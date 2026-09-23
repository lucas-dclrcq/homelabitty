---
name: deploy-new-app
description: Use when deploying a new application to the homelab Kubernetes cluster (Flux CD + Helm, bjw-s app-template). Guides creating ks.yaml, ocirepository.yaml, helmrelease.yaml, externalsecret.yaml under kubernetes/apps/<namespace>/<app> and registering the app in the namespace kustomization. Trigger on "deploy a new app", "add an application", "add <app> to the cluster", "new app".
---

# Deploy a New Application

## Overview

This skill guides adding a new application deployment to the cluster via Flux CD + Helm. The default chart is **bjw-s-labs app-template** (`oci://ghcr.io/bjw-s-labs/helm/app-template`), pulled as an OCI artifact. Only use an official/first-party chart when the app provides one **and** it requires resources app-template cannot model (e.g. CRDs, ClusterRoles, Webhooks for operators).

The cluster is GitOps-driven: push to `main` and Flux reconciles. Everything lives under `kubernetes/apps/<namespace>/<app>/`.

---

## Step 1: Gather Requirements

> **STOP. Do not create any files until every question below has been answered by the user.** Do not infer or assume answers — ask explicitly, even if an answer seems obvious from context.

Before creating any files, ask the user for:

| Question                    | Notes                                                                                                                                                                                            |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Container image**         | Full reference, e.g. `ghcr.io/foo/bar:1.2.3`. This repo uses plain semver tags (not digests) for app images — check existing apps.                                                               |
| **Namespace**               | Must be one of the existing directories under `kubernetes/apps/`. If a new namespace is needed, that is a separate task — see [Creating a new namespace](#creating-a-new-namespace).              |
| **App name**                | Kebab-case slug, used as the directory name and the Kubernetes resource name.                                                                                                                    |
| **Exposed port**            | The port the container listens on.                                                                                                                                                               |
| **HTTP route needed?**      | `internal` (LAN-only, behind the `internal` Gateway) or `external` (public internet, behind the `external` Gateway). Both live in the `network` namespace.                                      |
| **Persistent data needed?** | If yes, ask capacity (e.g. `5Gi`). Stateful apps use the `volsync` component; ephemeral scratch space uses `emptyDir`.                                                                           |
| **Secrets needed?**         | If yes, ask what to store. App secrets live in HashiCorp Vault (ClusterSecretStore `hashicorp-vault`); PostgreSQL credentials come from CrunchyData PGO (`crunchy-pgo-secrets`).                  |
| **Database needed?**        | If yes, a PostgreSQL user/db must be provisioned in the PGO `PostgresCluster` and its credentials pulled via a dedicated ExternalSecret.                                                         |

### Optional: search for prior art

Search the web (e.g. `site:github.com home-ops <app-name> helmrelease.yaml`) for how other home-ops repos deploy the app. Adapt findings to the patterns below — do not copy verbatim.

---

## Step 2: Understand the File Structure

Every app follows this layout:

```
kubernetes/apps/<namespace>/<app-name>/
├── ks.yaml                     # Flux Kustomization resource (one or more, separated by ---)
└── app/
    ├── kustomization.yaml      # lists resources in this directory
    ├── ocirepository.yaml      # OCIRepository for the helm chart
    ├── helmrelease.yaml        # HelmRelease with all values
    ├── externalsecret.yaml     # (optional) ExternalSecret for secrets
    ├── probes.yaml             # (optional) blackbox-exporter Probe
    ├── servicemonitor.yaml     # (optional) Prometheus ServiceMonitor
    ├── ciliumnetworkpolicy.yaml# (optional) CiliumNetworkPolicy
    ├── grafanadashboard.yaml   # (optional) GrafanaDashboard
    ├── <name>.pvc.yaml         # (optional) standalone PVC (shared/RWX, not volsync)
    └── resources/              # (optional) ConfigMaps mounted into the pod
```

There is **no** top-level `kustomization.yaml` inside the app directory — the namespace `kustomization.yaml` references `./<app-name>/ks.yaml` directly.

---

## Step 3: Create the Files

### 3a. `kubernetes/apps/<namespace>/<app-name>/ks.yaml`

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app <app-name>
  namespace: &namespace <namespace>
spec:
  targetNamespace: *namespace
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  dependsOn:
    - name: external-secrets-stores
      namespace: external-secrets
  path: ./kubernetes/apps/<namespace>/<app-name>/app
  prune: true
  sourceRef:
    kind: GitRepository
    name: home-kubernetes
    namespace: flux-system
  wait: false
  interval: 1h
  postBuild:
    substitute:
      APP: *app
```

Notes:
- `metadata.name` is the Flux Kustomization name (anchored `&app`); the actual release name is `targetNamespace` + the HelmRelease `metadata.name`.
- `wait: false`, `interval: 1h` are the repo-wide defaults — keep them.
- `dependsOn` entries are `{name, namespace}` objects, **not** plain names.
- `postBuild.substitute` maps `${APP}` for variable substitution in the manifests.

**When to add `components` (paths relative to `kubernetes/apps/<namespace>/<app-name>/`):**

| Need                              | Add to `spec.components`                            | Extra `postBuild.substitute`        | Extra `dependsOn`                                        |
| --------------------------------- | --------------------------------------------------- | ----------------------------------- | -------------------------------------------------------- |
| Persistent data with backup       | `../../../../components/volsync`                    | `VOLSYNC_CAPACITY: <size>`          | — (volsync is not a hard dependency here)                |
| Redis cache sidecar               | `../../../../components/dragonfly`                  | (optional) `DRAGONFLY_ARGS_DEFAULT_LUA_FLAGS` | `{name: dragonfly, namespace: flux-system}` |
| Forward-auth (Authentik)          | `../../../../components/security-policy/forward-auth` | —                                 | —                                                       |
| HTTP route                        | —                                                   | —                                   | `{name: envoy-gateway, namespace: network}`             |

**Standard `dependsOn` entries:**
- `{name: external-secrets-stores, namespace: external-secrets}` — whenever the app uses an ExternalSecret.
- `{name: envoy-gateway, namespace: network}` — whenever the app defines a `route`.
- `{name: dragonfly, namespace: flux-system}` — when using the dragonfly component.
- `{name: crunchy-postgres-operator, namespace: flux-system}` — when using a PGO database.

**Dragonfly health check** — when using the dragonfly component, also add:

```yaml
  healthCheckExprs:
    - apiVersion: dragonflydb.io/v1alpha1
      kind: Dragonfly
      failed: status.phase != 'ready'
      current: status.phase == 'ready'
```

### 3b. `kubernetes/apps/<namespace>/<app-name>/app/ocirepository.yaml`

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/source.toolkit.fluxcd.io/ocirepository_v1.json
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: <app-name>
spec:
  interval: 15m
  layerSelector:
    mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip
    operation: copy
  ref:
    tag: 5.2.1
  url: oci://ghcr.io/bjw-s-labs/helm/app-template
```

- `name` must match the HelmRelease's `chartRef.name` (and thus the anchor `*app`).
- The `tag` is the app-template chart version — check an existing `ocirepository.yaml` for the current value.
- If the chart does **not** publish an OCI artifact, use a `HelmRepository` source instead and reference it with `chart:` in the HelmRelease (see `kubernetes/apps/matrix/synapse/app/helmrepository.yaml`).

### 3c. `kubernetes/apps/<namespace>/<app-name>/app/helmrelease.yaml`

Start from this minimal secure template and expand only as needed:

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/bjw-s-labs/helm-charts/main/charts/other/app-template/schemas/helmrelease-helm-v2.schema.json
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: &app <app-name>
spec:
  interval: 1h
  chartRef:
    kind: OCIRepository
    name: *app
  values:
    global:
      createDefaultServiceAccount: false

    controllers:
      <app-name>:
        annotations:
          reloader.stakater.com/auto: "true" # remove if no configmaps/secrets
        pod:
          labels:
            ingress.home.arpa/gateway-external: allow # for external routes (CiliumNetworkPolicy)
            ingress.home.arpa/prometheus: allow      # if a ServiceMonitor/Probe scrapes it
            egress.home.arpa/kubedns: allow
            egress.home.arpa/world: allow
        containers:
          app:
            image:
              repository: <image-repo>
              tag: <image-tag>

            probes:
              liveness:
                enabled: true
              readiness:
                enabled: true
              startup:
                enabled: true
                spec:
                  failureThreshold: 30
                  periodSeconds: 5

            resources:
              requests:
                cpu: 10m
                memory: 64Mi
              limits:
                memory: 256Mi # tune based on app; NEVER set limits.cpu

            securityContext:
              allowPrivilegeEscalation: false
              readOnlyRootFilesystem: true # start true; relax only if proven necessary
              capabilities: { drop: ["ALL"] }

    defaultPodOptions:
      automountServiceAccountToken: false
      enableServiceLinks: false
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        seccompProfile: { type: RuntimeDefault }

    service:
      app:
        controller: *app
        ports:
          http:
            port: &port <port>

    route:
      app:
        annotations:
          homelab-manager.hoohoot.org/enabled: "true"
          homelab-manager.hoohoot.org/category: "Misc"
          homelab-manager.hoohoot.org/description: "<short description>"
          homelab-manager.hoohoot.org/logo-url: "<logo url>"
        hostnames:
          - "{{ .Release.Name }}.${SECRET_DOMAIN}"
        parentRefs:
          - name: external # or `internal` for LAN-only
            namespace: network
        rules:
          - backendRefs:
              - name: *app
                port: *port
```

**Variable substitution** — `${SECRET_DOMAIN}`, `${LIMITED_DOMAIN}`, `${INTERNAL_DOMAIN}`, `${TIMEZONE}`, etc. come from `cluster-settings`/`cluster-secrets` (applied cluster-wide by `cluster-apps`). Use them for non-secret configuration. `${APP}` is set per-app in `ks.yaml`.

**Common additions:**

- **Writable paths with `readOnlyRootFilesystem: true`** — mount `emptyDir` for any path the app writes:

```yaml
    persistence:
      tmp:
        type: emptyDir
        globalMounts:
          - path: /tmp
```

- **Persistent volume via volsync** — reference the claim created by the component (named `${APP}`):

```yaml
    persistence:
      config:
        enabled: true
        existingClaim: *app
        globalMounts:
          - path: /data
```

- **Secrets from ExternalSecret** — inject the whole secret via `envFrom`:

```yaml
            envFrom:
              - secretRef:
                  name: <app-name>-secret
```

  or a single key:

```yaml
            env:
              SOME_VAR:
                valueFrom:
                  secretKeyRef:
                    name: <app-name>-secret
                    key: SOME_VAR
```

- **Standalone PVC** (shared/RWX scratch space, e.g. machine-learning cache) — create `<name>.pvc.yaml` and mount via `existingClaim`. This is *not* the volsync pattern (see `immich/app/ml-cache-pvc.yaml`).

- **Non-standard UID** — if the upstream image runs as a specific UID, adjust `runAsUser`/`runAsGroup`. Use `568` for apps following the home-operations convention, or `65534` for nginx-based images. Verify with the image docs — do not assume 1000.

- **Second route (LAN + WAN)** — add another entry under `route` with `parentRefs.name: internal`.

### 3d. `kubernetes/apps/<namespace>/<app-name>/app/kustomization.yaml`

List every file in the `app/` directory (alphabetical order):

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./externalsecret.yaml
  - ./helmrelease.yaml
  - ./ocirepository.yaml
  # - ./probes.yaml
  # - ./servicemonitor.yaml
  # - ./ciliumnetworkpolicy.yaml
  # - ./grafanadashboard.yaml
```

### 3e. `kubernetes/apps/<namespace>/<app-name>/app/externalsecret.yaml` (optional)

Only create this if the app needs secrets. The `name` is `<app-name>` (not `<app-name>-secret`); the `target.name` is `<app-name>-secret`.

**App secrets from Vault** (`hashicorp-vault` ClusterSecretStore, KV path `<namespace>/<app>`):

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/external-secrets.io/externalsecret_v1.json
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: <app-name>
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: hashicorp-vault
  target:
    name: <app-name>-secret
    creationPolicy: Owner
    template:
      engineVersion: v2
      data:
        SOME_VAR: "{{ .vault_key_name }}"
  dataFrom:
    - extract:
        key: <namespace>/<app-name>
```

**PostgreSQL credentials from PGO** (a *separate* ExternalSecret, `target.name: <app-name>-db-secret`):

```yaml
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: <app-name>-db-secret
spec:
  refreshInterval: 1m
  secretStoreRef:
    name: crunchy-pgo-secrets
    kind: ClusterSecretStore
  target:
    name: <app-name>-db-secret
    template:
      engineVersion: v2
      data:
        DATABASE_URL: '{{ index . "uri" }}'
  dataFrom:
    - extract:
        key: postgres-16-pguser-<app-name>
```

### 3f. Optional companion files

- **probes.yaml** — blackbox-exporter `Probe` for external endpoint monitoring (see `miniflux/app/probes.yaml`).
- **servicemonitor.yaml** — Prometheus `ServiceMonitor` for app metrics (see `bambuddy/app/servicemonitor.yaml`).
- **ciliumnetworkpolicy.yaml** — explicit network policy for gateway/prometheus ingress and egress (see `bambuddy/app/ciliumnetworkpolicy.yaml`). Used when the pod-label selectors are not enough.
- **grafanadashboard.yaml** — `GrafanaDashboard` CR importing a public dashboard JSON (see `miniflux/app/grafanadashboard.yaml`).
- **resources/** — ConfigMaps mounted into the pod (config files, scripts).

---

## Step 4: Register the App in the Namespace Kustomization

Open `kubernetes/apps/<namespace>/kustomization.yaml` and add `./<app-name>/ks.yaml` to the `resources` list, maintaining alphabetical order:

```yaml
resources:
  - ./existing-app-1/ks.yaml
  - ./new-app-name/ks.yaml   # add here
  - ./existing-app-2/ks.yaml
```

The namespace kustomization itself follows one of two styles (do **not** modify it beyond adding the one line):

1. **Component style** (most namespaces): `namespace: <ns>` + `components: [../../components/common]` + `resources: [...]`.
2. **Explicit style** (older namespaces): `resources: [./namespace.yaml, ...]`.

### Creating a new namespace (separate task)

Do not conflate with adding an app. Creating a new namespace means:
1. Create `kubernetes/apps/<namespace>/kustomization.yaml` (copy an existing namespace's, using the component style with `components: [../../components/common]`).
2. If the older explicit style is required, also add a `namespace.yaml` with the `kustomize.toolkit.fluxcd.io/prune: disabled` and `volsync.backube/privileged-movers: "true"` annotations.
3. Register the namespace directory wherever sibling namespaces are aggregated.

---

## Step 5: Security Checklist

Verify every item before finishing:

- [ ] `runAsNonRoot: true` in `defaultPodOptions.securityContext`
- [ ] `runAsUser` / `runAsGroup` set to a specific non-zero UID (not `0`)
- [ ] `seccompProfile: { type: RuntimeDefault }` in `defaultPodOptions.securityContext`
- [ ] `allowPrivilegeEscalation: false` in container `securityContext`
- [ ] `capabilities: { drop: ["ALL"] }` in container `securityContext`
- [ ] `readOnlyRootFilesystem: true` attempted first; only `false` if the app genuinely cannot run otherwise (document why with a comment)
- [ ] `automountServiceAccountToken: false` in `defaultPodOptions`
- [ ] `enableServiceLinks: false` in `defaultPodOptions`
- [ ] `global.createDefaultServiceAccount: false`
- [ ] Resource `limits.cpu` is **not set** — only `requests.cpu` and `limits.memory`
- [ ] Secrets are in ExternalSecret (Vault / PGO), never hardcoded in the HelmRelease

---

## Step 6: Validate

- `yamlfmt` — YAML formatting (auto-run by the `pre-commit` lefthook hook on staged `*.yaml` files).
- `task kubernetes:kubeconform` — validate rendered manifests against their CRD schemas.
- Commits use **Conventional Commits** (enforced by commitlint). Use e.g. `feat(<app-name>): deploy`.

---

## Common Pitfalls

- **Shell variables in ConfigMaps**: if a ConfigMap/`resources/` file contains shell scripts with `${VAR}` syntax, use `$${VAR}` to avoid kustomization substitution
- **Missing reloader annotation**: if the app reads a ConfigMap or Secret at startup, add `reloader.stakater.com/auto: "true"` to the controller so it restarts on changes.
- **Wrong UID**: some images (nginx, etc.) run as a specific non-1000 UID. Verify with the image docs rather than assuming 1000.
- **Not listed in the namespace kustomization**: the namespace `kustomization.yaml` is the source of truth for what Flux deploys. A directory that exists but is not listed there will not be deployed.
- **Missing `VOLSYNC_CAPACITY`**: using the `volsync` component without setting `VOLSYNC_CAPACITY` in `postBuild.substitute` defaults to `5Gi` and may fail to reconcile if the substitution is expected.
- **Postgres not provisioned**: creating the  ExternalSecret without adding a matching `users` entry (name + database) to `kubernetes/apps/infrastructure/crunchy-postgres-operator/cluster/postgrescluster.yaml` will fail — the `postgres-16-pguser-<app>` key will not exist.
- **Route without backendRefs**: the app-template `route` requires `rules[].backendRefs` pointing at the service port; omit it and Envoy has nothing to forward to.
