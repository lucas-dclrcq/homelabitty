#!/bin/bash

set -e

./node_modules/@bitwarden/cli/build/bw.js login --apikey
export BW_SESSION="$(./node_modules/@bitwarden/cli/build/bw.js unlock --passwordenv BW_PASSWORD --raw)"

echo "Running bitwarden webhook server on port 8087"
./node_modules/@bitwarden/cli/build/bw.js serve --hostname 0.0.0.0 #--disable-origin-protection
