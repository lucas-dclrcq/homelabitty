#!/bin/bash

read -t5 -r line
path=$(echo "$line" | awk -F'"localDirectoryName":"' '{print $2}' | awk -F'"' '{print $1}' | awk '{printf "%s", $0}')

wget --quiet \
    --header="X-API-Key: $BETANIN_API_KEY" \
    --header="User-Agent: slskd-to-betanin" \
    --post-data="both=${path}" \
    "$BETANIN_URL/api/torrents" -O -
