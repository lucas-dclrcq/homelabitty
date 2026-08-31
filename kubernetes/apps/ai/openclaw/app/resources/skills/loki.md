---
name: loki
description: Query Grafana Loki (LogQL) for container logs and Kubernetes event history when diagnosing an incident
metadata:
  { "openclaw": { "emoji": "📜", "homepage": "https://grafana.com/docs/loki/latest/query/" } }
user-invocable: true
disable-model-invocation: false
---

Use this skill when an investigation needs actual log lines. Alloy ships all
container logs (and Kubernetes events) into Loki. The kubernetes MCP tools can
read a *live* pod's logs, but Loki is the only way to see logs from a pod that
has already been replaced — which is usually the interesting one.

## Endpoint

Base URL (in-cluster, `auth_enabled: false`, so no org header and no auth):
`http://loki-headless.observability.svc.cluster.local:3100`

Query with `curl` from the exec tool and URL-encode the LogQL
(`curl --data-urlencode`). There is no `jq` in this container — pipe JSON
through `python3 -m json.tool`, or `python3 -c` for anything sharper.

## Stream labels

Set by Alloy on every line: `cluster` (always `main`), `namespace`, `pod`,
`container`, `node`, `app` (from `app.kubernetes.io/name`), `job`
(`<namespace>/<container>`).

## Common API calls

Recent lines for a pod (last hour, newest first):

```sh
LOKI=http://loki-headless.observability.svc.cluster.local:3100
curl -sG "$LOKI/loki/api/v1/query_range" \
  --data-urlencode 'query={namespace="media", pod=~"jellyfin.*"}' \
  --data-urlencode "start=$(date -d '1 hour ago' +%s)000000000" \
  --data-urlencode "end=$(date +%s)000000000" \
  --data-urlencode 'limit=200' \
  --data-urlencode 'direction=backward'
```

Errors across an app, by its `app.kubernetes.io/name` label:

```sh
curl -sG "$LOKI/loki/api/v1/query_range" \
  --data-urlencode 'query={app="sonarr"} |~ "(?i)(error|panic|fatal)"' \
  --data-urlencode "start=$(date -d '30 minutes ago' +%s)000000000" \
  --data-urlencode "end=$(date +%s)000000000" \
  --data-urlencode 'limit=100'
```

Kubernetes events (Alloy forwards the event stream as logs):

```sh
curl -sG "$LOKI/loki/api/v1/query_range" \
  --data-urlencode 'query={job="integrations/kubernetes/eventhandler"} |= "Warning"' \
  --data-urlencode "start=$(date -d '30 minutes ago' +%s)000000000" \
  --data-urlencode "end=$(date +%s)000000000" \
  --data-urlencode 'limit=100'
```

Discover what is queryable:
`GET /loki/api/v1/labels`
`GET /loki/api/v1/label/namespace/values`
`GET /loki/api/v1/series?match[]={namespace="ai"}`

## LogQL notes

- Timestamps in `query_range` are **nanoseconds**; append `000000000` to a
  `date +%s` value.
- Start from a tight stream selector (`{namespace=…, pod=…}`) and only then add
  line filters — an unselective query will be rejected or time out.
- `|= "text"` is a plain substring filter and is far cheaper than a regex.
- `|~` is a case-sensitive RE2 regex match; prefix `(?i)` for case-insensitive.
- Count errors over time: `sum(count_over_time({namespace="media"} |= "error" [5m]))`

## Tips

- Correlate with `kube_pod_container_status_last_terminated_reason` from the
  prometheus skill to find *why* a pod died, then read its final lines here.
- Deployment pod names change on every rollout — match on `{app="…"}` or a pod
  name regex rather than an exact pod name.
