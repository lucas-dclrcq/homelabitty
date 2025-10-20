set quiet
set shell := ['bash', '-eu', '-o', 'pipefail', '-c']

[private]
default:
    just --list kube

[doc('Spawn a shell on a node')]
node-shell node:
    kubectl node-shell -n kube-system -x {{node}}

[doc('Prune all unused Pods')]
prune-pods:
    for phase in Failed Pending Succeeded; do \
        kubectl delete pods -A --field-selector status.phase="${phase}" --ignore-not-found=true; \
    done

[doc('View a secret')]
view-secret namespace secret:
    kubectl view-secret -n {{ namespace }} {{ secret }}

[doc('Browse a PVC')]
browse-pvc namespace claim:
    kubectl browse-pvc -n {{ namespace }} -i mirror.gcr.io/alpine:latest {{ claim }}

[doc('Snapshot VolSync PVCs')]
snapshot:
    kubectl get replicationsources --no-headers -A | while read -r ns name _; do \
        kubectl -n "$ns" patch replicationsources "$name" --type merge -p '{"spec":{"trigger":{"manual":"$(date +%s)"}}}'; \
    done

[doc('Suspend or resume VolSync')]
volsync state:
    flux -n volsync-system {{ state }} kustomization volsync
    flux -n volsync-system {{ state }} helmrelease volsync
    kubectl -n volsync-system scale deployment volsync --replicas {{ if state != "suspend" { "1" } else { "0" } }}

