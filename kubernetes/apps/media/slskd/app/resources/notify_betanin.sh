#!/usr/bin/env bash
# shellcheck disable=SC2154

set -euo pipefail

if [ -n "$BETANIN_API_KEY" ] || [ -n "$BETANIN_URL" ]; then
    echo "BETANIN_API_KEY and BETANIN_URL variables are mandatory"
    exit 1;
fi

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
