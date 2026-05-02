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
#   - Greps kubernetes/apps/**/externalsecret.yaml for `key: <cluster>-pguser-...`
#   - For each match, extracts namespace and app name from the path:
#       kubernetes/apps/<namespace>/<app>/app/externalsecret.yaml
#   - down: suspends the HelmRelease (so Flux won't reconcile) and scales workloads
#           with label `app.kubernetes.io/name=<app>` to 0 replicas.
#   - up:   resumes the HelmRelease (Flux reconciles back to desired replica count).
#   - list: prints the discovered (namespace, app) tuples without acting.

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <cluster-name> [down|up|list]"
  echo "  cluster-name  PostgresCluster name (e.g. postgres-16, postgres-sqq, postgres-vector)"
  echo "  down          Suspend HelmReleases and scale workloads to 0 (default)"
  echo "  up            Resume HelmReleases (Flux restores replicas)"
  echo "  list          Print discovered apps and exit"
  exit 1
fi

CLUSTER="$1"
ACTION="${2:-down}"

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
APPS_DIR="${REPO_ROOT}/kubernetes/apps"

if [ ! -d "$APPS_DIR" ]; then
  echo "error: cannot find ${APPS_DIR}"
  exit 1
fi

# Discover apps referencing the cluster via ExternalSecret keys like:
#   key: <cluster>-pguser-<role>
# Path convention: kubernetes/apps/<ns>/<app>/app/externalsecret.yaml
mapfile -t MATCHES < <(
  grep -RIl --include='externalsecret.yaml' -E "key:[[:space:]]+${CLUSTER}-pguser-" "$APPS_DIR" \
    | sed -E "s|^${APPS_DIR}/([^/]+)/([^/]+)/.*|\1 \2|" \
    | sort -u
)

if [ ${#MATCHES[@]} -eq 0 ]; then
  echo "No apps found referencing cluster '${CLUSTER}'."
  exit 0
fi

echo "Apps using cluster '${CLUSTER}':"
for line in "${MATCHES[@]}"; do
  ns="${line% *}"
  app="${line#* }"
  printf "  - %-20s %s\n" "$ns" "$app"
done

case "$ACTION" in
  list)
    exit 0
    ;;
  down)
    for line in "${MATCHES[@]}"; do
      ns="${line% *}"
      app="${line#* }"
      echo "==> Suspending HelmRelease ${ns}/${app}"
      flux suspend hr "$app" -n "$ns" || echo "   (no HelmRelease ${ns}/${app}, skipping suspend)"
      echo "==> Scaling workloads with app.kubernetes.io/name=${app} in ${ns} to 0"
      kubectl -n "$ns" scale deployment,statefulset \
        --selector="app.kubernetes.io/name=${app}" \
        --replicas=0 || true
    done
    echo "Done. Verify with: kubectl get pods -A -l app.kubernetes.io/name=<app>"
    ;;
  up)
    for line in "${MATCHES[@]}"; do
      ns="${line% *}"
      app="${line#* }"
      echo "==> Resuming HelmRelease ${ns}/${app}"
      flux resume hr "$app" -n "$ns" || echo "   (no HelmRelease ${ns}/${app}, skipping resume)"
    done
    echo "Done. Flux will reconcile workloads back to their desired replica count."
    ;;
  *)
    echo "Invalid action: ${ACTION}"
    echo "Usage: $0 <cluster-name> [down|up|list]"
    exit 1
    ;;
esac
