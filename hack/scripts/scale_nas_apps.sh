#!/usr/bin/env bash

if [ $# -eq 0 ]; then
  echo "Usage: $0 [up|down]"
  echo "  up   - Scale nas apps to 1 replicas"
  echo "  down - Scale nas apps to replicas"
  exit 1
fi

if [ "$1" = "up" ]; then
  replicas=1
elif [ "$1" = "down" ]; then
  replicas=0
else
  echo "Invalid parameter: $1"
  echo "Usage: $0 [up|down]"
  exit 1
fi

echo "Scaling NAS applications with replicas=$replicas"

kubectl scale deployment -n default sftpgo  --replicas $replicas
kubectl scale deployment -n default nextcloud  --replicas $replicas
kubectl scale deployment -n default immich-machine-learning  --replicas $replicas
kubectl scale deployment -n default immich-server  --replicas $replicas
kubectl scale deployment -n downloads bazarr  --replicas $replicas
kubectl scale deployment -n downloads lidarr  --replicas $replicas
kubectl scale deployment -n downloads qbittorrent  --replicas $replicas
kubectl scale deployment -n downloads radarr  --replicas $replicas
kubectl scale deployment -n downloads readarr  --replicas $replicas
kubectl scale deployment -n downloads sabnzbd  --replicas $replicas
kubectl scale deployment -n downloads sonarr  --replicas $replicas
kubectl scale deployment -n downloads slskd  --replicas $replicas
kubectl scale deployment -n downloads pinchflat  --replicas $replicas
kubectl scale deployment -n home frigate  --replicas $replicas
kubectl scale deployment -n infrastructure minio --replicas $replicas
kubectl scale deployment -n media audiobookshelf --replicas $replicas
kubectl scale deployment -n media jellyfin --replicas $replicas
kubectl scale deployment -n media komga --replicas $replicas
kubectl scale deployment -n media navidrome --replicas $replicas
kubectl scale deployment -n volsync-system volsync --replicas $replicas

echo "NAS applications scaled $1"
