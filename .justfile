#!/usr/bin/env -S just --justfile

set quiet
set shell := ['bash', '-euo', 'pipefail', '-c']

#[doc('Bootstrap Recipes')]
#mod bootstrap '.just/bootstrap.just'

[doc('Kubernetes Recipes')]
mod kube '.just/kube.just'

[doc('Sync Recipes')]
mod sync '.just/sync.just'

[doc('Ansible playbooks')]
mod ansible 'ansible/mod.just'

[doc('Talos Recipes')]
mod talos 'talos/mod.just'

[doc('Rook Ceph Recipes')]
mod rook '.just/rook.just'

[private]
default:
    just --list

[positional-arguments]
[private]
log lvl msg *args:
    gum log -t rfc3339 -s -l "{{ lvl }}" "{{ msg }}" {{ args }}
