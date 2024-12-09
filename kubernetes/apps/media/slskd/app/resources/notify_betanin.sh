#!/usr/bin/env bash
# shellcheck disable=SC2154

set -euo pipefail

BETANIN_API_KEY="${BETANIN_API_KEY:-required}"
BETANIN_URL="${BETANIN_URL:-required}"

DIRECTORY_PATH=$(echo "$1" | grep -oP '"localDirectoryName":\s*"\K[^"]+')

status_code=$(curl \
    --silent \
    --write-out "%{http_code}" \
    --output /dev/null \
    --request POST \
    --header "Content-Type: application/x-www-form-urlencoded" \
    --header "X-API-Key: ${BETANIN_API_KEY}" \
    --data-urlencode "path=${DIRECTORY_PATH}" \
    "$BETANIN_URL/api/torrents"
)

echo -e "Betanin notification returned with HTTP status code ${status_code}\n"
