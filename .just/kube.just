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

[doc('Snapshot all kopiur-protected PVCs')]
snapshot:
    kubectl get snapshotpolicies --no-headers -A | while read -r ns name _; do \
        kubectl kopiur snapshot now --policy "$name" -n "$ns"; \
    done

[doc('Force a kopiur backup for an app')]
backup namespace app:
    kubectl kopiur snapshot now --policy {{ app }} -n {{ namespace }} --wait

[doc('Suspend or resume kopiur (all backups, restores and maintenance)')]
kopiur state:
    kubectl patch clusterrepository truenas --type merge -p '{"spec":{"suspend":{{ if state == "suspend" { "true" } else { "false" } }}}}'

