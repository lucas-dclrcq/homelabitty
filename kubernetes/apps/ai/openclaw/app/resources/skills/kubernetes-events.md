---
name: kubernetes-events
description: Read recent Kubernetes object events to explain why a pod is failing, pending, or being restarted
metadata:
  { "openclaw": { "emoji": "📅" } }
user-invocable: true
disable-model-invocation: false
---

Events are the fastest answer to "why is this object not doing what it should".
Reach for them before reading logs: a `Pending` pod, a failing mount, an image
pull failure, or an evicted pod all explain themselves in events, not in
application logs.

## How to read them

Use the **kubernetes MCP tools** (`events_list`, or `resources_list` for
`v1/Event`). Access is read-only cluster-wide; Secrets are not readable.

Events are namespaced and short-lived — the apiserver keeps roughly the last
hour. For anything older, query the event stream in Loki instead:

```
{job="integrations/kubernetes/eventhandler"} |= "<object-name>"
```

(see the `loki` skill for the full request shape).

## What each reason usually means

| Reason | Read it as |
| --- | --- |
| `FailedScheduling` | No node satisfies requests/affinity/taints, or a required PVC is unbound |
| `FailedMount` / `FailedAttachVolume` | PVC not bound, CSI/Ceph problem, or an RWO volume still attached to another node |
| `ProvisioningFailed` | StorageClass or CSI driver rejected the claim — check the Rook Ceph or VolSync side |
| `Unhealthy` | A liveness/readiness probe is failing; the message carries the probe's response |
| `BackOff` / `CrashLoopBackOff` | Container keeps exiting; the exit code and last-terminated reason matter more than the event |
| `OOMKilling` / last state `OOMKilled` | Memory limit too low, or a leak |
| `Failed` with `ErrImagePull` / `ImagePullBackOff` | Bad tag/digest, or the registry is unreachable (this cluster mirrors through Spegel) |
| `Evicted` | Node under disk or memory pressure — check the node, not the pod |
| `NodeNotReady` | Kubelet lost; the pod is collateral damage |

## Triage order

1. `events_list` scoped to the failing object's namespace, newest first.
2. Read the pod's `status.containerStatuses[].lastState.terminated` (exit code,
   reason, finishedAt) with the MCP resource tools.
3. Only then go to logs (`loki` skill) for the application-level cause.
4. If the object is Flux-managed and simply never appeared, the problem is
   upstream in reconciliation — use the `flux` skill.

## This cluster

- Nodes: `bee`, `burrich`, `chade`, `fitz`, `fool`, `nighteyes` (Talos Linux).
- Storage is Rook Ceph (`ceph-block`, `ceph-filesystem`), OpenEBS hostpath for
  local scratch, and NFS from TrueNAS. RWO Ceph volumes are a common source of
  `Multi-Attach` and `FailedMount` events during a rollout.
- Nothing is edited by hand: if an object looks wrong, the fix is in git.
