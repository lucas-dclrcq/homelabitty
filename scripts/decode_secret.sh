kubectl get secret "$1" -o jsonpath='{.data}' | jq 'map_values(@base64d)'
