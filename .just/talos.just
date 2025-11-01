set quiet
set shell := ['bash', '-eu', '-o', 'pipefail', '-c']

#scripts_dir := justfile_dir() + '/scripts'
#talos_dir := justfile_dir() + '/talos'
#temp_dir := `mktemp -d`
#
#controller := `talosctl config info -o yaml | yq -e '.endpoints[0]'`

kubernetes_dir := justfile_dir() + '/kubernetes'

talhelper_cluster_dir := justfile_dir() + '/talos/clusterconfig'
talhelper_config_file := justfile_dir() + '/talos/talconfig.yaml'
talhelper_secret_file := justfile_dir() + '/talos/talsecret.sops.yaml'
talosconfig := talhelper_cluster_dir + '/talosconfig'

[private]
default:
    just --list talos

[doc('Generate Talos configuration')]
generate-config:
    #!/usr/bin/env bash
    set -euo pipefail

    # Check preconditions
    test -f {{talhelper_config_file}} || { echo "Config file not found: {{talhelper_config_file}}"; exit 1; }
    test -f {{talhelper_secret_file}} || { echo "Secret file not found: {{talhelper_secret_file}}"; exit 1; }
    command -v talhelper >/dev/null || { echo "talhelper not found in PATH"; exit 1; }

    # Run the command
    talhelper genconfig \
        --config-file {{talhelper_config_file}} \
        --secret-file {{talhelper_secret_file}} \
        --out-dir {{talhelper_cluster_dir}}

[doc('Apply Talos config to a node [NODE=required]')]
apply-node node:
    #!/usr/bin/env bash
    set -euo pipefail
    export TALOSCONFIG={{talosconfig}}

    # Check preconditions
    command -v talosctl >/dev/null || { echo "talosctl not found in PATH"; exit 1; }
    test -f "${TALOSCONFIG}" || { echo "TALOSCONFIG file not found: ${TALOSCONFIG}"; exit 1; }
    talosctl --nodes {{node}} get machineconfig >/dev/null || { echo "Cannot connect to node {{node}}"; exit 1; }

    # Find the config file for this node
    file=$(ls {{talhelper_cluster_dir}}/hoohoot-{{node}}.yaml)

    # Apply machine config
    talosctl apply-config \
        --nodes {{node}} \
        --file "${file}" \
        --mode auto

    # Check node health
    talosctl --nodes {{node}} health

[doc('Upgrade Talos on a single node [NODE=required]')]
upgrade-node node:
    #!/usr/bin/env bash
    set -euo pipefail
    export TALOSCONFIG={{talosconfig}}

    # Check preconditions
    command -v talosctl >/dev/null || { echo "talosctl not found in PATH"; exit 1; }
    test -f "${TALOSCONFIG}" || { echo "TALOSCONFIG file not found: ${TALOSCONFIG}"; exit 1; }
    talosctl --nodes {{node}} get machineconfig >/dev/null || { echo "Cannot connect to node {{node}}"; exit 1; }

    # Find the config file for this node and extract Talos image
    file=$(ls {{talhelper_cluster_dir}}/hoohoot-{{node}}.yaml)
    talos_image=$(yq '.machine.install.image' < "${file}")

    # Upgrade the node
    talosctl --nodes {{node}} upgrade --image="${talos_image}" --timeout=10m

    # Check node health
    talosctl --nodes {{node}} health

#[doc('Apply Node')]
#apply-node node *args:
#    just talos render-config "{{node}}" | talosctl -n "{{node}}" apply-config -f /dev/stdin {{args}}
#
#[doc('Download Image')]
#download-image version schematic:
#    gum spin -s line --title "Downloading Talos {{version}} ..." -- \
#    curl -sfL --remove-on-error --retry 5 --retry-delay 5 --retry-all-errors \
#        -o "{{talos_dir}}/talos-{{version}}-{{replace_regex(schematic, '^(.{8}).*', '$1')}}.iso" \
#        "https://factory.talos.dev/image/{{schematic}}/{{version}}/metal-amd64.iso"
#    just log info "Downloaded Talos" version "{{version}}" schematic "{{schematic}}"
#
#[doc('Generate Kubeconfig')]
#generate-kubeconfig:
#    talosctl kubeconfig -n "{{controller}}" -f --force-context-name main {{justfile_dir()}}
#
#[doc('Generate Schematic Id')]
#generate-schematic-id:
#    curl -sX POST --data-binary "@{{talos_dir}}/schematic.yaml" \
#        "https://factory.talos.dev/schematics" | jq -r '.id'
#
#[doc('Reboot Node')]
#reboot-node node:
#    talosctl -n {{node}} reboot -m powercycle
#
#[doc('Render Config')]
#render-config node:
#    minijinja-cli -D "machinetype=$(just talos machine-type {{node}})" \
#        "{{talos_dir}}/machineconfig.yaml.j2" | op inject >"{{temp_dir}}/base.yaml"
#    minijinja-cli -D "machinetype=$(just talos machine-type {{node}})" \
#        "{{talos_dir}}/nodes/{{node}}.yaml.j2" | op inject >"{{temp_dir}}/patch.yaml"
#    talosctl machineconfig patch "{{temp_dir}}/base.yaml" -p "{{temp_dir}}/patch.yaml"
#
#[doc('Reset Node')]
#[confirm]
#reset-node node:
#    talosctl -n "{{node}}" reset --graceful=false
#
#[doc('Shutdown Node')]
#shutdown-node node:
#    talosctl -n "{{node}}" shutdown --force
#
#[doc('Upgrade Kubernetes')]
#upgrade-k8s version:
#    talosctl -n "{{controller}}" upgrade-k8s --to {{version}}
#
#[doc('Upgrade Node')]
#upgrade-node node:
#    talosctl -n "{{node}}" upgrade -i "$(just talos machine-image)" -m powercycle --timeout=10m
#
#[private]
#machine-type node:
#    minijinja-cli "{{talos_dir}}/nodes/{{node}}.yaml.j2" | yq -e '.machine.type // ""'
#
#[private]
#machine-image:
#    minijinja-cli "{{talos_dir}}/machineconfig.yaml.j2" | yq -e '.machine.install.image // ""'
