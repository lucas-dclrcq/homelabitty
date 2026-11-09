# Network policy architecture

Staged improvement backlog: [`TASKS.md`](./TASKS.md).

Cilium network policies, default-deny everywhere, **nothing implicit**. A pod
reaches a peer only if some policy names that flow. There is no "same
namespace" shortcut and no cluster-wide escape hatch.

Flows are opened in one of two ways:

- **Shared vocabulary** — a pod label matched by a
  CiliumClusterwideNetworkPolicy. Use it for the handful of things half the
  cluster talks to (the gateways, Postgres, MQTT, Vault, SMTP, the API server,
  the internet). The label pair of a service lives **next to the app that owns
  it**; only the vocabulary with no owning app stays in this catalog — see
  [Where the policies live](#where-the-policies-live).
- **A policy shipped with the app** — a CiliumNetworkPolicy that names the
  peers directly. Use it for everything else: same-namespace components, and
  one-off cross-namespace calls. It lives next to the app, as a
  `ciliumnetworkpolicy.yaml` listed in the app's `kustomization.yaml`, so it is
  pruned together with the app. **Never** as `rawResources` inside the
  HelmRelease: a policy buried in Helm values is invisible to a `grep` for the
  kind, is not rendered by `kustomize build`, and cannot be read next to the
  pair it mirrors.

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
network, observability, security, vault). **Enrolling a namespace means
including the component** from `kubernetes/apps/<ns>/kustomization.yaml`:

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
- **the host and remote-node entities** (ingress)

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

`remote-node` sits next to it for the same reason. With
`enable-remote-node-identity` a packet from **another** node is not `host`, it
is `remote-node`, and the two are not interchangeable: the aggregated API
services (`keda-operator-metrics-apiserver`) were audited on ingress from
`reserved:remote-node` with an otherwise correct `ingress.home.arpa/apiserver`
label, because the caller sat on a different node. Node-sourced traffic is
infrastructure wherever the node is.

Check it per endpoint with
`cilium-dbg endpoint list` — enrolled pods must read `audit-both` (or `both`
once enforced), never `audit-egress`.

System namespaces (kube-system, flux-system, rook-ceph, cert-manager,
external-secrets, kopiur-system, openebs-system, system-upgrade) are **not**
enrolled on purpose — they do not include the component: pods there are
unconstrained unless a clusterwide policy happens to select them.

## Where the policies live

A policy sits next to the thing that owns it, so it is pruned with it and
reviewed in the same diff:

| Policy                                  | Lives in                                                                             |
| --------------------------------------- | ------------------------------------------------------------------------------------ |
| per-namespace default-deny baseline     | `kubernetes/components/netpol-baseline` (a component each ns includes)               |
| a service's label pair (both halves)    | the owning app, `kubernetes/apps/<ns>/<app>/app/ciliumclusterwidenetworkpolicy.yaml` |
| external destinations (CIDR labels)     | `netpols/destinations/` — no owning app                                              |
| entity-backed labels (apiserver, world) | `netpols/platform/` — no owning app                                                  |
| an app's own peers                      | the app, `kubernetes/apps/<ns>/<app>/app/ciliumnetworkpolicy.yaml`                   |

So this catalog holds only what **no single app owns**: the CIDR destinations
and the two entity-backed labels (the API server, and `world`/`remote-node` for
LoadBalancer services reached from the LAN). Everything else ships with the app
that owns it — kube-dns with `coredns`, the gateway data plane with
`envoy-gateway`, prometheus scraping with `victoria-metrics-stack`, and the
operator-managed pods that cannot carry our labels with their operator
(`dragonfly`, `kopiur`).

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
| `egress.home.arpa/alertmanager`     | vmalertmanager :9093, the Alertmanager API (karma)                                                                                                              |
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
| `egress.home.arpa/navidrome`        | Navidrome :8080, the Subsonic API (droppedneedle)                                                                                                               |
| `egress.home.arpa/home-assistant`   | Home Assistant :8123, the REST API (bambuddy, the litellm MCP server)                                                                                           |
| `egress.home.arpa/matrix-synapse`   | the Matrix client-server API :8008, i.e. the matrix-stack HAProxy front (the four mautrix bridges, homelab-manager)                                             |
| `egress.home.arpa/pushgateway`      | prometheus-pushgateway :9091 (batch jobs pushing run metrics: pacman-sync)                                                                                      |

kopiur mover Jobs (`<app>-<timestamp>`) are not labelled by us: the policy
shipped by `kopiur-system/kopiur/app` selects them on
`app.kubernetes.io/managed-by: kopiur` and opens the API server.

Most of these are **paired**: one clusterwide policy opens the consumer's
egress, a second one opens the service's ingress from pods carrying that same
label, so labelling the consumer is enough. That covers
`postgres`/`mqtt`/`smtp`/`vault`/`ldap`/`alertmanager`,
`gateway-external`/`gateway-internal` (the envoy pods accept hairpin calls from
pods carrying the label), the whole downloads stack
(`sonarr`/`radarr`/`lidarr`/`prowlarr`/`qbittorrent`/`sabnzbd`/`slskd`) and the
media/home services reached across namespaces
(`jellyfin`/`navidrome`/`home-assistant`/`homelab-manager`/`matrix-synapse`/`pushgateway`).

Both halves of a pair live in **one file, in the owning app's directory**:
`kubernetes/apps/downloads/sonarr/app/ciliumclusterwidenetworkpolicy.yaml`
holds the egress that consumers get from `egress.home.arpa/sonarr` and the
ingress Sonarr accepts from them. Grepping the label name finds the pair.

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

| Pod label (`=allow`)                  | Accepts ingress from                                                                                           |
| ------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| `ingress.home.arpa/gateway-external`  | external envoy gateway (HTTPRoute/TCPRoute)                                                                    |
| `ingress.home.arpa/gateway-internal`  | internal envoy gateway                                                                                         |
| `ingress.home.arpa/prometheus`        | vmagent (ServiceMonitor/PodMonitor scraping)                                                                   |
| `ingress.home.arpa/apiserver`         | kube-apiserver (admission webhooks)                                                                            |
| `ingress.home.arpa/world`             | outside the cluster (LoadBalancer services used from the LAN: adguard DNS, mosquitto, smtp-relay, forgejo ssh) |
| `ingress.home.arpa/matrix-appservice` | Synapse's appservice transaction pushes, on 29318/29319/29334 (the four mautrix bridges)                       |

The gateway labels are the **single source of truth for the data plane**: the
envoy pods' own egress is `toEndpoints: ingress.home.arpa/gateway-<name>`
(`apps/network/envoy-gateway/config/ciliumclusterwidenetworkpolicy.yaml`), so a
backend that is not labelled is simply unreachable through its route.

## Layer 3 — the app's own policy

Everything the vocabulary does not cover. Both sides of a flow need a rule,
since both ends are default-deny:

- same-namespace components — `ai/litellm` ↔ its MCP servers and the `headroom`
  guardrail, `development/harbor` and `development/temporal` meshes,
  `development/forgejo-runner` ↔ its CI job pods, `default/bookman` ↔ its
  Meilisearch/Mailpit, `default/immich` server ↔ machine-learning,
  `media/nana` ↔ FlareSolverr, `matrix` (HAProxy/Synapse/MAS/Valkey), `vault`
  raft peers, `infrastructure` (crunchy replication/pgBackRest), the
  `observability` stack
- one-off cross-namespace calls — `default/kalimba` → Temporal
- **anything addressed by entity rather than by pod or CIDR** — no vocabulary
  label exposes `host`/`remote-node`/`kube-apiserver`, so a pod that talks to a
  node by address names the entity in its own policy: `allow-egress-vmagent`
  (host-network exporters) and `blackbox-exporter-lan` (ICMP probes of the six
  nodes)

When a service has several consumers, prefer a label pair over a bespoke
policy: that is what the downloads stack does. The pair is still shipped by the
service's own directory — it is a clusterwide policy keyed on a label, not a
CiliumNetworkPolicy naming each consumer, so consumers stay decoupled.

The test is the **consumer list**, not the number of namespaces. A policy that
enumerates peers by name is a pair waiting to happen: `matrix-stack` used to
list its four bridges twice, once per direction, and now keys on
`egress.home.arpa/matrix-synapse` / `ingress.home.arpa/matrix-appservice`
instead — a fifth bridge is two pod labels and no policy edit. Conversely, a
flow whose consumer set is "exactly one, and structurally so" (a sidecar, a
guardrail, a controller of the same release) stays a CiliumNetworkPolicy: a
label there would be vocabulary nobody else can use.

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

2. If a shared peer it needs has no label yet but will have several consumers,
   add the **pair** rather than a bespoke policy — one
   `ciliumclusterwidenetworkpolicy.yaml` in the _service's_ directory holding
   both halves (see `media/jellyfin/app/` for the canonical shape). The
   consumer then only ever gains a label.

3. A policy for what is left: its own sidecars and co-located services, and
   one-off calls with a single consumer. A `ciliumnetworkpolicy.yaml` in the
   app's directory, added to its `kustomization.yaml`:

```yaml
# kubernetes/apps/<ns>/<app>/app/ciliumnetworkpolicy.yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
    name: myapp
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

Do **not** put the policy in `rawResources` in the HelmRelease: see the second
bullet at the top of this file.

## Flipping to enforcement

1. `Cilium Policy Audit` dashboard clean for a few days — see below, the
   target is not literally 0.
2. Set `policyAuditMode: false` in `../app/helmrelease.yaml`.
3. The `cilium-dropped-flows` dashboard (`cilium-policy-denied`) then shows
   real drops; the audit dashboard's "Real Drops" stat must stay green.

Rollback at any time: set `policyAuditMode: true` back (agent rollout, no
traffic interruption), or `kubectl -n kube-system exec ds/cilium -- cilium
config PolicyAuditMode=true` per node for instant effect without a rollout.

### The audit rate never reaches 0, and that is fine

Two things make the metric read non-zero forever, and neither is a policy gap:

- **Dead pod IPs.** An app that keeps dialling a peer it remembers by address
  — Temporal's Ringpop ring, Vault's raft peer list — sends to an IP that owns
  no endpoint any more. Cilium resolves it through the CIDR identity created by
  `internet`'s `except` list, so the flow is reported as
  `reserved:world` + `cidr:10.0.0.0/8`. No CNP can select an endpoint that does
  not exist; under enforcement these are dropped, which is the correct
  behaviour (the app retries and re-resolves through DNS). Recognise them with
  `hubble observe --verdict AUDIT -o json`: the destination IP is inside the
  pod CIDR `10.69.0.0/16` and `kubectl get pods -A -o wide` does not know it.
- **Label propagation on pod creation.** The first connection of a brand new
  pod can be audited before its identity carries the labels, which is why
  correctly labelled workloads still show 1 or 2 events per week.

So the criterion is **no audited flow whose destination is a live endpoint**,
not a zero on the stat panel.

Also mind that the metric counts **connections, not packets**: a missing label
on a keepalive HTTP client (karma → Alertmanager) shows up as 2 events a week
and is just as fatal as one showing 20 000. Rank by distinct source/destination
pairs, never by volume.
