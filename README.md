<div align="center">


<img src="./docs/assets/brand_icon.svg" align="center"/>

### My Homelab Gitops repository

_... managed with Flux, Renovate, and GitHub Actions_ 🤖



</div>

<div align="center">


[![Talos](https://kromgo.hoohoot.org/badges/talos_version)](https://talos.dev)
&nbsp;&nbsp;
[![Kubernetes](https://kromgo.hoohoot.org/badges/kubernetes_version)](https://kubernetes.io)
&nbsp;&nbsp;

</div>
<div align="center">

![Alert Manager Heartbeat](https://healthchecks.io/b/2/54405929-0cab-4e44-9404-07ac4f54da8a.svg)

[![Node-Count](https://kromgo.hoohoot.org/badges/cluster_node_count)](https://github.com/home-operations/kromgo)
&nbsp;&nbsp;
[![Nodes-Memory](https://kromgo.hoohoot.org/badges/cluster_total_ram)](https://github.com/home-operations/kromgo)
&nbsp;&nbsp;
[![Pod-Count](https://kromgo.hoohoot.org/badges/cluster_pod_count)](https://github.com/home-operations/kromgo)
&nbsp;&nbsp;
[![CPU-Usage](https://kromgo.hoohoot.org/badges/cluster_cpu_usage)](https://github.com/home-operations/kromgo)
&nbsp;&nbsp;
[![Memory-Usage](https://kromgo.hoohoot.org/badges/cluster_memory_usage)](https://github.com/home-operations/kromgo)
&nbsp;&nbsp;
[![Power-Usage](https://kromgo.hoohoot.org/badges/cluster_power_usage)](https://github.com/home-operations/kromgo)
&nbsp;&nbsp;
[![Age-Days](https://kromgo.hoohoot.org/badges/cluster_age_days)](https://github.com/home-operations/kromgo)
&nbsp;&nbsp;
[![Uptime-Days](https://kromgo.hoohoot.org/badges/cluster_uptime_days)](https://github.com/home-operations/kromgo)
&nbsp;&nbsp;
</div>

## 🚀 Bootstrap

1. Setup talos nodes: `task talos:bootstrap`
2. Push private key: `task flux:github-deploy-key`
3. Setup Flux : `task flux:bootstrap`

## 🛠️ Talos and Kubernetes Maintenance

### ⚙️ Updating Talos node configuration

> [!IMPORTANT]
> Ensure you have updated `talconfig.yaml` and any patches with your updated configuration. In some cases you **not only
need to apply the configuration but also upgrade talos** to apply new configuration.

```sh
# (Re)generate the Talos config
task talos:generate-config
# Apply the config to the node
task talos:apply-node HOSTNAME=? MODE=?
# e.g. task talos:apply-config HOSTNAME=k8s-0 MODE=auto
```

### ⬆️ Updating Talos and Kubernetes versions

> [!IMPORTANT]
> Ensure the `talosVersion` and `kubernetesVersion` in `talhelper.yaml` are up-to-date with the version you wish to
> upgrade to.

```sh
# Upgrade node to a newer Talos version
task talos:upgrade-node NODE=?
# e.g. task talos:upgrade HOSTNAME=k8s-0
```

```sh
# Upgrade cluster to a newer Kubernetes version
task talos:upgrade-k8s
# e.g. task talos:upgrade-k8s
```

## 🔧 Hardware

| Name      | Device                   | CPU               | OS Disk    | Data Disk(s)                      | RAM  | OS            | Purpose           |
|-----------|--------------------------|-------------------|------------|-----------------------------------|------|---------------|-------------------|
| Fitz      | Dell Optiplex 3080 Micro | i5-10500T         | 500GB NVMe | 1TB SSD                           | 32GB | Talos         | K8S Control Plane |
| Nighteyes | Dell Optiplex 3080 Micro | i5-10500T         | 500GB NVMe | 1TB SSD                           | 32GB | Talos         | K8S Control Plane |
| Chade     | Dell Optiplex 3080 Micro | i5-10500T         | 500GB NVMe | 1TB SSD                           | 32GB | Talos         | K8S Control Plane |
| Fool      | Dell Optiplex 3090 Micro | i5-10500T         | 500GB NVMe | 1TB SSD                           | 64GB | Talos         | K8S Worker        |
| Burrich   | Dell Optiplex 3090 Micro | i5-10500T         | 500GB NVMe | 1TB SSD                           | 64GB | Talos         | K8S Worker        |
| Bee       | Dell Optiplex 3090 Micro | i5-10500T         | 500GB NVMe | 1TB SSD                           | 64GB | Talos         | K8S Worker        |
| Verity    | DIY NAS                  | Ryzen 5 Pro 5650G | 1TB NVMe   | 4*18TB + 2\*22TB (mirrored vdevs) | 32GB | TrueNAS SCALE | NAS (NFS/Backup)  |
| Shrewd    | Synology DS1520+         | -                 | -          | 5*4TB (RAID 5)                    | -    | -             | NAS (NFS/Backup)  |
| Chivalry  | UniFi Dream Pro Max      | -                 | -          | -                                 | -    | -             | Router            |
| Molly     | UniFi Switch Pro Max 24  | -                 | -          | -                                 | -    | -             | 2.5Gb Switch      |

## ☁️ Cloud Services

| Service                                   | Use                                                            | Cost                 |
|-------------------------------------------|----------------------------------------------------------------|----------------------|
| [Pushover](https://pushover.net)          | Alerts & Notifications                                         | 5$ one-time purchase |
| [Cloudflare](https://www.cloudflare.com/) | Domain                                                         | Free                 |
| [GitHub](https://github.com/)             | Hosting this repository and continuous integration/deployments | Free                 |

## 🖥️ Tech Stack

|                                                                                                                                                                   | Name                                                          | Description                                                                                            |
|:------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------|--------------------------------------------------------------------------------------------------------|
| <img width="32" src="https://github.com/cncf/artwork/raw/main/projects/kubernetes/icon/color/kubernetes-icon-color.svg">                                          | [Kubernetes](https://kubernetes.io/)                          | An open-source system for automating deployment, scaling, and management of containerized applications |
| <img width="32" src="https://github.com/cncf/artwork/raw/main/projects/flux/icon/color/flux-icon-color.svg">                                                      | [FluxCD](https://fluxcd.io/)                                  | GitOps tool for deploying applications to Kubernetes                                                   |
| <img width="32" src="https://www.talos.dev/images/logo.svg">                                                                                                      | [Talos Linux](https://www.talos.dev/)                         | Talos Linux is Linux designed for Kubernetes                                                           |
| <img width="62" src="https://github.com/cncf/artwork/raw/main/projects/cilium/icon/color/cilium_icon-color.svg">                                                  | [Cilium](https://cilium.io/)                                  | GitOps tool for deploying applications to Kubernetes                                                   |
| <img width="32" src="https://github.com/cncf/artwork/raw/main/projects/containerd/icon/color/containerd-icon-color.svg">                                          | [containerd](https://containerd.io/)                          | Container runtime integrated with Talos Linux                                                          |
| <img width="32" src="https://github.com/cncf/artwork/raw/main/projects/coredns/icon/color/coredns-icon-color.svg">                                                | [CoreDNS](https://coredns.io/)                                | A DNS server that operates via chained plugins                                                         |
| <img width="32" src="https://github.com/cncf/artwork/raw/main/projects/prometheus/icon/color/prometheus-icon-color.svg">                                          | [Prometheus](https://prometheus.io)                           | Monitoring system and time series database                                                             |
| <img width="32" src="https://github.com/cncf/artwork/raw/main/projects/helm/icon/color/helm-icon-color.svg">                                                      | [Helm](https://helm.sh)                                       | The Kubernetes package manager                                                                         |
| <img width="32" src="https://raw.githubusercontent.com/cncf/artwork/3f0fb8808bff60f0899233e5e49aa1af055bb6ab/archived/openebs/icon/color/openebs-icon-color.svg"> | [OpenEBS](https://openebs.io)                                 | Container-attached storage                                                                             |
| <img width="32" src="./docs/assets/rook.png">                                                                                                                     | [Rook Ceph](https://rook.io/docs/rook/v1.9/ceph-storage.html) | Highly scalable distributed storage solution for block storage, object storage, and shared filesystems |
| <img width="32" src="https://github.com/cncf/artwork/raw/main/projects/opentelemetry/icon/color/opentelemetry-icon-color.svg">                                    | [OpenTelemetry](https://opentelemetry.io)                     | Making robust, portable telemetry a built in feature of cloud-native software.                         |
| <img width="32" src="https://github.com/cncf/artwork/raw/main/projects/cert-manager/icon/color/cert-manager-icon-color.svg">                                      | [Cert Manager](https://cert-manager.io/)                      | X.509 certificate management for Kubernetes                                                            |
| <img width="32" src="https://grafana.com/static/img/menu/grafana2.svg">                                                                                           | [Grafana](https://grafana.com)                                | Analytics & monitoring solution for every database.                                                    |
| <img width="32" src="https://github.com/grafana/loki/blob/main/docs/sources/logo.png?raw=true">                                                                   | [Loki](https://grafana.com/oss/loki/)                         | Horizontally-scalable, highly-available, multi-tenant log aggregation system                           |
| <img width="32" src="./docs/assets/alloy.png">                                                                                                                    | [Alloy](https://grafana.com/docs/alloy/latest/)               | Open source distribution of OpenTelemetry Collector that supports metrics, logs, traces, and profiles. |
