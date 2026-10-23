#!/usr/bin/env bash
#
# Scale down (or back up) all apps that use a given CrunchyData PGO PostgresCluster.
# Useful before a major PostgreSQL upgrade: quiesce all clients before touching the DB.
#
# Usage:
#   scale_db_apps.sh <cluster-name> [down|up|list]
#
# Examples:
#   scale_db_apps.sh postgres-16 down
#   scale_db_apps.sh postgres-sqq up
#   scale_db_apps.sh postgres-16 list
#
# How it works:
#   - Greps kubernetes/apps/**/*externalsecret*.yaml for `key: <cluster>-pguser-...`
#   - For each match, extracts namespace and app name from the path:
#       kubernetes/apps/<namespace>/<app>/app/externalsecret.yaml
#   - Apps whose HelmRelease or workloads don't follow the <app> naming are
#     mapped explicitly in targets_for().
#   - down: suspends the HelmRelease (so Flux won't reconcile), records each
#           workload's replica count in the ${REPLICAS_ANNOTATION} annotation
#           and scales it to 0.
#   - up:   scales each workload back to its recorded replica count, then
#           resumes the HelmRelease. Resuming alone is not enough: without drift
#           detection, helm-controller leaves an in-sync release at 0 replicas.
#   - list: prints the discovered apps and the workloads they map to.

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <cluster-name> [down|up|list]"
  echo "  cluster-name  PostgresCluster name (e.g. postgres-16, postgres-sqq, postgres-vector)"
  echo "  down          Suspend HelmReleases and scale workloads to 0 (default)"
  echo "  up            Restore recorded replicas and resume HelmReleases"
  echo "  list          Print discovered apps and exit"
  exit 1
fi

CLUSTER="$1"
ACTION="${2:-down}"
REPLICAS_ANNOTATION="hoohoot.org/replicas-before-scale-down"

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
APPS_DIR="${REPO_ROOT}/kubernetes/apps"

if [ ! -d "$APPS_DIR" ]; then
  echo "error: cannot find ${APPS_DIR}"
  exit 1
fi

# Discover apps referencing the cluster via ExternalSecret keys like:
#   key: <cluster>-pguser-<role>
# Path convention: kubernetes/apps/<ns>/<app>/app/*externalsecret*.yaml
MATCHES=()
while IFS= read -r line; do
  MATCHES+=("$line")
done < <(
  grep -RIl --include='*externalsecret*.yaml' -E "key:[[:space:]]+${CLUSTER}-pguser-" "$APPS_DIR" \
    | sed -E "s|^${APPS_DIR}/([^/]+)/([^/]+)/.*|\1 \2|" \
    | sort -u
)

if [ ${#MATCHES[@]} -eq 0 ]; then
  echo "No apps found referencing cluster '${CLUSTER}'."
  exit 0
fi

# Prints "<helmrelease> <kind/name>..." for an app. Controllers come before the
# workloads they manage, so they are stopped first and restarted last.
targets_for() {
  local ns="$1" app="$2"
  case "${ns}/${app}" in
    matrix/matrix-stack)
      # HelmRelease `matrix`; the chart sets its own app.kubernetes.io/name labels.
      echo "matrix statefulset/matrix-synapse-main deployment/matrix-matrix-authentication-service"
      ;;
    ai/litellm)
      # The litellm Deployment is owned by a LiteLLMProxy: stop its operator first,
      # or it scales the proxy straight back up.
      echo "litellm-operator deployment/litellm-operator deployment/litellm"
      ;;
    *)
      echo "${app} $(kubectl -n "$ns" get deployment,statefulset \
        --selector="app.kubernetes.io/name=${app}" -o name | tr '\n' ' ')"
      ;;
  esac
}

echo "Apps using cluster '${CLUSTER}':"
for line in "${MATCHES[@]}"; do
  ns="${line% *}"
  app="${line#* }"
  read -r hr workloads <<<"$(targets_for "$ns" "$app")"
  printf "  - %-14s %-18s hr=%-18s %s\n" "$ns" "$app" "$hr" "$workloads"
done

case "$ACTION" in
  list)
    exit 0
    ;;
  down)
    for line in "${MATCHES[@]}"; do
      ns="${line% *}"
      app="${line#* }"
      read -r hr workloads <<<"$(targets_for "$ns" "$app")"
      echo "==> Suspending HelmRelease ${ns}/${hr}"
      flux suspend hr "$hr" -n "$ns" || echo "   (no HelmRelease ${ns}/${hr}, skipping suspend)"
      for w in $workloads; do
        replicas="$(kubectl -n "$ns" get "$w" -o jsonpath='{.spec.replicas}')"
        # Never overwrite a recorded count with the 0 of a previous run.
        if [ "$replicas" != "0" ]; then
          kubectl -n "$ns" annotate "$w" --overwrite "${REPLICAS_ANNOTATION}=${replicas}" >/dev/null
        fi
        echo "==> Scaling ${ns}/${w} (${replicas}) to 0"
        kubectl -n "$ns" scale "$w" --replicas=0
      done
    done
    echo "Done. Verify with: kubectl get pods -A -l app.kubernetes.io/name=<app>"
    ;;
  up)
    for line in "${MATCHES[@]}"; do
      ns="${line% *}"
      app="${line#* }"
      read -r hr workloads <<<"$(targets_for "$ns" "$app")"
      for w in $workloads; do
        replicas="$(kubectl -n "$ns" get "$w" -o jsonpath="{.metadata.annotations.${REPLICAS_ANNOTATION//./\\.}}")"
        if [ -z "$replicas" ]; then
          echo "   (${ns}/${w} has no recorded replica count, leaving it to Flux)"
          continue
        fi
        echo "==> Scaling ${ns}/${w} back to ${replicas}"
        kubectl -n "$ns" scale "$w" --replicas="$replicas"
        kubectl -n "$ns" annotate "$w" "${REPLICAS_ANNOTATION}-" >/dev/null
      done
      echo "==> Resuming HelmRelease ${ns}/${hr}"
      flux resume hr "$hr" -n "$ns" || echo "   (no HelmRelease ${ns}/${hr}, skipping resume)"
    done
    echo "Done."
    ;;
  *)
    echo "Invalid action: ${ACTION}"
    echo "Usage: $0 <cluster-name> [down|up|list]"
    exit 1
    ;;
esac
