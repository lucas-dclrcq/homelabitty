#!/bin/bash

echo "$1"

name=$(echo "$1" | awk -F'"localDirectoryName": "' '{print $2}' | awk -F'",' '{print $1}')

echo "$name"

wget --post-data "name=$name&path=$name" --header="X-API-KEY: $BETANIN_API_KEY" "$BETANIN_URL/api/torrents"
