# Migration plan: Rook Ceph → miroir

Goal: replace Rook Ceph with [miroir](https://miroir.home-operations.com/)
(DRBD9 + LVM thin CSI) without losing data, reusing the same SATA SSDs.

## 1. Current state (snapshot 2026-11-24)

| Item                | Value                                                                                                                                  |
| ------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| Nodes               | 6 × Talos v1.14.2 (kernel 6.18): CP `chade`, `fitz`, `nighteyes`; workers `bee`, `burrich`, `fool`                                     |
| Disks               | System NVMe per node (500 GB, `chade` 1 TB) + **one** `CT1000BX500SSD1` 1 TB SATA SSD (`sda`) per node, fully consumed by one Ceph OSD |
| Ceph                | 6 OSDs, `size: 3`, failure domain `host`, 948 GiB raw used / 5.5 TiB (17 %), `HEALTH_WARN` (BlueStore slow ops, BX500)                 |
| Data                | `ceph-blockpool` 196 GiB stored, `ceph-filesystem` 131 GiB stored, RGW: **no buckets, no OBC**                                         |
| PVCs                | 65 × `ceph-block` (RWO), 5 × `ceph-filesystem` (RWX), 762 GiB requested in total                                                       |
| Backups             | kopiur → TrueNAS NFS (`ClusterRepository truenas`), hourly, 45 apps via `components/kopiur`                                            |
| Kubelet             | Graceful shutdown already on (`90s` / `60s` critical) ✓                                                                                |
| snapshot-controller | Already deployed in `kube-system` ✓                                                                                                    |

### PVC inventory

**A. kopiur-managed (`components/kopiur`)** – migrated by restore from backup:

- RWO (41): ai/hermes; default/{bambuddy, bichon, bookman, bookman-basemap, bookman-meilisearch, endurain, kalimba, mealie, mindwtr, onlyoffice, outline, rustical, trilium, vaultwarden, vikunja, wallabag}; development/forgejo; downloads/{bazarr, brrpolice, droppedneedle, lidarr, pinchflat, radarr, recyclarr, sabnzbd, slskd, sonarr, sonarr-anime}; home/{esphome, home-assistant}; matrix/{mautrix-discord, mautrix-facebook, mautrix-instagram, mautrix-whatsapp, synapse}; media/{audiobookshelf, bookorbit, jellyfin, jellyseerr, navidrome, silo, silo-meilisearch, tdarr, the-elder-scrobz}
- RWX (4): auth/authentik, default/opencloud, downloads/qbittorrent, home/zigbee2mqtt

**B. Not covered by kopiur** – migrated by copy job:

| PVC                                                                                                                                      | Kind                      | Strategy                                       |
| ---------------------------------------------------------------------------------------------------------------------------------------- | ------------------------- | ---------------------------------------------- |
| vault/data-vault-{0,1,2}                                                                                                                 | STS, Raft                 | Copy one pod at a time (+ raft snapshot first) |
| matrix/ess-synapse-media (50Gi)                                                                                                          | Deployment                | Copy                                           |
| observability/grafana-pvc, observability/config-gatus-0, observability/alertmanager-…-0                                                  | Deploy/STS                | Copy                                           |
| development/database-data-harbor-database-0, data-harbor-redis-0, harbor-jobservice                                                      | STS/Deploy                | Copy                                           |
| infrastructure/mosquitto, ai/kubitus-workspace, development/persistent-forgejo-runner-0                                                  | Deploy/STS                | Copy                                           |
| development/pacman (RWX 200Gi), default/immich-machine-learning-cache (RWX)                                                              | Deploy                    | Copy (pacman) / recreate empty (immich cache)  |
| development/data-harbor-trivy-0, security/data-trivy-server-0, home/esphome-cache, home/home-assistant-cache, flux-system/konflate-cache | caches                    | Recreate empty                                 |
| gravitee/data-graviteeio-apim-elasticsearch-master-0                                                                                     | not in this repo          | Decide: copy or drop                           |
| downloads/recyclarr-*-src                                                                                                                | kopiur staging, ephemeral | Ignore                                         |

## 2. Target design

- **Backend**: `lvmthin` on a Talos `RawVolumeConfig` partition (`/dev/disk/by-partlabel/r-miroir`) on each BX500 SSD.
- **Topology**: `MiroirNodeGroup std` selecting `storage.miroir.home-operations.com/class=std` (node label set in Talos config).
- **StorageClasses**:
    - `miroir-replicated` – `replicas: "2"`, `quorum: freeze`, ext4, WFFC, expandable, **default class**. With ≥ 3 storage nodes every volume gets a diskless tie-breaker → survives one node down.
    - `miroir-replicated-staging` – `replicas: "1"`, same pool; kopiur `spec.staging.storageClassName` so hourly backups do not spin up a second DRBD leg each time.
    - `miroir-local` – `replicas: "1"` for disposable caches and for Vault (Raft already replicates 3×).
- **VolumeSnapshotClass** `miroir-snap`.
- **RWX**: `gateway.enabled: true` (NFS-Ganesha gateway per RWX volume). Review whether each of the 6 RWX volumes really needs RWX; single-writer apps are better on RWO.
- **Helm values**: stock DRBD settings (default `drbd.portBase: 7000`), Prometheus rules + Grafana dashboard on. The Ceph mgr dashboard, which would collide on host port 7000, is disabled beforehand (Phase 1b).

> Capacity: 3 workers × ~930 GB thin = ~2.8 TB raw → ~1.4 TB usable at 2 replicas during the transition, vs ~330 GiB of real data and 762 GiB requested. Comfortable; thin provisioning means watch `miroir` pool usage, not PVC sizes.

## 3. Safety principles (why nothing is lost)

1. **Every old Ceph PV is switched to `persistentVolumeReclaimPolicy: Retain` before its PVC is deleted.** The RBD image / CephFS subvolume survives until Ceph is decommissioned at the very end, so any app can be rolled back by rebinding the old PV.
2. **Writers stopped before the last copy**: Flux Kustomization + HelmRelease suspended, workload scaled to 0, then a final on-demand kopiur `Snapshot` (pinned) or final rsync.
3. **Restores fail closed during the migration**: `components/kopiur/restore.yaml` is switched from `onMissingSnapshot: Continue` to `Fail` for the whole window, so a wrong snapshot lookup can never silently produce an empty PVC.
4. **Ceph keeps 3 replicas on 3 hosts at all times** while it shrinks (6 → 3 OSDs), and is only destroyed after a bake period with zero Ceph PVs left.
5. **One app at a time, pilot first**, verification after each app before moving on.
6. Independent off-cluster copy: the kopia repository on TrueNAS (verified before starting).

## 4. Phases

### Phase 0 – Preflight (no changes)

- [ ] Every `SnapshotPolicy` has a `Succeeded` snapshot < 2 h old: `kubectl get snapshot -A --sort-by=.metadata.creationTimestamp`.
- [ ] Run a full kopia maintenance + `kopia snapshot verify` on the repository (kopiur server UI or a one-off job).
- [ ] Export the PVC→PV mapping: `kubectl get pvc -A -o yaml > pvc-backup-$(date +%F).yaml` and the same for `pv` (keep off-cluster).
- [ ] Vault: `vault operator raft snapshot save` to off-cluster storage.
- [ ] Ceph `HEALTH_OK`/`WARN` only for the known BlueStore slow-ops; all PGs `active+clean`.
- [ ] Read open miroir issues, in particular
      [#636](https://github.com/home-operations/miroir/issues/636) (idle `freeze` volumes losing every UpToDate leg after all replication links dropped at once, e.g. switch reboot). Keep the switch untouched during the migration and know the recovery path (recreate from kopiur).

### Phase 1 – Talos: DRBD

1. `talos/schematic.yaml.j2`: add `siderolabs/drbd` to `officialExtensions`.
2. `talos/cluster.yaml.j2`:
    ```yaml
    machine:
        kernel:
            modules:
                - name: drbd
                  parameters:
                      - usermode_helper=disabled
                - name: drbd_transport_tcp
    ```
    (kubelet graceful shutdown is already configured.)
3. Roll it out node by node (tuppr `TalosUpgrade` with the new schematic; its Ceph health gate still applies). Verify on each node: `talosctl -n <node> read /proc/drbd` → version ≥ 9.3.4.

### Phase 1b – Disable the Ceph dashboard (frees host port 7000)

1. `rook-ceph/cluster/helmrelease.yaml`: `cephClusterSpec.dashboard.enabled: false`; remove `httproute.yaml` and `probes.yaml` (blackbox probe on `rook.hoohoot.xyz`); remove the envoy-internal → host/remote-node `7000/TCP` rule from `envoy-gateway/config/ciliumclusterwidenetworkpolicy.yaml`.
2. The `rook-ceph-cluster` Kustomization is `prune: false`: delete the leftovers by hand: `kubectl -n rook-ceph delete httproute rook-ceph-dashboard probe rook-ceph`.
3. Verify nothing listens any more: `ceph mgr services` has no `dashboard` entry (else `ceph mgr module disable dashboard`), and port 7000 is closed on the active mgr host.

### Phase 2 – Free the worker SSDs (Ceph 6 → 3 OSDs)

Ceph keeps its 3 replicas on the control-plane hosts (mons/mgr already live there). Raw usage after shrink: 948 GiB / 2.8 TiB ≈ 34 %.

1. Delete the unused object store first (no buckets): remove `cephObjectStores` from `rook-ceph/cluster/helmrelease.yaml` (pools are `preservePoolsOnDelete: true` → delete them manually afterwards), and the `ceph-bucket` route/netpol references.
2. Pin OSDs to control planes in the cluster HelmRelease:
    ```yaml
    storage:
        useAllNodes: false
        useAllDevices: false
        nodes:
            - { name: chade, devices: [{ name: sda }] }
            - { name: fitz, devices: [{ name: sda }] }
            - { name: nighteyes, devices: [{ name: sda }] }
    ```
3. For each of `osd.4` (bee), `osd.3` (burrich), `osd.5` (fool), **one at a time**:
    ```bash
    ceph osd out <id>
    # wait until all PGs are active+clean (slow on BX500: expect hours)
    ceph osd safe-to-destroy <id>
    kubectl -n rook-ceph scale deploy rook-ceph-osd-<id> --replicas=0
    ceph osd purge <id> --yes-i-really-mean-it
    kubectl -n rook-ceph delete deploy rook-ceph-osd-<id>
    ceph osd crush rm <host>
    ```
4. Wipe the freed disks: `talosctl -n <worker> wipe disk sda --drop-partition`.

### Phase 3 – Install miroir on the workers

1. `talos/workers.yaml.j2` (workers only for now – the CP SSDs are still Ceph's):
    ```yaml
    ---
    apiVersion: v1alpha1
    kind: RawVolumeConfig
    name: miroir
    provisioning:
        diskSelector:
            match: disk.model == "CT1000BX500SSD1" && !system_disk
        grow: true
    ```
    plus node label `storage.miroir.home-operations.com/class: std`. Apply per worker; verify `/dev/disk/by-partlabel/r-miroir` exists.
2. New Flux app `kubernetes/apps/miroir-system/miroir/`:
    - `app/` – `OCIRepository` `oci://ghcr.io/home-operations/charts/miroir` + `HelmRelease` (values: default DRBD port base, `gateway.enabled: true`, `agent.loopfileBaseDirs: [/var/lib/miroir-stub]`, monitoring on).
    - `topology/` (dependsOn `miroir`) – `MiroirNodeGroup std` (pool `default`, `lvmthin.device: /dev/disk/by-partlabel/r-miroir`), StorageClasses, `VolumeSnapshotClass miroir-snap`.
    - Namespace privileged like `rook-ceph`; add `miroir-system` wherever `rook-ceph` is listed as a system namespace (Cilium `system-namespaces.yaml`, admission-policies exemptions).
3. **Control planes must be in the map too** (pods using volumes run there): hand-authored `MiroirNode` for `chade`, `fitz`, `nighteyes` with a small `loopfile` pool named `stub` (not `default`, so no data lands there). They can then host client legs and tie-breakers. _Validate on a test PVC that a pod on a CP mounts a replicated volume and that no `default` replica is placed there._
4. Keep `ceph-block` as the default StorageClass until Phase 6.

### Phase 4 – Validate miroir before moving anything

- [ ] Test PVC on `miroir-replicated`: provision, write, `kubectl get miroirvolumes` → `Ready`, tie-breaker present.
- [ ] fio comparison vs `ceph-block` (4k randwrite sync + seq) – BX500 + protocol C.
- [ ] `VolumeSnapshot` + restore + PVC clone.
- [ ] RWX PVC through the gateway, mounted from 2 nodes.
- [ ] Kopiur round trip on a throwaway app: backup with `copyMethod: Snapshot` + staging class, then restore through the volume populator **on a WFFC class** (Ceph was `Immediate`; this is the main unknown).
- [ ] Node drill: cordon/drain one worker, reboot, `kubectl wait miroirvolumes --all --for=jsonpath='{.status.phase}'=Ready`, uncordon. Repeat with a CP (tie-breaker/client host).
- [ ] Alerts arrive (PrometheusRule) and dashboard renders.

### Phase 5 – Migrate the workloads

Preparation commit:

- `components/kopiur/restore.yaml`: `onMissingSnapshot: Fail` (revert after Phase 6).
- `components/kopiur/snapshotpolicy.yaml`: add `staging.storageClassName: ${KOPIUR_STAGING_STORAGECLASS:=…}` so it can be overridden per app.

Per migrated app the `ks.yaml` gets the overrides (component defaults are flipped only at the end, otherwise snapshots of not-yet-migrated Ceph PVCs would use the wrong snapshot class):

```yaml
postBuild:
    substitute:
        KOPIUR_STORAGECLASS: miroir-replicated
        KOPIUR_SNAPSHOTCLASS: miroir-snap
        KOPIUR_STAGING_STORAGECLASS: miroir-replicated-staging
```

#### Runbook A – kopiur-managed app

```bash
APP=mealie NS=default
PV=$(kubectl -n $NS get pvc $APP -o jsonpath='{.spec.volumeName}')

# 1. Keep the Ceph volume no matter what
kubectl patch pv $PV -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
kubectl label pv $PV migration.home.arpa/from=ceph migration.home.arpa/claim=$NS.$APP

# 2. Stop Flux and the writers
flux -n $NS suspend ks $APP
flux -n $NS suspend hr $APP
kubectl -n $NS scale deploy,sts -l app.kubernetes.io/name=$APP --replicas=0

# 3. Final, pinned backup and wait for it
kubectl -n $NS create -f - <<EOF
apiVersion: kopiur.home-operations.com/v1alpha1
kind: Snapshot
metadata:
  generateName: $APP-premigration-
spec:
  policyRef: { name: $APP }
  pin: true
  description: pre-miroir-migration
EOF
kubectl -n $NS get snapshot -w   # until Succeeded

# 4. Release the old claim (PV stays, Released)
kubectl -n $NS delete pvc $APP

# 5. Push the ks.yaml overrides, then
flux -n $NS resume ks $APP     # recreates the PVC on miroir, Restore populates it
flux -n $NS resume hr $APP
```

Verify: Restore `Succeeded`, pod running, app-level check (login, latest item present), `du -s` of the volume ≈ old one, next scheduled kopiur backup `Succeeded` from the miroir PVC.

Rollback: suspend again, delete the new PVC, `kubectl patch pv $PV --type=json -p '[{"op":"remove","path":"/spec/claimRef"}]'`, recreate the PVC with `storageClassName: ceph-block` and `volumeName: $PV`, revert the ks.yaml.

#### Runbook B – PVC not covered by kopiur (copy)

1. Retain the old PV (as above), create a temporary PVC `<name>-miroir` on the target class.
2. Warm copy while the app runs (optional for large volumes), then stop the writers (suspend ks/hr, scale 0) and run the final copy:
    ```yaml
    # Job mounting old claim at /src (readOnly) and new claim at /dst
    command: ["rsync", "-aHAX", "--numeric-ids", "--delete", "--info=stats2", "/src/", "/dst/"]
    ```
    For the RWX pacman volume the same job works (both sides RWX).
3. Delete the old PVC; create the final PVC with the **original name** on miroir with `dataSource: { kind: PersistentVolumeClaim, name: <name>-miroir }` (miroir clone, copy-on-write, same class required); delete the temp PVC once bound.
4. StatefulSets (`volumeClaimTemplates` are immutable): change `storageClass` in the HelmRelease, `kubectl delete sts <name> --cascade=orphan`, pre-create the PVCs as in step 3, resume → Flux recreates the STS which adopts the PVCs by name.
5. Vault: one ordinal at a time (copy `data-vault-N`, restart only that pod, wait `vault operator raft list-peers` healthy + unsealed) – Raft quorum is kept the whole time. Use `miroir-local` (Raft is the replication).
6. Caches: just delete the PVC and let it be recreated on miroir (no Retain needed).

#### Order (waves)

1. Pilot: `downloads/brrpolice`, `matrix/mautrix-*` (small, low value).
2. downloads, media (largest bytes: jellyfin, silo, synapse – plan for restore duration).
3. default (except vaultwarden), development (forgejo, harbor, runner), ai, observability.
4. RWX: zigbee2mqtt, qbittorrent, opencloud, pacman, immich cache.
5. Critical last, each in its own window: home-assistant, matrix/synapse + ess-synapse-media, authentik, vaultwarden, vault.

Track progress with `kubectl get pv -l migration.home.arpa/from=ceph` and `kubectl get pvc -A | grep ceph`.

### Phase 6 – Bake, then decommission Ceph

1. Zero PVCs on `ceph-block`/`ceph-filesystem`; make `miroir-replicated` the default class; flip the kopiur component defaults (`KOPIUR_STORAGECLASS`, `KOPIUR_SNAPSHOTCLASS`, staging) to miroir and drop the per-app overrides; set `onMissingSnapshot` back to `Continue`.
2. **Bake period (≥ 2 weeks)**: every app has had successful kopiur backups from miroir, at least one node reboot cycle done, no miroir alerts. Retained Ceph PVs are still the rollback.
3. Delete the retained PVs (`kubectl delete pv -l migration.home.arpa/from=ceph`), then the RBD images/CephFS subvolumes are removed by hand or with the pools.
4. Remove Rook: drop `dependsOn: rook-ceph-cluster` from the 6 Kustomizations and the 8 HelmReleases referencing it; set `cephClusterSpec.cleanupPolicy.confirmation: yes-really-destroy-data`; delete the `CephCluster` (Kustomizations are `prune: false` → manual), then the csi and operator releases, CRDs, namespace, `/var/lib/rook` on every node.
5. Clean up: `silence-operator/silences/ceph-health-warning.yaml`, Ceph Grafana dashboards, Ceph network policies (envoy, victoria-metrics, system-namespaces), tuppr `talosupgrade.yaml` health check (replace by a miroir check, e.g. controller Deployment available), admission-policies README, `AGENTS.md` storage section.

### Phase 7 – Extend miroir to the control-plane SSDs

1. `talosctl -n <cp> wipe disk sda --drop-partition`, move the `RawVolumeConfig` + node label to `cluster.yaml.j2` (all nodes).
2. Delete the hand-authored CP `MiroirNode`s' `stub` pool by adding the `default` `lvmthin` pool to them, or let the group own them once the stub pool is empty (remove the hand-authored object only when it holds no legs).
3. Drop `agent.loopfileBaseDirs`. Result: 6 storage nodes, new volumes spread by capacity; existing volumes stay on the workers (no automatic rebalance).

## 5. Risks and open questions

| Risk                                                            | Mitigation                                                                                                             |
| --------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| kopiur volume populator + WFFC miroir class untested here       | Phase 4 round trip on a throwaway app before any real data                                                             |
| miroir is young (0.12.x, weekly releases) and issue #636 open   | Retained Ceph PVs until bake ends, hourly kopiur backups, pin chart version, read changelog before every Renovate bump |
| Sync replication on DRAM-less BX500 SSDs                        | fio in Phase 4; latency-sensitive apps can use `allowRemoteVolumeAccess: "false"`                                      |
| Single NIC: DRBD traffic shares the node network                | Optional later: dedicated VLAN via `miroir.home-operations.com/address` node annotation                                |
| DRBD port collision with Ceph dashboard (7000, host network)    | Dashboard disabled in Phase 1b, before miroir is installed                                                             |
| Restore of large volumes (silo, synapse, jellyfin) takes long   | Schedule; Runbook B (rsync, warm copy) is an alternative for the largest ones                                          |
| Restore `onMissingSnapshot: Continue` would create an empty PVC | Set to `Fail` for the whole migration                                                                                  |
| Capacity during transition: only 3 storage nodes                | 1.4 TB usable vs ~330 GiB data                                                                                         |
