# Network policy — backlog

Improvements drawn from a comparison with
[JJGadgets/Biohazard](https://github.com/JJGadgets/Biohazard/tree/main/kube/deploy/core/_networking/cilium/netpols)
(2026-10-21). We already share the same `*.home.arpa/<thing>: allow` vocabulary,
but their split of **external destinations** is far finer than ours, while our
**structure** (explicit per-namespace default-deny, intra-namespace closed,
audit-mode rollout) is more rigorous than theirs.

See `README.md` for the current architecture.

## Migration rule

Every label migration happens in **two additive steps**, which makes it safe
even under enforcement:

1. add the new label alongside the old one (union of the allowances);
2. drop the old one once the dashboard is clean.

Corollary: while `policyAuditMode: true`, **tightening a policy is free** — a
flow that would no longer pass is recorded as `verdict=AUDIT` and still
forwarded, so the problem shows up without biting. That is the argument for
doing phases 1 to 3 before the flip; the opposite argument (real protection
sooner) says flip right after phase 0. To be arbitrated.

---

## Phase 0 — hygiene, before anything else

- [ ] **`allow-egress-kubedns` only opens UDP/53** while the baseline opens
      UDP+TCP. Pods outside enrolled namespaces carrying
      `egress.home.arpa/kubedns: allow` therefore have no TCP fallback
      (truncated responses > 512 B, EDNS). → add `protocol: TCP`.
      _File_: `platform/kubedns.yaml`

- [ ] **kopiur movers**: they carry `app.kubernetes.io/managed-by: kopiur`, run
      in enrolled namespaces (`default`, `media`, …) and are selected by **no**
      policy → they inherit the baseline default-deny with only DNS open. This
      is probably harmless (the repository is an inline NFS volume mounted by
      the kubelet, so it lives in the host netns and not in the pod's Cilium
      endpoint), but it is an unverified assumption.
      → confirm on the `cilium-policy-audit` dashboard that no AUDIT flow comes
      from a `managed-by: kopiur` pod, over a window covering one snapshot cycle
      **and** one maintenance run (`0 * * * *` / `30 3 * * *`).
      If flows do show up: a CCNP selecting the operator label, modelled on their
      `volsync-mover`
      (`endpointSelector: app.kubernetes.io/created-by: volsync`).

- [ ] **Same question for the other ephemeral pods** in enrolled namespaces:
      pgBackRest jobs (`infrastructure`), Helm hooks, app CronJobs.
      The Biohazard pattern is consistently a CCNP on the operator label
      (`app.kubernetes.io/managed-by: <operator>`).

## Phase 1 — DNS L7 opt-in _(hard prerequisite for any FQDN policy)_

- [ ] **Split the baseline DNS rule into mutually exclusive L4 / L7 halves.**

      Today the baseline (`components/netpol-baseline`) opens port 53 to
      kube-dns as a **plain L4 rule** for
      every pod in every enrolled namespace. The Cilium docs are explicit:
      > _"If a layer 4 rule is specified in the policy, and a similar layer 4
      > rule with layer 7 rules is also specified, then the layer 7 portions of
      > the latter rule will have no effect."_

      and
      > _"`toFQDNs` rules do nothing if there is no L7 DNS rule covering the
      > endpoint."_

      So as things stand, **a `toFQDNs` policy would be silently inoperative**:
      the DNS proxy is never engaged and the FQDN cache stays empty.

      The Biohazard setup (`cluster-default-kube-dns.yaml`): two policies with
      mutually exclusive `matchExpressions` on a `dns.home.arpa/l7` label, one
      with `rules.dns`, one without. Opt-in, so we don't pay the DNS proxy's
      userspace hop for the whole cluster.

      ```yaml
      # pods WITHOUT the label → plain L4 (current behaviour)
      endpointSelector:
        matchExpressions:
          - { key: dns.home.arpa/l7, operator: NotIn, values: ["true"] }
      # pods WITH the label → same rule + rules.dns
      endpointSelector:
        matchExpressions:
          - { key: dns.home.arpa/l7, operator: In, values: ["true"] }
      ```

      _Files_: `components/netpol-baseline/ciliumnetworkpolicy.yaml` (or a dedicated
      CCNP replacing the baseline's DNS rule), `platform/kubedns.yaml`

- [ ] **Validate on a single app** before going further:
      `cilium-dbg policy get` must show the DNS parser on the endpoint,
      `hubble observe --type l7 --protocol dns` must see the queries go through,
      and `cilium-dbg fqdn cache list` must fill up.
      Mind the Alpine/musl `Refused` + resolv.conf `search` trap (documented
      upstream) if we ever move to a restrictive `matchPattern` instead of `*`.

## Phase 2 — split `egress.home.arpa/world` — **DONE (2026-10-21)**

`world` was internet **+ the whole LAN + every VLAN**, and 62 pod templates
carried it. It now has **no carrier at all**: `destinations/world.yaml` stays
only as the documented escape hatch for a bad reclassification.

- [x] **`egress.home.arpa/internet`** — "the world except home"
      (`destinations/internet.yaml`). `except` ended up wider than RFC1918:
      `100.64.0.0/10` (CGNAT, also Tailscale) and `169.254.0.0/16` (link-local,
      which includes the `169.254.169.254` metadata address) are excluded too.
      No `::/0` twin — the cluster runs `enable-ipv6=false`.

      Multicast and broadcast are deliberately **not** excluded, so SSDP
      discovery (home-assistant, sabnzbd → `239.255.255.250:1900` and
      `255.255.255.255:1900`) keeps working until phase 5 adds `/ssdp`.

- [x] **Per-segment labels** — `/lan` (`192.168.1.0/24`), `/nas`
      (`192.168.1.70`, TrueNAS), `/router` (`192.168.1.1:443`, the UniFi
      gateway), `/iot` (`192.168.30.0/24`).

      **Deviation from the Biohazard model**: the IPs are hardcoded, not Flux
      `${IP_*}` substitutions. `AGENTS.md` reserves substitution for secrets —
      "domains and other non-secret values (timezone, UID/GID, load balancer
      IPs, hostnames) are hardcoded directly in manifests" — and a netpol whose
      CIDRs only exist in a cluster Secret cannot be reviewed in the diff.

      `192.168.20.0/24` (client VLAN) and `192.168.70.0/24` (VPN) got no label:
      nothing egresses to the first, and the second is only reached through the
      multus `vpn` attachment, which bypasses Cilium entirely.

- [x] **Port-scoped variant** — `/internet-https` (443), on the thirteen pods
      whose whole external surface is an HTTPS API: external-dns-cloudflare,
      renovate-operator, robusta, litellm + its github/kubesearch MCPs,
      paperless-ai, the four mautrix bridges, headroom, alertmanager.

      `world-https` and `world-ntp` were **not** built. The first is now
      `internet-https` + `lan`, which composes; the second has no carrier (NTP
      is a Talos node concern, no pod speaks 123).

- [x] **Migrated all 62 carriers.** Done as a straight swap, not the two-step
      additive migration: `policyAuditMode` is still on, so a misclassification
      shows up as `verdict=AUDIT` instead of biting, and the additive step
      would have produced no dashboard signal at all (new label ∪ `world` =
      `world`). That is the corollary above, used on purpose.

      Classification evidence: `hubble observe --to-identity 2` over the live
      ring buffer, cross-checked against each app's config. The non-obvious
      ones:

      | Pod | Label(s) | Why |
      | --- | -------- | --- |
      | home-assistant | `internet` + `iot` | appliances on `192.168.30.{9,18}` (MQTT 8883, 9999) |
      | hcpy | `iot` | Home Connect appliance on `192.168.30.91:443`, nothing else |
      | bambuddy | `iot` | the Bambu printer is `192.168.30.18:8883` |
      | envoy (both gateways) | `nas` + `iot` | the nas-services FQDN EndpointSlices: truenas `:80`, robovac `192.168.30.142:80` |
      | blackbox-exporter-lan | `internet` + `lan` + `iot` | 1.1.1.1/8.8.8.8/9.9.9.9, truenas + ups, robovac |
      | snmp-exporter | `lan` | the UPS, `192.168.1.182:161` |
      | semaphore | `internet` + `lan` | runs `ansible/` over SSH against `ntp.lulice.lan` |
      | external-dns-unifi, unifi-mcp | `router` | `https://192.168.1.1` only |
      | truenas-mcp | `nas` | `truenas.lulice.lan:443` only |

### Fallout found while doing it (not fixed here)

- [x] **vmagent scrapes two LAN hosts and no policy covered it**:
      `192.168.1.70` (node-exporter 9100, smartctl 9633) and `192.168.1.118`
      (the same two plus chrony 9123 and gpsd 9015), from `./scrapeconfig.yaml`.
      vmagent never carried `world`, so this predated phase 2.

      Fixed as a port-scoped `toCIDR` rule inside `allow-egress-vmagent`
      (`apps/observability/victoria-metrics-stack/app/ciliumclusterwidenetworkpolicy.yaml`)
      rather than by hanging `egress.home.arpa/lan` on the pod: these two hosts
      are vmagent's own scrape targets, not shared vocabulary, and `/lan` would
      have opened all 65535 ports of `192.168.1.0/24` to it. That policy's
      header promises it "is still a whitelist, not an escape hatch".

- [x] **blackbox-exporter-lan probes the six nodes by address**
      (`bee.lulice.lan` … → `192.168.1.11-16`). Those are the `host`/
      `remote-node` entities, which neither `world` nor a CIDR label matches
      (`policy-cidr-match-mode` is unset), so no vocabulary label can ever
      cover them. Also predated phase 2.

      Fixed with a CiliumNetworkPolicy next to the app
      (`apps/observability/exporters/blackbox-exporter/lan/ciliumnetworkpolicy.yaml`),
      scoped to ICMP echo-request via `icmps.fields` — the entities are not
      opened for TCP. Selector is `app.kubernetes.io/instance`, since the chart
      gives this deployment and blackbox-exporter-vpn the same
      `app.kubernetes.io/name`.

      This makes the phase 5 `/host` label less urgent: two apps need entities
      and both now name them in their own policy, which is what `README.md`
      prescribes for anything the vocabulary does not cover.

- [ ] **The EnvoyProxy pod template is shared** by both gateways, so the
      external one now carries `/nas` + `/iot` it does not need. Splitting it
      means a second `EnvoyProxy` CR referenced from the external `Gateway`.

## Phase 3 — FQDN labels _(depends on phase 1)_

- [ ] **Labels per external destination**: `/github`, `/cloudflare`, `/registry`
      (ghcr, docker hub, quay), `/pypi`, `/heartbeat`.
      "this app may reach GitHub and nothing else" instead of "this app may
      reach the internet".

- [ ] **Reuse the YAML-anchor trick**: the FQDN list serves as both the
      `toFQDNs` target and the DNS proxy allowlist, so the two can never drift.

      ```yaml
      egress:
        - toFQDNs: &dns
            - matchPattern: "*.github.com"
            - matchName: "ghcr.io"
          toPorts: [{ ports: [{ port: "443", protocol: TCP }] }]
        - toEndpoints:
            - matchLabels:
                io.kubernetes.pod.namespace: kube-system
                k8s-app: kube-dns
          toPorts:
            - ports: [{ port: "53", protocol: ANY }]
              rules:
                dns: *dns # ← same list
      ```

## Phase 4 — `deny` guard-rails

We have none. Deny beats allow, so it is the only way to carve a hole out of a
broad label — and the only protection against a mislabelled pod.

- [ ] **`ingressDeny`** on the WebUIs that must never be reachable from `world`,
      whatever a label allows elsewhere: qbittorrent, sabnzbd, slskd. Model:
      their home-assistant denies port 8123 from `world` via `ingressDeny` while
      still accepting the rest.
- [ ] **`egressDeny`** towards the IoT VLAN for everything but home-assistant.

## Phase 5 — quality-of-life refactors

- [ ] **Valued labels for per-instance granularity.** They use
      `db.home.arpa/pg: pg-<name>` (the value carries the target) rather than
      `=allow`, with the policy pair templated through `${PG_APP_NAME}`. Here
      that would collapse the *_7 near-identical per-*arr policy files*_ into
      one templated pair, and make the vocabulary multi-instance-safe the day a
      second PG cluster shows up.
- [ ] **`toServices`** (`k8sService` / `k8sServiceSelector`) to name a Service
      rather than pod labels: admission webhooks, Ceph RGW. We use none today.
- [ ] **`icmps: [{}]`** alongside 5432 if any health check goes through ping.
- [ ] **`egress.home.arpa/talos`** (`host` + `remote-node` on :50000/:50001) and
      a generic `/host`. We only use `host`/`remote-node` 4 times in total;
      useful the day a pod in an enrolled namespace talks to the Talos API.
- [ ] **Multicast**: `/mdns` (224.0.0.251:5353), `/dlna` (239.255.255.250:1900)
      — only if home-assistant / jellyfin discovery needs it.

## Phase 6 — enforcement

### Audit sweep, 2026-10-22 (afternoon)

Third pass over `hubble_policy_verdicts_total{action="audit"}`, measured over
the 10 h that followed the previous two fix commits. Total 7 978 flows, of
which **7 794 are not policy gaps at all** — see "stale pod IPs" below. The
184 real ones were:

- [x] **authentik outposts → the external gateway** (156). The outposts' egress
      half already existed (`authentik-outposts` CNP, keyed on the `app:
authentik-outpost` label authentik stamps on them), but
      `allow-ingress-gateway-external-from-cluster` only accepts pods carrying
      `egress.home.arpa/gateway-external`, which an operator-made Deployment
      cannot. Added as a second named exception next to Flux source-controller.
- [x] **immich-server → the external gateway** (4). Missing
      `egress.home.arpa/gateway-external`; it does OIDC against
      `sso.hoohoot.org`.
- [x] **homelab-manager → authentik-server :9000** (2). `AUTHENTIK_BASE_URL` is
      the in-cluster Service, and homelab-manager's own CNP had the egress
      half, but nothing opened authentik-server's ingress — a half-paired flow
      that only the audit log could reveal. Added `authentik-server-api-clients`.

**Stale pod IPs are the dominant signal and must not be "fixed".** Two
workloads keep dialling addresses whose pods are long gone:

- `temporal-{worker,history,matching,frontend}` → 7 724 flows to four dead pod
  IPs on the ringpop ports (6933/6934/6935/6939). Temporal's
  `cluster_membership` table still lists them; the live mesh is fully covered
  by the `temporal-cluster` CNP.
- `vmagent` → 70 flows to dead authentik pod IPs on :9300.

Cilium labels those destinations `cidr:10.0.0.0/8` + `reserved:world`, so on
the dashboard they masquerade as "missing internet egress". They are
**correctly denied** — opening them would mean allowing the pod CIDR as
`world`, which is precisely what phase 2 removed. The flows stop when the
membership row expires or the workload restarts; the fix, if one is wanted, is
pruning `cluster_membership`, not a netpol.

Left open, too rare to attribute (1–10 flows per 10 h, destination not
observable in a 20 s ring buffer): `kalimba`, `grafana-mcp`, `zigbee2mqtt`,
`bambuddy` → world; `dragonfly-operator` → remote-node; `echo-server` → host.
Re-check before flipping enforcement.

### Audit sweep, 2026-10-22 (evening)

Fourth pass, over the 6 h window on the evening of the same day. 11 204 flows,
of which 4 765 are the temporal stale-IP noise described above and ~30 are the
matrix rollout 17 min earlier (`matrix-haproxy` keeps dialling the previous
Synapse pod IP for as long as `hold obsolete`). The rest were real and are
fixed below.

New evidence for the stale-IP story: those dead ringpop addresses have since
been **recycled onto a live pod** — `matrix/synapse-20261022184400-48s7n`, a
kopiur mover — which temporal is now dialling on 6933-6939. Still not a policy
gap, and a good argument for pruning `cluster_membership` rather than letting
it point at whatever lands on the address next.

#### The baseline was never enforcing ingress

The headline finding, and it produces **no audit signal at all**. Cilium:

> If any rule selects an Endpoint and the rule has an ingress section, the
> endpoint goes into default deny-mode for ingress.

`enableDefaultDeny` can only switch that _off_. `baseline.yaml` had
`enableDefaultDeny.ingress: true` but no `ingress:` section, so any pod that no
_other_ policy happened to select for ingress kept an `Allow Ingress ANY` entry
in its policy map and stayed wide open — silently, because nothing was denied
and therefore nothing was audited. Six endpoints were in that state
(`cilium-dbg endpoint list` → `policy-enabled: audit-egress` instead of
`audit-both`):

| Namespace      | Pod                                    |
| -------------- | -------------------------------------- |
| development    | forgejo-runner                         |
| home           | hcpy                                   |
| infrastructure | crunchy-users, dragonfly-operator, pgo |
| vault          | (serviceaccount `default`)             |

- [x] **Fixed**: the baseline now carries an `ingress: [{fromEntities: [host]}]`
      section in all twelve namespaces. `reserved:host` is allowed
      unconditionally by Cilium anyway, so the rule grants nothing — its
      presence is the entire point.
- [ ] **Soak before flipping.** This turns ingress enforcement _on_ for those
      six pods for the first time, so expect new AUDIT flows that the dashboard
      could not previously show. Judge the dashboard only after it has run for
      a full day with this in place.

#### Real gaps fixed in this pass

- [x] **forgejo-runner → kube-apiserver and the internet** (4 358 flows, 39 %
      of the window). The HelmRelease declared `apiserver` / `internet` /
      `gateway-external` under `defaultPodOptions.labels`, but the pod carried
      none of them: **in app-template a controller's `pod.labels` REPLACES
      `defaultPodOptions.labels` outright** rather than merging, and this
      release set `app.kubernetes.io/component` there. Confirmed with
      `helm template` on 5.3.0: the controller with `pod.labels` loses the
      netpol labels, a sibling controller without it keeps them. The deployment
      had not rolled since 2026-10-11, so the 2026-10-21 label commit rendered
      identically and nothing looked wrong.

      Fixed by moving all four labels onto the controller. forgejo-runner was
      the only release in the repo with both keys set; a check for that is
      cheap and worth keeping in mind when labelling a chart that already has
      a `pod.labels`.

- [x] **forgejo-runner-task → everything** (1 557 flows). The k8s plugin
      stamped `egress.home.arpa/custom-egress=true` on every CI job pod, a
      label **no policy selects**. Replaced with `internet` +
      `gateway-external` (`internet`, not `internet-https`: CI pulls over 80,
      git and ssh too, and six hours of 443-only traffic does not prove
      otherwise), plus a `forgejo-runner-netpol-task` CNP for the two
      in-cluster peers:

      - `forgejo-http:3000` — checkout and API. The ingress half in
        `apps/development/forgejo/app/ciliumnetworkpolicy.yaml` named
        `forgejo-runner` only and now takes both names via `matchExpressions`.
      - the runner's Actions cache proxy. Its port is **random on every runner
        restart** (`cache.port` / `cache.proxy_port` both default to 0), which
        no policy can name, so both are now pinned — 45000 and 45001 — and the
        policy names 45001, the one `ACTIONS_CACHE_URL` points at.

- [x] **esphome → IoT VLAN** (406 flows). `10.69.5.12:5353 → 192.168.30.1:<eph>`,
      i.e. unicast mDNS replies to the UniFi gateway's own queries, plus ICMP.
      It carried `internet`, whose `except` list excludes `192.168.0.0/16`.
      Added `egress.home.arpa/iot`. This is the pod's `eth0` leg; the macvlan
      attachment it also has bypasses Cilium entirely.

- [x] **jellyfin → the authentik LDAP outpost** (3 + 3, audited at both ends).
      `LDAP-Auth.xml` points at `ak-outpost-ldap.auth.svc:389`, which targets
      **container port 3389** — policy is evaluated after service translation,
      so the published port is the wrong one to write down. Made a vocabulary
      pair (`auth/authentik/app`, `egress.home.arpa/ldap`) rather than a bespoke
      policy: LDAP is a multi-consumer service and the README prefers a pair
      for those. Service side keys on the labels authentik stamps on the
      outpost, as `authentik-outposts` already does.

- [x] **radarr and lidarr → homelab-manager:8080**. Only radarr showed up in
      the window (1 flow — these are import webhooks, so a 6 h window proves
      nothing). Read the notification lists out of each *arr's API instead:
      radarr and lidarr both have the Homelab Manager webhook and lacked
      `egress.home.arpa/homelab-manager`; sonarr and bazarr already had it;
      **sonarr-anime has no notifications configured at all**, so its missing
      `homelab-manager` and `jellyfin` labels are correct, not an oversight.

      Incidentally: sonarr still has an **Autobrr** webhook pointing at
      `autobrr.downloads.svc`, and that Service no longer exists. Dead config,
      not a policy gap — but it will start failing loudly rather than quietly
      once DNS is the only thing stopping it.

#### Found afterwards, pushing the VictoriaMetrics dashboards

- [x] **grafana-operator → the internet** (8 flows, one per new dashboard).
      The _operator_, not Grafana, fetches every `GrafanaDashboard` that has a
      `url:` and caches the JSON in the CR status — 45 of ours do. It carried
      only `apiserver` + a CNP for `grafana:3000`, so under enforcement no
      url-backed dashboard would ever load again.

      The 6 h sweep could not have caught this: a fetch happens when a CR is
      created or its cache is invalidated, and the 45 existing ones were all
      cached long ago. It only surfaced because pushing eight new dashboards
      forced eight fresh fetches, to `raw.githubusercontent.com` and
      `grafana.com`, both 443 — hence `internet-https`.

      The general shape is worth remembering: **a cached fetch is invisible
      until the cache misses**. Anything that pulls remote content once and
      stores it (operators resolving URLs, init containers, first-run
      migrations) can pass an audit window and still break at enforcement.

#### Not fixed, on purpose

`temporal-*` (4 765) and `matrix-haproxy` (24) are stale-IP retries. Denying
them is the correct outcome.

The `renovate-operator-…-crd-install` Helm hook hits the API server once per
chart upgrade (1 flow). Chart-managed pod, no values hook for labels; left
alone rather than adding a CNP for one packet per release.

#### Still unattributed

A 45 min live follow caught **none** of them, which turned out to be the useful
result: reading each counter's shape over three hours says more than trying to
catch a packet. These flows are episodic, not steady, so `hubble observe -f`
has to run for hours, not minutes.

| Source                         | Shape over 3 h                                                                   | Reading                                                                                                                                                                                                      |
| ------------------------------ | -------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `vmagent-vmks` → world         | +1/+2 every ~10 min until 20:30, then **flat for 45 min** with no change from us | self-healing, i.e. the stale-IP/connection-pool signature again. Supports the previous sweep's ":9300 dead authentik pods" story even though `up == 0` is empty and every live socket to 9300 is established |
| `matrix-haproxy` → world (+24) | one step at the 20:00 rollout, flat before and after                             | rollout artifact, `hold obsolete`                                                                                                                                                                            |
| `matrix-rtc-sfu` → world (+6)  | same single step at 20:00                                                        | rollout artifact                                                                                                                                                                                             |
| `bambuddy` → world             | flat for 3 h                                                                     | episodic; nothing to catch right now                                                                                                                                                                         |
| `grafana-mcp` → world          | +1 in 3 h                                                                        | episodic                                                                                                                                                                                                     |
| `kalimba` → world              | +3 in 3 h, as three separate single steps                                        | **the most recently active of the six**, but episodic too — flat for the last 25 min                                                                                                                         |

So the list is really one item. kalimba carries `internet-https`, so whatever
it is, it is either non-443 on the internet or a private address;
`kalimba-secret` holds the external endpoints and is the place to look next.
A 25 min follow scoped to it still caught nothing, so budget hours.

- [ ] Attribute `kalimba` → world. Needs a follow left running for a long
      while, not a ring-buffer dip:

      ```
      hubble observe --verdict AUDIT --from-pod default/kalimba -f
      ```

- [ ] Re-check the other five right before flipping; a counter that is flat for
      days is not the same as one that is explained.

- [ ] `cilium-policy-audit` dashboard at 0 for a few days (see `README.md`).
      Read it with the stale-IP caveat above: filter out `source=~"temporal-.*"`
      and vmagent before judging it clean, and do not judge it at all until the
      baseline ingress fix has soaked for a day.
- [ ] Re-run the enforcement-state check — every endpoint in an enrolled
      namespace must read `audit-both`, never `audit-egress`:

      ```
      cilium-dbg endpoint list -o json | \
        jq -r '.[] | select(.status.policy.realized["policy-enabled"]=="audit-egress")'
      ```

- [ ] `policyAuditMode: false` in `../app/helmrelease.yaml`.
- [ ] Watch `cilium-policy-denied`; instant per-node rollback with
      `cilium config PolicyAuditMode=true`.

---

## What we deliberately don't take from them

- **`kube-system-allow-all`** — they need it because their CCNPs flip kube-system
  pods into default-deny. Not enrolling the system namespaces is cleaner.
- **Blanket intra-namespace allow**
  (`fromEndpoints: {io.kubernetes.pod.namespace: <ns>}`) — that is exactly what
  we chose to close.
- **`ingress.home.arpa/cluster`** (`fromEntities: cluster`) — reintroduces a
  "the whole cluster" shortcut.
- **Implicit default-deny** (no `enableDefaultDeny`, relying on "selected ⇒
  denied") — removing a label then silently reopens everything.
