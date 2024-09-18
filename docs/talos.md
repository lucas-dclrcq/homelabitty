# Talos

## Troubleshooting

### "remote error: tls: internal error" after adding a new node

You need to add the hostname of the new node in the rule for the csr approver : [here](../kubernetes/apps/kube-system/kubelet-csr-approver/app/helm-values.yaml)
