# Talos

## Upgrade node

```bash
talosctl --nodes 192.168.1.14 upgrade --image=factory.talos.dev/installer/376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba:v1.8.0 --preserve=true
```

## Troubleshooting

### "remote error: tls: internal error" after adding a new node

You need to add the hostname of the new node in the rule for the csr approver : [here](../kubernetes/apps/kube-system/kubelet-csr-approver/app/helm-values.yaml)
