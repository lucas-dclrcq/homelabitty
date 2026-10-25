# fluent-bit

Node log collector. Replaces `victoria-logs-collector` (vlagent), which had no
way to derive a log level from an unstructured line: its only knobs are
`msgField`, `timeField`, `streamFields` and `decolorizeFields`.

Fluent Bit ships the same logs to the same place, and additionally writes a
`level` field, so `level` becomes a thing you can **query** (`| stats by
(level)`, alert rules) rather than something a Grafana datasource rule paints
on at display time.

## What it writes

Field names reproduce vlagent's exactly, so the logs already in VictoriaLogs
and every saved query keep matching across the cutover:

| Field                       | Source                                       |
| --------------------------- | -------------------------------------------- |
| `_msg`                      | `msg` / `message` / `log`, first one present |
| `_time`                     | the CRI timestamp of the line                |
| `kubernetes.pod_namespace`  | renamed from `namespace_name`                |
| `kubernetes.pod_name`       | as-is                                        |
| `kubernetes.container_name` | as-is                                        |
| `kubernetes.pod_node_name`  | renamed from `host`                          |
| `kubernetes.container_id`   | renamed from `docker_id`                     |
| `kubernetes.pod_labels.*`   | lifted from `kubernetes.labels`              |
| `output_stream`             | renamed from `stream` (stdout/stderr)        |
| `level`                     | **new** — see below                          |

`_stream_fields` is unchanged: namespace, pod, container, and the
`app.kubernetes.io/name` pod label.

## Where `level` comes from

Two paths, in this order:

1. **The app's own JSON.** `merge_log on` flattens a JSON line into the
   record, so an app that already logs `{"level":"info",...}` needs nothing.
   Roughly 45 workloads are in this case.
2. **A `fluentbit.io/parser` pod annotation** naming one of the parsers below.
   The kubernetes filter runs it against the raw line; a line that does not
   match passes through untouched (which is what the continuation lines of a
   stack trace want).

Either way the value is then normalised to one of `trace` `debug` `info`
`warn` `error` `fatal` by the `modify` filter chain in `app/helmrelease.yaml`
— it folds case, three-letter forms (`INF`, `WRN`), single letters (`I`, `W`,
`E`), `LOG`, `notice`, and pino's numeric levels (`30`, `40`, `50`).

## Parser catalogue

All of them capture **only** `level`; the message itself stays in `log`.

| Parser            | Matches                                     | Example line                                             |
| ----------------- | ------------------------------------------- | -------------------------------------------------------- |
| `level_logfmt`    | `level=xxx` anywhere                        | `time=... level=info msg="..."`                          |
| `level_bracket`   | a level inside brackets                     | `[Info] RssSync...`, `[10:31:12 INF] ...`, `log [DBG] :` |
| `level_tsword`    | timestamp, then the level as second token   | `2026-10-25T09:31:57Z  INFO atuin::...`                  |
| `level_python`    | timestamp, then the first level word        | `2026-10-25 09:28:44,469 - synapse... - INFO - ...`      |
| `level_tsbracket` | `[<anything>] LEVEL:`                       | `[2026-10-25 12:00:03.809] INFO: ...`                    |
| `level_leading`   | the line starts with the level              | `INFO:     192.168.1.16 - "GET / HTTP/1.1" 200`          |
| `level_klog`      | glog/klog letter prefix                     | `I1025 09:29:27.859871  1 reconciler.go:364]`            |
| `level_pgbouncer` | `[<pid>] LEVEL`                             | `2026-... UTC [7] LOG stats: ...`                        |
| `level_nestjs`    | NestJS, and the `[ts] LEVEL` immich variant | `[Nest] 7 - 10/25/2026 ... LOG [PersonService] ...`      |
| `level_gitea`     | Forgejo's single-letter bracket             | `2026/10/25 ... logger.go:75:func1() [W] router:`        |

Each pairing was checked against 25 real lines pulled from VictoriaLogs and
replayed through `fluent-bit 5.1.3`: 57 of the 67 workload/parser pairs match
on 90%+ of their lines. The rest land at 16–80%, and in every case the
unmatched lines are **continuation lines** — Java and
.NET stack traces, rocksdb statistics tables, multi-line SQL errors — which
carry no level of their own.

## Adding one for a new app

Put the annotation wherever the app's pod labels already live, so the
`defaultPodOptions` / `controllers.<n>.pod` override rule cannot drop it:

```yaml
defaultPodOptions:
    annotations:
        fluentbit.io/parser: level_logfmt
```

Use `fluentbit.io/parser_<container>` to scope it to one container of a
multi-container pod. If no catalogue entry fits, add a `[PARSER]` to
`customParsers` in `app/helmrelease.yaml` — because the annotation scopes it to
one workload, the regex can be as aggressive as that app needs.

## Not covered

- **Talos static pods** (`kube-apiserver`, `kube-controller-manager`,
  `kube-scheduler`) cannot carry an annotation from Flux. `kube-apiserver`
  already logs JSON with a level; `kube-controller-manager` does not, which is
  why `level_klog` is defined but currently unused.
- **Access logs** (envoy, haproxy, the nginx sidecars, element-web) have no
  level. Deriving one from the HTTP status is possible but has not been done.
- **ceph-osd and ceph-rgw**: their lines carry a numeric _verbosity_, not a
  severity. `level_bracket` catches the cluster-log lines (`log [DBG] :`) and
  leaves the rest without a level, which is the honest outcome.
- **Multi-line stack traces** are not joined. Fluent Bit can do it
  (`multiline.parser java`, `go`, `python`) but it has to be configured per
  app, and nothing depends on it today.

## Verifying a change

VictoriaLogs accepts `&debug=1` on any ingestion URL: it logs what it _would_
have stored and stores nothing. Useful to check field names and `_msg`
selection without polluting the index:

```sh
printf '%s\n' '{"date":"2026-10-25T16:00:00Z","msg":"hello","log":"raw","level":"INFO"}' \
  | curl -s -XPOST --data-binary @- \
    'http://victoria-logs.observability.svc.cluster.local:9428/insert/jsonline?_msg_field=msg,message,log&_time_field=date&debug=1'
kubectl -n observability logs victoria-logs-0 --tail=5
```

The rendered config can be checked without a cluster:

```sh
helm template fluent-bit oci://ocharted.hoohoot.org/fluent.github.io/helm-charts/fluent-bit \
  --version 0.58.3 -f <(yq '.spec.values' app/helmrelease.yaml) \
  | yq 'select(.kind=="ConfigMap" and .metadata.name=="fluent-bit").data' > /tmp/conf
docker run --rm -v /tmp/conf:/fluent-bit/etc/conf:ro cr.fluentbit.io/fluent/fluent-bit:5.1.3 \
  /fluent-bit/bin/fluent-bit --dry-run --config=/fluent-bit/etc/conf/fluent-bit.conf
```
