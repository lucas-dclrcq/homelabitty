# Admission policies

Native `ValidatingAdmissionPolicy` objects, evaluated by the apiserver itself.
No webhook, so no certificate to rotate, no latency on every admission and no
cluster-wide failure mode when a pod is down — which is the whole reason this
repo does not run Kyverno.

What the apiserver cannot do, and what would justify adding Kyverno later:
generating resources, mutating what already exists, background scanning of
live objects, and image signature verification.

## Where things live

|                         |                                                                                                       |
| ----------------------- | ----------------------------------------------------------------------------------------------------- |
| The policies            | `policies/`, one file per policy, each holding its `ValidatingAdmissionPolicy` **and** its binding    |
| Namespace enrolment     | `kubernetes/components/policy-baseline`, included from each enrolled namespace's `kustomization.yaml` |
| Per-workload exceptions | a label on the pod template of the workload that needs it                                             |

## Enrolment

A policy only applies to namespaces labelled `policy.home.arpa/admission:
enforce`, which is what including the `policy-baseline` component does:

```yaml
components:
    - ../../components/common
    - ../../components/policy-baseline
```

Enrolled, mirroring `netpol-baseline`: ai, auth, default, development,
downloads, home, infrastructure, matrix, media, network, observability,
security, vault. The system namespaces (kube-system, flux-system, rook-ceph,
cert-manager, external-secrets, kopiur-system, openebs-system, system-upgrade)
are **not** enrolled on purpose: they run the privileged workloads that make
the cluster work, and an operator that cannot create its pods takes the cluster
with it.

Opt-in is the point. A new infrastructure namespace is unaffected until someone
deliberately enrols it, so no policy can refuse pods in a namespace nobody
thought about.

## Exceptions

Granted per workload, by labelling the **pod template** — not the workload's
own metadata, which is a different label set:

```yaml
defaultPodOptions:
    labels:
        policy.home.arpa/run-as-root: allow
```

One label key per policy, so an exception grants exactly one thing. The value
is always `allow`, matching the `*.home.arpa/*: allow` vocabulary the network
policies use.

Beware the app-template trap: a controller's `pod.labels` **replaces**
`defaultPodOptions.labels` rather than merging, so when a controller already
declares `pod.labels`, the exception goes there, next to the netpol labels.

## Writing a policy

Three things the native API does not give you, and that every policy here has
to handle by hand:

- **No autogen.** Kyverno derives controller rules from a Pod rule. Here the
  `matchConstraints` have to list Deployments, StatefulSets, DaemonSets, Jobs
  and CronJobs explicitly, otherwise a bad Deployment is admitted and only its
  Pods are refused later — visible in a ReplicaSet event and nowhere in Flux.
  ReplicaSets are left out: the Deployment and the Pod rules already cover
  every path that creates one.
- **`matchConditions` cannot read `variables`.** Only `validations`,
  `auditAnnotations` and `messageExpression` can. Since exceptions belong in
  `matchConditions`, the walk down to the pod template (`object.metadata` for a
  Pod, `object.spec.jobTemplate.spec.template.metadata` for a CronJob,
  `object.spec.template.metadata` otherwise) is spelled out in each condition.
- **`cel.bind` is not available**, so there is no way to factor that walk out.

Test a policy before pushing it — a `Deny` binding that is wrong refuses real
workloads. Create a throwaway namespace carrying the enrolment label, apply the
policy, then exercise it with `kubectl apply --dry-run=server`: dry-run
requests go through admission, so denials surface without anything being
persisted.

## Policies

### `require-run-as-non-root-user`

Ported from [Kyverno's policy of the same
name](https://github.com/kyverno/policies/tree/main/pod-security-vpol/restricted/require-run-as-non-root-user)
(Pod Security Standards, restricted). `runAsUser` must be unset or greater than
zero, at the pod level and on every container, init container and ephemeral
container.

An **unset** `runAsUser` is allowed, which is the upstream semantics: the UID
then comes from the image's `USER` line, which admission cannot see. This
policy refuses an explicit `runAsUser: 0`, it does not prove a workload is
non-root. Trivy's KSV-0118 covers the complementary "no security context at
all" case.

Exception label: `policy.home.arpa/run-as-root: allow`.

Standing exceptions at the time of writing:

| Workload                          | Why                                                                                                                                                                                                                                          |
| --------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `default/onlyoffice`              | the all-in-one image boots nginx, postgresql and rabbitmq under supervisord                                                                                                                                                                  |
| `default/wallabag`                | upstream image runs its entrypoint as root                                                                                                                                                                                                   |
| `development/pacman-sync`         | the rsync container has to preserve ownership on the mirror tree                                                                                                                                                                             |
| `observability/smartctl-exporter` | reads `/dev/sda` and `/dev/nvme0n1` directly                                                                                                                                                                                                 |
| kopiur movers                     | root is required for the NFS repository, and the operator spawns them at backup time so there is no manifest here to label — the carve-out rides on `app.kubernetes.io/managed-by: kopiur`, the label kopiur stamps on everything it creates |

The kopiur carve-out is the one exception not expressed on a workload this repo
owns. If a restore ever gets refused, check that label first.
