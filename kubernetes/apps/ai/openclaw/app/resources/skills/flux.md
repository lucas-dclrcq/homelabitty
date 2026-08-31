---
name: flux
description: Inspect Flux CD GitOps reconciliation state (Kustomizations, HelmReleases, sources) to explain why a change is not live
metadata:
  { "openclaw": { "emoji": "🔁", "homepage": "https://fluxcd.io/flux/components/" } }
user-invocable: true
disable-model-invocation: false
---

Everything in this cluster is deployed by Flux from the `home-kubernetes` Git
repository. If a workload is missing, stale, or reverted, the cause is almost
always a failed reconciliation rather than the workload itself.

## How to read state

There is no `flux` CLI in this container. Use the **kubernetes MCP tools** to
read the custom resources directly (read-only):

| What | Group / kind |
| --- | --- |
| Git source | `source.toolkit.fluxcd.io/v1` `GitRepository` (`flux-system/home-kubernetes`) |
| Chart / OCI source | `source.toolkit.fluxcd.io/v1` `OCIRepository`, `HelmRepository`, `HelmChart` |
| Kustomize apply unit | `kustomize.toolkit.fluxcd.io/v1` `Kustomization` |
| Helm release | `helm.toolkit.fluxcd.io/v2` `HelmRelease` |
| Alerting | `notification.toolkit.fluxcd.io/v1beta3` `Alert`, `Provider` |

For each, the answer is in `.status.conditions` — look at `Ready` (and
`Reconciling` / `Stalled`), then `.status.lastAppliedRevision` versus the
source's `.status.artifact.revision`.

Prometheus also exposes this; `gotk_reconcile_condition{type="Ready",status="False"} == 1`
lists everything currently broken in one query (see the `prometheus` skill).

## Reconciliation chain

```
GitRepository (flux-system/home-kubernetes)
  └─ Kustomization cluster-apps
       └─ Kustomization <namespace>            (kubernetes/apps/<ns>/kustomization.yaml)
            └─ Kustomization <app>             (kubernetes/apps/<ns>/<app>/ks.yaml)
                 └─ HelmRelease / plain manifests
```

A failure at any level stops everything below it, so always walk **down** from
the source: a red `HelmRelease` whose parent `Kustomization` is also red is a
symptom, not the cause.

## Common failure shapes

- **`Ready=False`, "failed to decrypt"** — SOPS/Age problem on a `*.sops.yaml`.
- **`Ready=False`, "variable substitution failed" / a literal `${VAR}` in the
  applied object** — the var is missing from the `cluster-settings` ConfigMap or
  `cluster-secrets` Secret, or an inline shell `${VAR}` was not escaped as
  `$${VAR}` (Flux replaces undefined vars with an empty string).
- **`HelmRelease` "upgrade retries exhausted"** — read
  `.status.history` and the release's own pod events; Flux stops retrying until
  the spec changes or it is reconciled again.
- **`dependsOn` not ready** — the named Kustomization is blocked upstream.
- **Object keeps reverting** — it is Flux-managed and someone edited it live;
  git is authoritative.
- **Object disappeared** — it was removed from a `kustomization.yaml`, and
  `prune: true` deleted it.

## Boundaries

Access is **read-only**. Do not attempt to annotate, patch, suspend, resume, or
force a reconcile — those verbs are not granted, and the fix for a GitOps
cluster belongs in a commit. Report what is broken and what the change should
be; a human lands it.
