set quiet
set shell := ['bash', '-eu', '-o', 'pipefail', '-c']

talos_dir := justfile_dir() + '/talos'
secret_file := talos_dir + '/talsecret.sops.yaml'
talosconfig := talos_dir + '/talosconfig'

[private]
default:
    just --list talos

[doc('Render Talos config for a node to stdout')]
render-config node:
    #!/usr/bin/env bash
    set -euo pipefail
    role="$(just talos node-role {{ node }})"
    schematic="$(just talos schematic-id)"
    talosctl machineconfig patch \
        <(just talos template "{{ talos_dir }}/cluster.yaml.j2" -D "schematic=${schematic}") \
        -p @<(just talos template "{{ talos_dir }}/${role}.yaml.j2") \
        -p @<(just talos template "{{ talos_dir }}/nodes/${role}/{{ node }}.yaml.j2")

[doc('Apply Talos config to a node')]
apply-node node *args:
    #!/usr/bin/env bash
    set -euo pipefail
    just talos render-config "{{ node }}" | talosctl --nodes "{{ node }}" apply-config --file /dev/stdin {{ args }}

[confirm('Upgrade Talos on node [y/N]?')]
[doc('Upgrade Talos on a node (image from the schematic)')]
upgrade-node node *args:
    #!/usr/bin/env bash
    set -euo pipefail
    talosctl --nodes "{{ node }}" upgrade --image "$(just talos machine-image)" --timeout=10m {{ args }}
    talosctl --nodes "{{ node }}" health

[confirm('Upgrade Kubernetes on the cluster [y/N]?')]
[doc('Upgrade Kubernetes version on the cluster')]
upgrade-k8s version:
    talosctl --nodes "$(talosctl config info -o yaml | yq -r -e '.endpoints[0]')" upgrade-k8s --to {{ version }}

[doc('Reboot a node')]
reboot-node node:
    talosctl --nodes "{{ node }}" reboot -m powercycle

[confirm('Reset node back to maintenance mode [y/N]?')]
[doc('Reset a node back to maintenance mode')]
reset-node node *args:
    talosctl --nodes "{{ node }}" reset --reboot --system-labels-to-wipe STATE --system-labels-to-wipe EPHEMERAL --graceful=false {{ args }}

[confirm('Shutdown node [y/N]?')]
[doc('Shutdown a node')]
shutdown-node node:
    talosctl --nodes "{{ node }}" shutdown --force

[doc('Download a Talos metal ISO from the Image Factory')]
download-image version:
    #!/usr/bin/env bash
    set -euo pipefail
    schematic="$(just talos schematic-id)"
    curl -fL --remove-on-error --retry 5 --retry-delay 5 --retry-all-errors --progress-bar \
        -o "{{ talos_dir }}/talos-{{ version }}-${schematic:0:8}.iso" \
        "https://factory.talos.dev/image/${schematic}/{{ version }}/metal-amd64.iso"

[doc('Regenerate the talosctl client config from the SOPS secrets')]
generate-talosconfig:
    #!/usr/bin/env bash
    set -euo pipefail
    sops exec-file "{{ secret_file }}" \
        'talosctl gen config hoohoot https://192.168.1.42:6443 --with-secrets {} --output-types talosconfig -o "{{ talosconfig }}" --force'
    talosctl --talosconfig "{{ talosconfig }}" config endpoint 192.168.1.11 192.168.1.12 192.168.1.13
    talosctl --talosconfig "{{ talosconfig }}" config node 192.168.1.11 192.168.1.12 192.168.1.13 192.168.1.14 192.168.1.15 192.168.1.16

[private]
node-role node:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -f "{{ talos_dir }}/nodes/controlplane/{{ node }}.yaml.j2" ]]; then
        echo controlplane
    elif [[ -f "{{ talos_dir }}/nodes/workers/{{ node }}.yaml.j2" ]]; then
        echo workers
    else
        echo "No config found for node {{ node }} under {{ talos_dir }}/nodes/" >&2
        exit 1
    fi

[private]
schematic-id:
    curl -sfX POST --data-binary @<(just talos template "{{ talos_dir }}/schematic.yaml.j2") "https://factory.talos.dev/schematics" | jq -r '.id'

[private]
machine-image:
    just talos template "{{ talos_dir }}/cluster.yaml.j2" -D "schematic=$(just talos schematic-id)" | yq -r -e 'select(document_index == 0) | .machine.install.image'

[private]
template file *args:
    sops exec-file "{{ secret_file }}" "minijinja-cli --strict -f yaml {{ args }} '{{ file }}' {}"
