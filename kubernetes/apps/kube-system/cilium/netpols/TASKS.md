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

- [ ] **`allow-egress-kubedns` only opens UDP/53** while `baseline.yaml` opens
      UDP+TCP. Pods outside enrolled namespaces carrying
      `egress.home.arpa/kubedns: allow` therefore have no TCP fallback
      (truncated responses > 512 B, EDNS). → add `protocol: TCP`.
      _File_: `allow-egress-kubedns.yaml`

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

      Today `baseline.yaml` opens port 53 to kube-dns as a **plain L4 rule** for
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

      _Files_: `baseline.yaml` (or a dedicated CCNP replacing the baseline's DNS
      rule), `allow-egress-kubedns.yaml`

- [ ] **Validate on a single app** before going further:
      `cilium-dbg policy get` must show the DNS parser on the endpoint,
      `hubble observe --type l7 --protocol dns` must see the queries go through,
      and `cilium-dbg fqdn cache list` must fill up.
      Mind the Alpine/musl `Refused` + resolv.conf `search` trap (documented
      upstream) if we ever move to a restrictive `matchPattern` instead of `*`.

## Phase 2 — split `egress.home.arpa/world`

`world` = internet **+ the whole LAN + every VLAN**, and **63 apps** carry it.
This is the biggest actual security gain of the lot.

- [ ] **`egress.home.arpa/internet`** — "the world except home":

      ```yaml
      egress:
        - toCIDRSet:
            - cidr: "0.0.0.0/0"
              except: ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
      ```

      CIDR selectors don't match in-cluster endpoints by default, so the RFC1918
      `except` is safe (and already covers the 10.69/16 pod CIDR and the
      192.168.1/24 LAN). Mind the IPv6 twin if needed, and note that
      `100.64.0.0/10` (CGNAT/Tailscale) is not excluded by that list.

- [ ] **Per-segment labels**, parameterised through Flux substitution the way
      they do it (`${IP_*}`): `/lan`, `/nfs` (truenas), `/iot` or `/hass`,
      `/router`. Biohazard goes as far as a single IP
      (`${IP_HUAWEI_E3372}/32`) for one device.

- [ ] **Port-scoped variants** for apps that only speak HTTPS:
      `internet-https` / `world-https` (443), `world-ntp` (123).

- [ ] **Migrate the 63 carriers** of `world` to the right label (additive, then
      removal — see the migration rule). Keep `world` for whatever genuinely
      needs both the internet **and** the LAN.

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
      that would collapse the **7 near-identical `allow-<arr>.yaml` files** into
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

- [ ] `cilium-policy-audit` dashboard at 0 for a few days (see `README.md`).
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
