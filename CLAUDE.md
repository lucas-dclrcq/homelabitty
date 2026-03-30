# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

GitOps homelab repository managing a Talos Linux Kubernetes cluster ("hoohoot") via Flux CD. All changes are deployed by pushing to `main` — Flux reconciles the Git state to the cluster.

## Common Commands

### Direct CLI
```bash
flux get ks -A                       # List all Flux Kustomizations and their status
flux get hr -A                       # List all HelmReleases and their status
flux logs --kind=HelmRelease --name=<app>  # Flux logs for a specific app
kubectl get hr -A                    # Quick HelmRelease status check
```



## Architecture

### Deployment Flow
```
Git push → Flux GitRepository → cluster-apps Kustomization → per-namespace Kustomization → per-app Kustomization → HelmRelease/resources
```

The top-level `kubernetes/flux/apps.yaml` defines `cluster-apps` which patches all child Kustomizations with: SOPS decryption, variable substitution (from `cluster-settings` ConfigMap + `cluster-secrets` Secret), and HelmRelease defaults (retry strategies, CRD handling, cleanup).

### Directory Layout
```
kubernetes/
├── apps/<namespace>/<app>/          # Application deployments
│   ├── ks.yaml                      # Flux Kustomization (metadata, deps, components)
│   └── app/
│       ├── kustomization.yaml       # Kustomize resource list
│       ├── helmrelease.yaml         # Helm chart values
│       ├── ocirepository.yaml       # OCI chart source
│       └── externalsecret.yaml      # Secret injection (if needed)
├── bootstrap/flux/                  # Flux bootstrap resources
├── components/                      # Reusable Kustomize components
│   ├── common/                      # Base (namespace, alerts, repos, sops, vars)
│   ├── dragonfly/                   # Redis cache sidecar
│   ├── security-policy/             # Forward auth policy
│   └── volsync/                     # Backup component
└── flux/                            # Flux config (repos, vars, settings)
```

Each namespace directory has a `kustomization.yaml` that includes the `common` component and lists all `ks.yaml` files for that namespace.

### App Structure Pattern

**ks.yaml** (Flux Kustomization): defines app name, namespace, path, dependencies, components, and `postBuild.substitute` vars. Uses YAML anchors (`&app`, `&namespace`) for DRY naming.

**helmrelease.yaml**: most apps use the [bjw-s app-template](https://github.com/bjw-s-labs/helm-charts) chart via OCI. Chart source is an OCIRepository resource rather than a HelmRepository.

**Variable substitution**: `${SECRET_DOMAIN}`, `${SECRET_*}`, etc. in manifests are replaced at reconciliation time from `cluster-settings`/`cluster-secrets`. The `APP` variable is set per-app in `ks.yaml`. Use Flux substitution only for non-secret configuration (domains, feature flags). App credentials must go through Vault via ExternalSecret.

**Multi-component apps**: When an app requires a separate backing service (e.g., app + MongoDB), split into multiple Flux Kustomizations in the same `ks.yaml` (separated by `---`), each pointing to its own subdirectory. Use `dependsOn` for ordering. Each component gets its own VolSync volume. Do NOT combine unrelated services in the same controller/pod — VolSync PVCs are RWO and each Kustomization with the VolSync component creates exactly one PVC named `${APP}`.

```
<app>/
├── ks.yaml              # Multiple Flux Kustomizations
├── app/                 # Main application
│   ├── kustomization.yaml
│   ├── helmrelease.yaml
│   └── ...
└── <backing-service>/   # e.g., mongodb/
    ├── kustomization.yaml
    ├── helmrelease.yaml
    └── ...
```

### Secrets

- **HashiCorp Vault** (preferred for app secrets): `ExternalSecret` resources pull from the `hashicorp-vault` ClusterSecretStore. Vault path convention: `apps/<namespace>/<app-name>` (e.g., `sqq/rocket-chat`). Use `envFrom` with a `secretRef` in the HelmRelease to inject credentials.
- **SOPS + Age**: files matching `*.sops.yaml` are encrypted. Flux decrypts automatically via the `sops-age` secret. Used for cluster-level secrets, not app credentials.
- **CrunchyData PGO secrets**: Apps using PostgreSQL pull DB credentials via namespace-specific `ClusterSecretStore` (e.g., `crunchy-pgo-sqq-secrets`).
- **Config**: `.sops.yaml` defines encryption rules; `age.key` holds the Age key.

### Networking

- **Envoy Gateway**: internal (`192.168.1.47`) and external (`192.168.1.48`) gateways in `network` namespace.
- **Routes**: apps define `route` in HelmRelease values with `parentRefs` pointing to `internal` or `external` gateway.
- **Pod labels** like `ingress.home.arpa/envoy-external: allow` control network policy access.

### Key Infrastructure
- **Cluster**: Talos Linux, 3 control plane + 3 worker nodes, VIP `192.168.1.42`
- **Storage**: Rook Ceph, NFS (TrueNAS), MinIO, Garage, VolSync backups
- **Databases**: CrunchyData PGO (PostgreSQL Operator) with pgBackRest
- **Monitoring**: Prometheus + Grafana + Loki + Alloy (observability namespace)

### Talos Management

Node configs are generated by `talhelper` from `talos/talconfig.yaml` + `talos/talsecret.sops.yaml` into `talos/clusterconfig/`. Use `just talos generate-config` after editing `talconfig.yaml`.

### Templating

`task configure` runs Makejinja (config: `.minijinja.toml`) to render `.yaml.j2` templates using `config.yaml` values, then encrypts secrets with SOPS and validates with kubeconform. This is for bootstrap/initial setup — runtime config uses Flux's `postBuild` substitution.

### Renovate

Automated dependency updates via Renovate. Config in `.renovaterc.json5` with presets in `.renovate/`. Handles Flux manifests, Docker image digests, and Helm chart versions. Files matching `*.sops.*` are excluded.

### Label Convention

`app.kubernetes.io/name` is set via `commonMetadata.labels` in `ks.yaml` and propagates to all resources. Use `app.kubernetes.io/component` for labels that must survive Flux's `commonMetadata` override. The label `substitution.flux.home.arpa/disabled` opts out of variable substitution.
