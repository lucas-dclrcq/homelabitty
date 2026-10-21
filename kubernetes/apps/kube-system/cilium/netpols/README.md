# Network policy architecture

Cilium network policies, default-deny everywhere, **nothing implicit**. A pod
reaches a peer only if some policy names that flow. There is no "same
namespace" shortcut and no cluster-wide escape hatch.

Flows are opened in one of two ways:

- **Shared vocabulary** — a pod label matched by one of the
  CiliumClusterwideNetworkPolicies in this directory. Use it for the handful of
  things half the cluster talks to (the gateways, Postgres, MQTT, Vault, SMTP,
  the API server, the internet).
- **A policy shipped with the app** — a CiliumNetworkPolicy that names the
  peers directly. Use it for everything else: same-namespace components, and
  one-off cross-namespace calls. It lives next to the app (`rawResources` in
  the HelmRelease values for app-template charts, a `ciliumnetworkpolicy.yaml`
  in the app directory otherwise) so it is pruned together with the app.

## Current state: AUDIT MODE

`policyAuditMode: true` is set on the Cilium HelmRelease
(`../app/helmrelease.yaml`). **Nothing is enforced**: flows that would be
denied are forwarded and recorded as `verdict=AUDIT`.

Workflow to reach enforcement:

1. Watch the **Cilium Policy Audit** Grafana dashboard (`cilium-policy-audit`).
2. For each audited flow, open it: add a vocabulary label if one fits, or add
   the peer to the app's own policy (the two tables on the dashboard tell you
   which side is missing a rule).
3. For details beyond the metric (exact ports, DNS names):
   `cilium hubble observe --verdict AUDIT -f` (or hubble UI).
4. When the dashboard stays clean, flip `policyAuditMode` to `false`.

## Layer 1 — baseline (per-namespace default deny)

`baseline.yaml` stamps a `baseline` CiliumNetworkPolicy into every enrolled
namespace (ai, auth, default, development, downloads, home, infrastructure,
matrix, media, network, observability, vault). It selects **all pods** with
`enableDefaultDeny` on both directions and re-opens exactly one thing:

- **DNS** to kube-dns

Everything else — **traffic between two pods of the same namespace included** —
has to be named by another policy. kubelet health probes come from the host
entity, which Cilium always allows, so they are unaffected.

System namespaces (kube-system, flux-system, rook-ceph, cert-manager,
external-secrets, kopiur-system, openebs-system, system-upgrade) are **not**
enrolled on purpose: pods there are unconstrained unless a clusterwide policy
happens to select them.

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
| `egress.home.arpa/sonarr`           | the Sonarr instances (`sonarr` + `sonarr-anime`) :80                                                                                                            |
| `egress.home.arpa/radarr`           | Radarr :80                                                                                                                                                      |
| `egress.home.arpa/lidarr`           | Lidarr :8686                                                                                                                                                    |
| `egress.home.arpa/prowlarr`         | Prowlarr :80                                                                                                                                                    |
| `egress.home.arpa/qbittorrent`      | qBittorrent WebUI API :8080                                                                                                                                     |
| `egress.home.arpa/sabnzbd`          | SABnzbd API :80                                                                                                                                                 |
| `egress.home.arpa/slskd`            | slskd API :80                                                                                                                                                   |

Most of these are **paired**: one clusterwide policy opens the consumer's
egress, a second one opens the service's ingress from pods carrying that same
label, so labelling the consumer is enough. That covers
`postgres`/`mqtt`/`smtp`/`vault` and the whole downloads stack
(`sonarr`/`radarr`/`lidarr`/`prowlarr`/`qbittorrent`/`sabnzbd`/`slskd`, one
`allow-<service>.yaml` per service holding both halves).

The downloads labels work from any namespace — `media/seerr` and
`default/homelab-manager` use the same ones the *arr apps use between
themselves. `egress.home.arpa/sonarr` deliberately covers both Sonarr instances:
every consumer drives `sonarr` and `sonarr-anime` together.

### Ingress labels (put on the _receiving_ pod)

| Pod label (`=allow`)                 | Accepts ingress from                                                                              |
| ------------------------------------ | ------------------------------------------------------------------------------------------------- |
| `ingress.home.arpa/gateway-external` | external envoy gateway (HTTPRoute/TCPRoute)                                                       |
| `ingress.home.arpa/gateway-internal` | internal envoy gateway                                                                            |
| `ingress.home.arpa/prometheus`       | vmagent (ServiceMonitor/PodMonitor scraping)                                                      |
| `ingress.home.arpa/apiserver`        | kube-apiserver (admission webhooks)                                                               |
| `ingress.home.arpa/world`            | outside the cluster (LoadBalancer services used from the LAN: mosquitto, smtp-relay, forgejo ssh) |

The gateway labels are the **single source of truth for the data plane**: the
envoy pods' own egress is `toEndpoints: ingress.home.arpa/gateway-<name>`
(`apps/network/envoy-gateway/config/ciliumclusterwidenetworkpolicy.yaml`), so a
backend that is not labelled is simply unreachable through its route.

## Layer 3 — the app's own policy

Everything the vocabulary does not cover. Both sides of a flow need a rule,
since both ends are default-deny:

- same-namespace components — `ai/litellm` ↔ its MCP servers, `development/harbor`
  and `development/temporal` meshes, `matrix` (HAProxy/Synapse/MAS/Valkey),
  `vault` raft peers, `infrastructure` (crunchy replication/pgBackRest), the
  `observability` stack
- one-off cross-namespace calls — `default/kalimba` → Temporal,
  `development/pacman` → the Pushgateway, `downloads/droppedneedle` → Navidrome

When a service has several consumers, prefer a label pair over a bespoke policy:
that is what the downloads stack does, and it is why none of the *arr apps ship
a policy of their own.

Dragonfly is handled by the component that creates it:
`kubernetes/components/dragonfly/ciliumnetworkpolicy.yaml` ships the instance's
policy and the matching client rule for `app.kubernetes.io/name: ${APP}`.

## Cheat sheet: a new app

1. Labels for the shared peers:

```yaml
defaultPodOptions:
    labels:
        ingress.home.arpa/gateway-external: allow # it has an HTTPRoute on `external`
        ingress.home.arpa/prometheus: allow # it has a ServiceMonitor
        egress.home.arpa/postgres: allow # it uses the crunchy cluster
        egress.home.arpa/gateway-external: allow # it does OIDC against authentik
        egress.home.arpa/world: allow # it calls the internet
```

2. A policy for anything else it talks to, including its own sidecars and
   co-located services. For an app-template chart:

```yaml
rawResources:
    netpol:
        manifest:
            apiVersion: cilium.io/v2
            kind: CiliumNetworkPolicy
            spec:
                description: "<what this opens and why>"
                endpointSelector:
                    matchLabels:
                        app.kubernetes.io/name: myapp
                egress:
                    - toEndpoints:
                          - matchLabels:
                                app.kubernetes.io/name: mysidecar
                      toPorts:
                          - ports:
                                - port: "8080"
                                  protocol: TCP
```

and the mirror `ingress` rule on the peer. DNS needs no rule.

## Flipping to enforcement

1. `Cilium Policy Audit` dashboard clean for a few days (audit rate = 0).
2. Set `policyAuditMode: false` in `../app/helmrelease.yaml`.
3. The `cilium-dropped-flows` dashboard (`cilium-policy-denied`) then shows
   real drops; the audit dashboard's "Real Drops" stat must stay green.

Rollback at any time: set `policyAuditMode: true` back (agent rollout, no
traffic interruption), or `kubectl -n kube-system exec ds/cilium -- cilium
config PolicyAuditMode=true` per node for instant effect without a rollout.
