#!/bin/sh
# Fill the tiles claim used by the Martin tile server:
#
#   /tiles/basemap.pmtiles   the France extract of the Protomaps OpenStreetMap
#                            basemap (large and gitignored upstream)
#   /tiles/fonts/*.ttf       the Noto Sans faces `styles/bookman.json` needs
#
# This mirrors `scripts/fetch-basemap.sh` in the bookman repository, but runs
# with the busybox tooling of a plain Alpine image, so the Job needs no root and
# no package install. `wget --spider` (a HEAD request) is used to probe the
# daily builds, because a `206 Partial Content` reply to a ranged GET is an
# error for wget.
#
# Idempotent: present files are left alone, so re-running the Job (or deleting
# it to rebuild) is safe.

set -eu

tiles=/tiles
bbox="${BASEMAP_BBOX:--5.6,41.0,9.9,51.5}"
maxzoom="${BASEMAP_MAXZOOM:-14}"

mkdir -p "$tiles/fonts"

# --- fonts -----------------------------------------------------------------
for font in NotoSans-Regular.ttf NotoSans-Bold.ttf NotoSans-Italic.ttf NotoSans-Medium.ttf; do
  dest="$tiles/fonts/$font"
  if [ -s "$dest" ]; then
    echo "font present: $font"
    continue
  fi
  echo "fetching font: $font"
  wget -q -O "$dest.tmp" \
    "https://github.com/notofonts/noto-fonts/raw/main/hinted/ttf/NotoSans/$font"
  mv "$dest.tmp" "$dest"
done

# --- basemap ---------------------------------------------------------------
if [ -s "$tiles/basemap.pmtiles" ]; then
  echo "basemap already present, nothing to do"
  exit 0
fi

# The Protomaps daily builds are only retained for a short window, so the most
# recent one that still answers is discovered rather than pinned.
build=""
i=0
while [ "$i" -le 14 ]; do
  d="$(date -u -d "@$(( $(date +%s) - i * 86400 ))" +%Y%m%d)"
  if wget -q --spider "https://build.protomaps.com/$d.pmtiles"; then
    build="$d"
    break
  fi
  i=$((i + 1))
done
[ -n "$build" ] || { echo "no Protomaps build found" >&2; exit 1; }

case "$(uname -m)" in
  x86_64) arch=x86_64 ;;
  aarch64 | arm64) arch=arm64 ;;
  *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

version="$(wget -qO- https://api.github.com/repos/protomaps/go-pmtiles/releases/latest \
  | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p' | head -n1)"
[ -n "$version" ] || { echo "could not determine the go-pmtiles release version" >&2; exit 1; }

echo "extracting bbox=$bbox maxzoom=$maxzoom from $build.pmtiles (go-pmtiles $version)"
wget -qO /tmp/pmtiles.tgz \
  "https://github.com/protomaps/go-pmtiles/releases/download/v${version}/go-pmtiles_${version}_Linux_${arch}.tar.gz"
tar -xzf /tmp/pmtiles.tgz -C /tmp

# Write beside the final name and move on success, so an interrupted run never
# looks like a complete archive (the presence check above is size-based).
/tmp/pmtiles extract "https://build.protomaps.com/$build.pmtiles" \
  "$tiles/basemap.pmtiles.part" --bbox="$bbox" --maxzoom="$maxzoom"
mv "$tiles/basemap.pmtiles.part" "$tiles/basemap.pmtiles"
echo "wrote $tiles/basemap.pmtiles"
