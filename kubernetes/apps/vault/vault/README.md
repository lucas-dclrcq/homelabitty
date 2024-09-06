# Vault

## Runbooks

### Unseal

```bash
./scripts/unseal cluster-keys.json
```

### Restore from backup

1. Bring Vault cluster back online
2. Copy last snap file to PVC and restore : `vault operator raft snapshot restore -force backup.snap`
3. Unseal : `./scripts/unseal cluster-keys.json`

Source : https://developer.hashicorp.com/vault/tutorials/standard-procedures/sop-restore



