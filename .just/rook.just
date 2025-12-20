set quiet := true
set shell := ['bash', '-euo', 'pipefail', '-c']

rook_ceph_dir := justfile_dir() + '/kubernetes/apps/rook-ceph'

[private]
default:
  just -l rook

[doc('Zap (wipe) Ceph OSD disk on one or more nodes (defaults to /dev/sda)')]
zap-disk device="/dev/sda" *nodes:
  #!/usr/bin/env bash
  DEVICE="{{ device }}"
  JOBS_DIR="{{ rook_ceph_dir }}/jobs"
  nodes="{{ nodes }}"

  if [ -z "$nodes" ]; then
    just log error "Must specify at least one node"
    just log info "Usage: just rook:zap-disk [device] node1 [node2 node3...]"
    just log info "Example: just rook:zap-disk metal-04 metal-05 metal-06"
    exit 1
  fi

  gum confirm "⚠️  This will DESTROY all data on $DEVICE on nodes: $nodes. Continue?" || exit 0

  for node in $nodes; do
    gum style --foreground 212 --bold "=== Zapping $DEVICE on $node ==="

    JOB_NAME="disk-zap-$node-$(date +%s)"

    just template "$JOBS_DIR/disk-zap.yaml.j2" \
      -D job_name="$JOB_NAME" \
      -D node="$node" \
      -D device="$DEVICE" | kubectl apply -f -

    just spin "Waiting for disk wipe job on $node..." kubectl wait --for=condition=complete --timeout=300s job -n rook-ceph $JOB_NAME || \
      just log warn "Job may still be running. Check: kubectl logs -n rook-ceph job/$JOB_NAME"

    kubectl delete job -n rook-ceph $JOB_NAME 2>/dev/null || true
    echo ""
  done

  just log info "Disk zapping complete on $nodes"

[doc('Restart OSD prepare jobs to re-scan disks')]
restart-osd-prepare:
  just spin "Deleting OSD prepare jobs..." kubectl delete job -n rook-ceph -l app=rook-ceph-osd-prepare
  just log info "OSD prepare jobs deleted. They will be recreated automatically."
  just log info "Monitor with: kubectl get pods -n rook-ceph | grep osd-prepare"

[doc('Check Ceph cluster status')]
status:
  #!/usr/bin/env bash
  gum style --foreground 212 --bold "=== Ceph Cluster Status ==="
  kubectl -n rook-ceph get cephcluster
  echo ""
  gum style --foreground 212 --bold "=== Ceph Block Pool Status ==="
  kubectl -n rook-ceph get cephblockpool
  echo ""
  gum style --foreground 212 --bold "=== OSDs ==="
  kubectl -n rook-ceph get pods -l app=rook-ceph-osd
  echo ""
  gum style --foreground 212 --bold "=== Ceph Health (from toolbox) ==="
  kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph status 2>/dev/null || \
    just log warn "Toolbox not available. Enable it in the cluster config."

[doc('Show Ceph disk usage')]
disk-usage:
  kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph df

[doc('List all OSDs')]
list-osds:
  kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph osd tree

[doc('Force reconcile rook-ceph HelmReleases')]
reconcile:
  just spin "Reconciling rook-ceph-cluster..." flux reconcile helmrelease -n rook-ceph rook-ceph-cluster
  just spin "Reconciling rook-ceph-operator..." flux reconcile helmrelease -n rook-ceph rook-ceph-operator
  just log info "Reconciliation complete"

[doc('Check PVCs stuck in Pending status')]
check-pending-pvcs:
  #!/usr/bin/env bash
  gum style --foreground 212 --bold "=== Pending PVCs across all namespaces ==="
  kubectl get pvc -A | grep Pending || just log info "No pending PVCs found"

[doc('Describe a pending PVC to see why it is not binding')]
debug-pvc namespace pvc:
  kubectl describe pvc -n {{ namespace }} {{ pvc }}
