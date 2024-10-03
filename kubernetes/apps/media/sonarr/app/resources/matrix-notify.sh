#!/usr/bin/env bash
# shellcheck disable=SC2154

set -euo pipefail

# User defined variables for pushover
MATRIX_URL="${MATRIX_URL:-required}"
MATRIX_TOKEN="${MATRIX_TOKEN:-required}"

if [[ "${sonarr_eventtype:-}" == "Test" ]]; then
    printf -v MATRIX_TITLE \
        "Test Notification"
    printf -v MATRIX_MESSAGE \
        "Howdy this is a test notification from %s" \
            "${sonarr_instancename:-Sonarr}"
fi

if [[ "${sonarr_eventtype:-}" == "Download" ]]; then
    printf -v MATRIX_TITLE \
        "Episode %s" \
            "$( [[ "${sonarr_isupgrade}" == "True" ]] && echo "Upgraded" || echo "Downloaded" )"
    printf -v MATRIX_MESSAGE \
        "<b>%s (S%02dE%02d)</b><small>\n%s</small><small>\n\n<b>Quality:</b> %s</small><small>\n<b>Client:</b> %s</small>" \
            "${sonarr_series_title}" \
            "${sonarr_episodefile_seasonnumber}" \
            "${sonarr_episodefile_episodenumbers}" \
            "${sonarr_episodefile_episodetitles}" \
            "${sonarr_episodefile_quality:-Unknown}" \
            "${sonarr_download_client:-Unknown}"
fi

json_data=$(jo \
    token="${MATRIX_TOKEN}" \
    user="${MATRIX_USER_KEY}" \
    title="${MATRIX_TITLE}" \
    message="${MATRIX_MESSAGE}" \
    url="${MATRIX_URL}" \
    url_title="${MATRIX_URL_TITLE}" \
    priority="${MATRIX_PRIORITY}" \
    html="1"
)

status_code=$(curl \
    --silent \
    --write-out "%{http_code}" \
    --output /dev/null \
    --request POST \
    --header "Content-Type: application/json" \
    --data-binary "${json_data}" \
    "${MATRIX_URL}/1/messages.json" \
)

printf "matrix notification returned with HTTP status code %s and payload: %s\n" \
    "${status_code}" \
    "$(echo "${json_data}" | jq --compact-output)" >&2
