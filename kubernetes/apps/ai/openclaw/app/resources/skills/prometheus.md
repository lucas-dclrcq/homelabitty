---
name: prometheus
description: Query the cluster Prometheus HTTP API (PromQL) to inspect metrics, alerts, and targets during investigations
metadata:
  { "openclaw": { "emoji": "📊", "homepage": "https://prometheus.io/docs/prometheus/latest/querying/api/" } }
user-invocable: true
disable-model-invocation: false
---

Use this skill whenever you need live or historical metrics from the hoohoot
cluster's Prometheus — triaging an alert, confirming a symptom, or checking a
trend.

## Endpoint

Base URL (in-cluster, no auth):
`http://prometheus-operated.observability.svc.cluster.local:9090`

Alertmanager (read-only inspection):
`http://alertmanager-operated.observability.svc.cluster.local:9093`

Query them with `curl` from the exec tool. Always URL-encode the query
(`curl --data-urlencode`). There is no `jq` in this container — pipe JSON
through `python3 -m json.tool`, or `python3 -c` for anything sharper.

## Common API calls

Instant query (current value):

```sh
curl -sG http://prometheus-operated.observability.svc.cluster.local:9090/api/v1/query \
  --data-urlencode 'query=up == 0'
```

Range query (trend over a window; start/end are Unix timestamps in seconds —
compute them with `date +%s`):

```sh
curl -sG http://prometheus-operated.observability.svc.cluster.local:9090/api/v1/query_range \
  --data-urlencode 'query=rate(container_cpu_usage_seconds_total[5m])' \
  --data-urlencode "start=$(date -d '1 hour ago' +%s)" \
  --data-urlencode "end=$(date +%s)" \
  --data-urlencode 'step=60'
```

Currently firing alerts: `GET /api/v1/alerts`
Scrape targets / health:   `GET /api/v1/targets`
List metric names:         `GET /api/v1/label/__name__/values`
Active Alertmanager alerts: `GET /api/v2/alerts` (on the Alertmanager URL)
Active silences:            `GET /api/v2/silences` (on the Alertmanager URL)

## Useful PromQL for triage

- Pods restarting:        `increase(kube_pod_container_status_restarts_total[15m]) > 0`
- Pods not running:       `kube_pod_status_phase{phase!="Running",phase!="Succeeded"} == 1`
- OOMKilled containers:   `kube_pod_container_status_last_terminated_reason{reason="OOMKilled"}`
- Container memory vs limit: `container_memory_working_set_bytes / kube_pod_container_resource_limits{resource="memory"}`
- Node memory pressure:   `(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100`
- Node disk usage:        `(1 - node_filesystem_avail_bytes{fstype!~"tmpfs|overlay"} / node_filesystem_size_bytes) * 100`
- PVC nearly full:        `kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes > 0.85`
- Down scrape targets:    `up == 0`
- Ceph health:            `ceph_health_status` (0 OK, 1 WARN, 2 ERR)
- Flux not ready:         `gotk_reconcile_condition{type="Ready",status="False"} == 1`
- VolSync out of sync:    `volsync_volume_out_of_sync == 1`
- Per-pod CPU (cores):    `sum by (pod) (rate(container_cpu_usage_seconds_total{container!=""}[5m]))`

## Tips

- Scope queries with label matchers (e.g. `{namespace="rook-ceph"}`) to cut noise.
- Use `topk(10, ...)` to surface the worst offenders.
- Cluster nodes are `bee`, `burrich`, `chade`, `fitz`, `fool`, `nighteyes`.
