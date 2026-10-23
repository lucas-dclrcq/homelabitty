# Network policy architecture

Staged improvement backlog: [`TASKS.md`](./TASKS.md).

Cilium network policies, default-deny everywhere, **nothing implicit**. A pod
reaches a peer only if some policy names that flow. There is no "same
namespace" shortcut and no cluster-wide escape hatch.

Flows are opened in one of two ways:

- **Shared vocabulary** — a pod label matched by one of the
  CiliumClusterwideNetworkPolicies in this catalog. Use it for the handful of
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

The `netpol-baseline` component (`kubernetes/components/netpol-baseline`)
stamps a `baseline` CiliumNetworkPolicy into every enrolled namespace (ai,
auth, default, development, downloads, home, infrastructure, matrix, media,
network, observability, vault). **Enrolling a namespace means including the
component** from `kubernetes/apps/<ns>/kustomization.yaml`:

```yaml
components:
    - ../../components/common
    - ../../components/netpol-baseline
```

The directory's `namespace:` transformer stamps the CNP's namespace, so the
component itself ships the policy without one.

The baseline selects **all pods** with
`enableDefaultDeny` on both directions and re-opens exactly two things:

- **DNS** to kube-dns (egress)
- **the host entity** (ingress)

Everything else — **traffic between two pods of the same namespace included** —
has to be named by another policy.

The host rule is not a grant, it is the switch. Cilium enters default-deny for
a direction only when a rule that selects the endpoint **has a section for that
direction**; `enableDefaultDeny` can turn that off but never on. An egress-only
baseline therefore leaves ingress wide open (`Allow Ingress ANY` in the
endpoint's policy map) on every pod that no _other_ policy happens to select —
and since nothing is denied, audit mode shows nothing at all. `reserved:host`
is the harmless choice of section content: Cilium allows it unconditionally
anyway, which is also why kubelet health probes are unaffected.

Check it per endpoint with
`cilium-dbg endpoint list` — enrolled pods must read `audit-both` (or `both`
once enforced), never `audit-egress`.

System namespaces (kube-system, flux-system, rook-ceph, cert-manager,
external-secrets, kopiur-system, openebs-system, system-upgrade) are **not**
enrolled on purpose — they do not include the component: pods there are
unconstrained unless a clusterwide policy happens to select them.

## Layer 2 — label vocabulary (clusterwide policies)

### Egress labels (put on the _consumer_ pod)

| Pod label (`=allow`)                | Opens egress to                                                                                                                                                 |
| ----------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `egress.home.arpa/internet`         | the internet — `0.0.0.0/0` minus RFC1918, CGNAT and link-local, any port                                                                                        |
| `egress.home.arpa/internet-https`   | the same destinations, 443 only                                                                                                                                 |
| `egress.home.arpa/lan`              | the trusted LAN segment `192.168.1.0/24` (TrueNAS, UPS, NTP Pi, router), any port                                                                               |
| `egress.home.arpa/nas`              | TrueNAS alone, `192.168.1.70`, any port                                                                                                                         |
| `egress.home.arpa/router`           | the UniFi gateway alone, `192.168.1.1:443`                                                                                                                      |
| `egress.home.arpa/iot`              | the IoT VLAN `192.168.30.0/24` (appliances, Bambu printer, robot vacuum)                                                                                        |
| `egress.home.arpa/world`            | **last resort** — everything outside the cluster at once (internet + LAN + every VLAN). No app carries it                                                       |
| `egress.home.arpa/kubedns`          | kube-dns:53 (already in baseline; for pods in non-enrolled namespaces)                                                                                          |
| `egress.home.arpa/postgres`         | crunchy pods (instances + pgbouncer) :5432                                                                                                                      |
| `egress.home.arpa/mqtt`             | mosquitto :1883 (+ matching ingress on mosquitto)                                                                                                               |
| `egress.home.arpa/smtp`             | smtp-relay :2525 (+ matching ingress)                                                                                                                           |
| `egress.home.arpa/vault`            | vault :8200 (+ matching ingress)                                                                                                                                |
| `egress.home.arpa/ldap`             | authentik's LDAP outpost :3389/:6636 (apps authenticating over LDAP rather than OIDC)                                                                           |
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
| `egress.home.arpa/jellyfin`         | Jellyfin :8096 (the *arr apps' library refresh)                                                                                                                 |
| `egress.home.arpa/homelab-manager`  | homelab-manager API :8080 (the *arr apps' webhook notifications)                                                                                                |

kopiur mover Jobs (`<app>-<timestamp>`) are not labelled by us:
`platform/kopiur-mover.yaml` selects them on `app.kubernetes.io/managed-by: kopiur`
and opens the API server.

Most of these are **paired**: one clusterwide policy opens the consumer's
egress, a second one opens the service's ingress from pods carrying that same
label, so labelling the consumer is enough. That covers
`postgres`/`mqtt`/`smtp`/`vault`/`ldap`, `gateway-external`/`gateway-internal`
(the envoy pods accept hairpin calls from pods carrying the label) and the whole downloads stack
(`sonarr`/`radarr`/`lidarr`/`prowlarr`/`qbittorrent`/`sabnzbd`/`slskd`, one
`services/<name>.yaml` per service holding both halves).

The downloads labels work from any namespace — `media/seerr` and
`default/homelab-manager` use the same ones the *arr apps use between
themselves. `egress.home.arpa/sonarr` deliberately covers both Sonarr instances:
every consumer drives `sonarr` and `sonarr-anime` together.

#### Outside the cluster: pick a destination, not "everything"

The first six labels above carve up what used to be a single
`egress.home.arpa/world`. They are plain CIDR rules, and they **compose** —
home-assistant carries `internet` _and_ `iot`, blackbox-exporter-lan carries
`internet`, `lan` _and_ `iot`:

| Label            | CIDR                                                                            | Ports |
| ---------------- | ------------------------------------------------------------------------------- | ----- |
| `internet`       | `0.0.0.0/0` except `10/8`, `172.16/12`, `192.168/16`, `100.64/10`, `169.254/16` | any   |
| `internet-https` | the same                                                                        | 443   |
| `lan`            | `192.168.1.0/24`                                                                | any   |
| `nas`            | `192.168.1.70/32` (TrueNAS)                                                     | any   |
| `router`         | `192.168.1.1/32` (UniFi gateway)                                                | 443   |
| `iot`            | `192.168.30.0/24`                                                               | any   |

Three things to know about CIDR rules in Cilium:

- **They never match in-cluster peers.** Pods keep their own security identity
  and nodes are the `host`/`remote-node` entities, so the private ranges in
  `internet`'s `except` list cost nothing in-cluster: they only carve the house
  network out of `0.0.0.0/0`. Conversely a `lan` label does **not** let a pod
  reach a node by its `192.168.1.1x` address — that needs the entities, which
  no vocabulary label exposes yet (TASKS.md phase 5).
- **The IPs are hardcoded**, like every other non-secret value in this repo
  (see `AGENTS.md`); they are not Flux substitutions.
- **The VPN and IoT NetworkAttachmentDefinitions bypass all of this.** A pod
  with a macvlan/ipvlan interface on `vpn0`/`iot0` (qbittorrent, slskd,
  blackbox-exporter-vpn) sends that traffic outside its Cilium endpoint. Its
  `eth0` egress still needs a label.

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
- **anything addressed by entity rather than by pod or CIDR** — no vocabulary
  label exposes `host`/`remote-node`/`kube-apiserver`, so a pod that talks to a
  node by address names the entity in its own policy: `allow-egress-vmagent`
  (host-network exporters) and `blackbox-exporter-lan` (ICMP probes of the six
  nodes)

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
        egress.home.arpa/internet: allow # it calls the internet
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
