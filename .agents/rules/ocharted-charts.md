# Serve a non-OCI Helm chart via ocharted

## When
- deploying a new app whose chart is only in a classic HTTP Helm repo (no OCI artifact)
- adding/replacing a chart source that is not `oci://`

## Rule
- ocharted (in `flux-system`) proxies classic Helm repos as OCI. Reachable in-cluster at
  `ocharted.flux-system.svc.cluster.local:8080`.
- Per chart, create an `OCIRepository` with
  `url: oci://ocharted.flux-system.svc.cluster.local:8080/<upstream-host>/<path>/<chart>` and
  `ref.tag: <version>`, then point the HelmRelease at it via `chartRef` (name == release name).
- Add one Renovate packageRule per upstream in `.renovate/ocharted.json5`
  (`overrideDatasource: helm` + `registryUrls: [<upstream>]`) — hosted Renovate cannot reach the
  internal proxy, so it must re-resolve versions from upstream.

## Reference
- kubernetes/apps/flux-system/ocharted/ (deployment; chart `oci://ghcr.io/home-operations/charts/ocharted`)
- kubernetes/apps/kube-system/metrics-server/ (example migrated app)
- .renovate/ocharted.json5
- https://github.com/home-operations/ocharted (URL scheme + Renovate topology docs)
