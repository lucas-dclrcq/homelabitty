# Network policy architecture

Label-driven Cilium network policies. Apps open the flows they need by putting
labels on their **pods** (`defaultPodOptions.labels` for app-template charts,
`podLabels`/pod metadata for everything else) — no per-app policy files for the
common cases.

## Current state: AUDIT MODE

`policyAuditMode: true` is set on the Cilium HelmRelease
(`../app/helmrelease.yaml`). **Nothing is enforced**: flows that would be
denied are forwarded and recorded as `verdict=AUDIT`.

Workflow to reach enforcement:

1. Watch the **Cilium Policy Audit** Grafana dashboard (`cilium-policy-audit`).
2. For each audited flow, add the right label to the right pod (the two tables
   on the dashboard tell you which side needs a label).
3. For details beyond the metric (exact ports, DNS names):
   `cilium hubble observe --verdict AUDIT -f` (or hubble UI).
4. When the dashboard stays clean, flip `policyAuditMode` to `false`.

## Layer 1 — baseline (per-namespace default deny)

`baseline.yaml` stamps a `baseline` CiliumNetworkPolicy into every enrolled
namespace (ai, auth, default, development, downloads, home, infrastructure,
matrix, media, network, observability, vault). It selects **all pods**, which
flips them into default-deny for both directions, and re-allows with no labels:

- **same-namespace traffic** (app ↔ dragonfly, sidecars, co-located services)
- **DNS** to kube-dns
- kubelet health probes are always allowed by Cilium (host entity)

System namespaces (kube-system, flux-system, rook-ceph, cert-manager,
external-secrets, kopiur-system, openebs-system, system-upgrade) are **not**
enrolled on purpose.

## Layer 2 — label vocabulary (clusterwide policies)

### Egress labels (put on the _consumer_ pod)

| Pod label (`=allow`)                | Opens egress to                                                                                                                                                 |
| ----------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `egress.home.arpa/world`            | everything outside the cluster (internet + LAN)                                                                                                                 |
| `egress.home.arpa/kubedns`          | kube-dns:53 (already in baseline; for pods in non-enrolled namespaces)                                                                                          |
| `egress.home.arpa/postgres`         | crunchy pods (instances + pgbouncer) :5432                                                                                                                      |
| `egress.home.arpa/mqtt`             | mosquitto :1883 (+ matching ingress on mosquitto)                                                                                                               |
| `egress.home.arpa/smtp`             | smtp-relay :2525 (+ matching ingress)                                                                                                                           |
| `egress.home.arpa/vault`            | vault :8200 (+ matching ingress)                                                                                                                                |
| `egress.home.arpa/apiserver`        | kube-apiserver (operators, patroni, controllers)                                                                                                                |
| `egress.home.arpa/gateway-external` | external envoy pods — needed for **OIDC hairpin** (app calls `auth.<domain>` which resolves to the gateway LB) and any call to a public hostname of the cluster |
| `egress.home.arpa/gateway-internal` | internal envoy pods — calls to internal hostnames (blackbox probes of `*.hoohoot.xyz`)                                                                          |
| `egress.home.arpa/cluster`          | anything in-cluster (escape hatch: vmagent, envoy, cross-namespace API consumers)                                                                               |

The `postgres`/`mqtt`/`smtp`/`vault` labels are **paired**: one clusterwide
policy opens the consumer's egress, a second one opens the service's ingress
from pods carrying that same label. Labeling the consumer is enough.

### Ingress labels (put on the _receiving_ pod)

| Pod label (`=allow`)                 | Accepts ingress from                                                                              |
| ------------------------------------ | ------------------------------------------------------------------------------------------------- |
| `ingress.home.arpa/gateway-external` | external envoy gateway (HTTPRoute/TCPRoute)                                                       |
| `ingress.home.arpa/gateway-internal` | internal envoy gateway                                                                            |
| `ingress.home.arpa/prometheus`       | vmagent (ServiceMonitor/PodMonitor scraping)                                                      |
| `ingress.home.arpa/apiserver`        | kube-apiserver (admission webhooks)                                                               |
| `ingress.home.arpa/world`            | outside the cluster (LoadBalancer services used from the LAN: mosquitto, smtp-relay, forgejo ssh) |
| `ingress.home.arpa/cluster`          | anything in-cluster (escape hatch: pushgateway, victoria-logs)                                    |

## Layer 3 — per-app CiliumNetworkPolicy

Only for flows the vocabulary can't express (odd ports, specific peers).
Examples: `default/atuin`, `default/bambuddy`, `home/mqtt2prometheus`.

## Cheat sheet: labeling a new app

```yaml
defaultPodOptions:
    labels:
        ingress.home.arpa/gateway-external: allow # it has an HTTPRoute on `external`
        ingress.home.arpa/prometheus: allow # it has a ServiceMonitor
        egress.home.arpa/postgres: allow # it uses the crunchy cluster
        egress.home.arpa/gateway-external: allow # it does OIDC against authentik
        egress.home.arpa/world: allow # it calls the internet
```

Intra-namespace (dragonfly, sidecars) and DNS need no labels.

## Flipping to enforcement

1. `Cilium Policy Audit` dashboard clean for a few days (audit rate = 0).
2. Set `policyAuditMode: false` in `../app/helmrelease.yaml`.
3. The `cilium-dropped-flows` dashboard (`cilium-policy-denied`) then shows
   real drops; the audit dashboard's "Real Drops" stat must stay green.

Rollback at any time: set `policyAuditMode: true` back (agent rollout, no
traffic interruption), or `kubectl -n kube-system exec ds/cilium -- cilium
config PolicyAuditMode=true` per node for instant effect without a rollout.
