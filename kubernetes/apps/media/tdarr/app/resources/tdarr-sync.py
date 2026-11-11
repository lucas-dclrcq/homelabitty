#!/usr/bin/env python3
"""Queue the files of tagged Sonarr/Radarr items into a Tdarr library.

Tdarr has no notion of Sonarr/Radarr tags, so its library is configured with
folder watching and scheduled scans OFF: nothing enters it on its own. This
job is the only way in. It reads every series/movie carrying ARR_TAG in each
*arr instance, keeps the files that are not HEVC/AV1 yet (according to the
*arr's own media info), and pushes their paths to Tdarr's scan API.

Removing the tag stops new files from being sent; files already queued stay in
Tdarr's queue until cleared there.

Environment:
  TDARR_URL          e.g. http://tdarr.media.svc.cluster.local:8265
  TDARR_API_KEY      x-api-key for Tdarr (auth=true)
  TDARR_LIBRARY_ID   library id, from the Tdarr UI URL (/libraries/<id>/...).
                     Empty -> the job only reports what it would send.
  ARR_TAG            tag label to look for (default: tdarr)
  DRY_RUN            "true" -> report only, send nothing
  SONARR_URL / SONARR_API_KEY, SONARR_ANIME_URL / SONARR_ANIME_API_KEY,
  RADARR_URL / RADARR_API_KEY   instances without both values are skipped
"""

import json
import os
import sys
import urllib.error
import urllib.request

# Codecs that are already at least as efficient as the HEVC target. Values are
# Sonarr/Radarr mediaInfo.videoCodec, lowercased.
ALREADY_EFFICIENT = {"x265", "h265", "hevc", "av1"}
BATCH_SIZE = 50


def log(msg):
    print(msg, flush=True)


def request(method, url, headers=None, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Accept", "application/json")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    for key, value in (headers or {}).items():
        req.add_header(key, value)
    with urllib.request.urlopen(req, timeout=60) as resp:
        raw = resp.read()
        if not raw:
            return None
        try:
            return json.loads(raw)
        except json.JSONDecodeError:
            return raw.decode(errors="replace")


class Arr:
    def __init__(self, name, kind, url, api_key):
        self.name = name
        self.kind = kind  # "sonarr" | "radarr"
        self.url = url.rstrip("/")
        self.headers = {"X-Api-Key": api_key}

    def get(self, path):
        return request("GET", f"{self.url}/api/v3/{path}", self.headers)

    def tag_id(self, label):
        for tag in self.get("tag"):
            if tag["label"].strip().lower() == label.lower():
                return tag["id"]
        return None

    def candidate_files(self, tag_id):
        """Yield (item title, path, size, codec) for every file of tagged items."""
        if self.kind == "sonarr":
            for series in self.get("series"):
                if tag_id not in series.get("tags", []):
                    continue
                for ep in self.get(f"episodefile?seriesId={series['id']}"):
                    codec = (ep.get("mediaInfo") or {}).get("videoCodec") or "?"
                    yield series["title"], ep["path"], ep.get("size", 0), codec
        else:
            for movie in self.get("movie"):
                if tag_id not in movie.get("tags", []) or not movie.get("hasFile"):
                    continue
                mf = movie["movieFile"]
                codec = (mf.get("mediaInfo") or {}).get("videoCodec") or "?"
                yield movie["title"], mf["path"], mf.get("size", 0), codec


def gib(n):
    return f"{n / 1024**3:.1f} GiB"


def main():
    tag = os.environ.get("ARR_TAG", "tdarr")
    tdarr_url = os.environ["TDARR_URL"].rstrip("/")
    tdarr_key = os.environ.get("TDARR_API_KEY", "")
    library_id = os.environ.get("TDARR_LIBRARY_ID", "").strip()
    dry_run = os.environ.get("DRY_RUN", "false").lower() == "true" or not library_id
    if not library_id:
        log("TDARR_LIBRARY_ID is empty: report only, nothing is sent to Tdarr.")

    instances = []
    for name, kind, prefix in (
        ("sonarr", "sonarr", "SONARR"),
        ("sonarr-anime", "sonarr", "SONARR_ANIME"),
        ("radarr", "radarr", "RADARR"),
    ):
        url, key = os.environ.get(f"{prefix}_URL"), os.environ.get(f"{prefix}_API_KEY")
        if url and key:
            instances.append(Arr(name, kind, url, key))
        else:
            log(f"[{name}] not configured, skipped")

    to_send, failures = [], 0
    for arr in instances:
        try:
            tag_id = arr.tag_id(tag)
            if tag_id is None:
                log(f"[{arr.name}] no tag named '{tag}', nothing to do")
                continue
            per_item, skipped = {}, 0
            for title, path, size, codec in arr.candidate_files(tag_id):
                if codec.lower() in ALREADY_EFFICIENT:
                    skipped += 1
                    continue
                count, total = per_item.get(title, (0, 0))
                per_item[title] = (count + 1, total + size)
                to_send.append(path)
            for title, (count, total) in sorted(per_item.items()):
                log(f"[{arr.name}] {title}: {count} file(s), {gib(total)}")
            log(f"[{arr.name}] {sum(c for c, _ in per_item.values())} file(s) to queue, "
                f"{gib(sum(t for _, t in per_item.values()))}; {skipped} already HEVC/AV1")
        except (urllib.error.URLError, KeyError, TypeError) as exc:
            failures += 1
            log(f"[{arr.name}] ERROR: {exc}")

    log(f"Total: {len(to_send)} file(s) to queue in Tdarr")
    if dry_run or not to_send:
        return 1 if failures else 0

    headers = {"x-api-key": tdarr_key} if tdarr_key else {}
    for i in range(0, len(to_send), BATCH_SIZE):
        batch = to_send[i : i + BATCH_SIZE]
        body = {"data": {"scanConfig": {
            "dbID": library_id,
            "arrayOrPath": batch,
            "mode": "scanFolderWatcher",
        }}}
        try:
            request("POST", f"{tdarr_url}/api/v2/scan-files", headers, body)
            log(f"[tdarr] sent {i + len(batch)}/{len(to_send)}")
        except urllib.error.HTTPError as exc:
            failures += 1
            log(f"[tdarr] ERROR {exc.code}: {exc.read().decode(errors='replace')[:500]}")
        except urllib.error.URLError as exc:
            failures += 1
            log(f"[tdarr] ERROR: {exc}")

    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
