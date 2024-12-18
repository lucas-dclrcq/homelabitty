#!/bin/bash

VAULT_UNSEAL_KEY=$(jq -r ".unseal_keys_hex[]" $1)

kubens vault
kubectl exec -ti vault-0 -- vault operator unseal "$VAULT_UNSEAL_KEY"
kubectl exec -ti vault-1 -- vault operator unseal "$VAULT_UNSEAL_KEY"
kubectl exec -ti vault-2 -- vault operator unseal "$VAULT_UNSEAL_KEY"
