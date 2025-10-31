set quiet
set shell := ['bash', '-eu', '-o', 'pipefail', '-c']

ansible_dir := justfile_dir() + '/ansible'

[private]
default:
    just --list ansible

[doc('Run playbook')]
apply:
    ansible-playbook {{ansible_dir}}/playbook.yaml -i {{ansible_dir}}/inventory
