#!/bin/bash

set -e

bw login --apikey
export BW_SESSION="$(bw unlock --passwordenv BW_PASSWORD --raw)"

echo "Running bitwarden webhook server on port 8087"
bw serve --hostname 0.0.0.0 #--disable-origin-protection
