# Volsync

## Links

- [Official Docs](https://volsync.readthedocs.io)

## Backup calendar

| App                   | Schedule   |
|-----------------------|------------|
| actual                | 0 * * * *  |
| changedetection       | 0 * * * *  |
| nextcloud             | 0 * * * *  |
| tandoor               | 0 * * * *  |
| vaultwarden           | 5 * * * *  |
| vikunja               | 5 * * * *  |
| wallabag              | 5 * * * *  |
| influxdb              | 5 * * * *  |
| zigbee2mqtt           | 10 * * * * |
| apprise               | 10 * * * * |
| baibot                | 10 * * * * |
| matrix-bridge-discord | 10 * * * * |
| synapse               | 15 * * * * |
| bazarr                | 15 * * * * |
| betanin               | 15 * * * * |
| calibre-web           | 15 * * * * |
| jellyfin              | 20 * * * * |
| jellyseerr            | 20 * * * * |
| komga                 | 20 * * * * |
| navidrome             | 20 * * * * |
| qbittorrent           | 25 * * * * |
| radarr                | 25 * * * * |
| recyclarr             | 25 * * * * |
| sabnzbd               | 25 * * * * |
| slskd                 | 30 * * * * |
| sonarr                | 30 * * * * |
| metube                | 30 * * * * |
| trilium               | 30 * * * * |

## Troubleshooting

### Locked repo

The 1st thing to try here is deleting the cache PVC.
When the backup starts next time, it should recreate it, and it'll use the permissions that restic is running with.

If that does not work, unlock the repo from within the volsync pod :

```
restic -r s3:http://minio.infrastructure.svc.cluster.local:9000/volsync/<appname> unlock
```
