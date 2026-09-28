# Serve a non-OCI Helm chart via ocharted

## When
- deploying a new app whose chart is only in a classic HTTP Helm repo (no OCI artifact)
- adding/replacing a chart source that is not `oci://`

## Rule
- ocharted (in `flux-system`) proxies classic Helm repos as OCI. Exposed publicly at
  `ocharted.hoohoot.org` behind basic auth (`ocharted-secret`); in-cluster Flux bypasses auth via
  `bypassNetworks` (pod + service CIDRs).
- Per chart, create an `OCIRepository` with
  `url: oci://ocharted.hoohoot.org/<upstream-host>/<path>/<chart>` and `ref.tag: <version>`, then
  point the HelmRelease at it via `chartRef` (name == release name).
- No per-upstream Renovate config needed: hosted Renovate reaches the proxy directly and
  authenticates via the single `hostRules` entry in `.renovate/ocharted.json5`.

## Reference
- kubernetes/apps/flux-system/ocharted/ (deployment + ExternalSecret; chart `oci://ghcr.io/home-operations/charts/ocharted`)
- kubernetes/apps/kube-system/metrics-server/ (example migrated app)
- .renovate/ocharted.json5
- https://github.com/home-operations/ocharted (URL scheme + Renovate topology docs)
