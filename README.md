<div align="center">


<img src="https://raw.githubusercontent.com/onedr0p/home-ops/main/docs/src/assets/logo.png" align="center" width="144px" height="144px"/>

### My Homelab Gitops repository

_... managed with Flux, Renovate, and GitHub Actions_ 🤖



</div>

<div align="center">


[![Talos](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.hoohoot.org%2Ftalos_version&style=flat-square&label=Talos)](https://github.com/kashalls/kromgo)
&nbsp;&nbsp;
[![k8s](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.hoohoot.org%2Fkubernetes_version&style=flat-square&label=K8S)](https://github.com/kashalls/kromgo)
&nbsp;&nbsp;
[![Age-Days](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.hoohoot.org%2Fcluster_age_days&style=flat-square&label=Age)](https://github.com/kashalls/kromgo)
&nbsp;&nbsp;
[![Uptime-Days](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.hoohoot.org%2Fcluster_uptime_days&style=flat-square&label=Uptime)](https://github.com/kashalls/kromgo)
&nbsp;&nbsp;

</div>
<div align="center">

[![Node-Count](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.hoohoot.org%2Fcluster_node_count&style=flat-square&label=Nodes)](https://github.com/kashalls/kromgo)
&nbsp;&nbsp;
[![Nodes-Memory](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.hoohoot.org%2Fcluster_total_ram&style=flat-square&label=RAM)](https://github.com/kashalls/kromgo)
&nbsp;&nbsp;
[![Pod-Count](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.hoohoot.org%2Fcluster_pod_count&style=flat-square&label=Pods)](https://github.com/kashalls/kromgo)
&nbsp;&nbsp;
[![CPU-Usage](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.hoohoot.org%2Fcluster_cpu_usage&style=flat-square&label=CPU)](https://github.com/kashalls/kromgo)
&nbsp;&nbsp;
[![Memory-Usage](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.hoohoot.org%2Fcluster_memory_usage&style=flat-square&label=Memory)](https://github.com/kashalls/kromgo)
&nbsp;&nbsp;
</div>

## 🚀 Bootstrap

1. Setup talos nodes: `task talos:bootstrap`
2. Push private key: `task flux:github-deploy-key`
3. Setup Flux : `task flux:bootstrap`

## 🔧 Hardware

| Name      | Device                   | CPU           | OS Disk    | Data Disk(s) | RAM  | OS          | Purpose           |
|-----------|--------------------------|---------------|------------|--------------|------|-------------|-------------------|
| Fitz      | Dell Optiplex 3080 Micro | i5-10500T     | 256GB NVMe | 1TB SSD      | 32GB | Talos       | K8S Control Plane |
| Nighteyes | Dell Optiplex 3080 Micro | i5-10500T     | 256GB NVMe | 1TB SSD      | 32GB | Talos       | K8S Control Plane |
| Chade     | Dell Optiplex 3080 Micro | i5-10500T     | 500GB NVMe | 1TB SSD      | 32GB | Talos       | K8S Control Plane |
| Fool      | Dell Optiplex 3090 Micro | i5-10500T     | 500GB NVMe | 1TB SSD      | 32GB | Talos       | K8S Worker        |
| Burrich   | Dell Optiplex 3090 Micro | i5-10500T     | 500GB NVMe | 1TB SSD      | 32GB | Talos       | K8S Worker        |
| Bee       | Dell Optiplex 3090 Micro | i5-10500T     | 500GB NVMe | 1TB SSD      | 32GB | Talos       | K8S Worker        |
| NAS       | Synology DS1520+         | Celeron J4125 | N/A        | 5*4TB        | 8GB  | Synology OS | NAS (NFS/Backup)  |
| MOX       | Turris MOX               |               | 32GB       | N/A          | 1GB  | Turris OS   | Router            |

## ☁️ Cloud Services

| Service                                   | Use                                                            | Cost                 |
|-------------------------------------------|----------------------------------------------------------------|----------------------|
| [Pushover](https://pushover.net)          | Alerts & Notifications                                         | 5$ one-time purchase |
| [Cloudflare](https://www.cloudflare.com/) | Domain                                                         | Free                 |
| [GitHub](https://github.com/)             | Hosting this repository and continuous integration/deployments | Free                 |

## 🖥️ Tech Stack

|                                                                                                                                                                   | Name                                      | Description                                                                                            |
|-------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------|--------------------------------------------------------------------------------------------------------|
| <img width="32" src="https://github.com/cncf/artwork/raw/main/projects/kubernetes/icon/color/kubernetes-icon-color.svg">                                          | [Kubernetes](https://kubernetes.io/)      | An open-source system for automating deployment, scaling, and management of containerized applications |
| <img width="32" src="https://github.com/cncf/artwork/raw/main/projects/flux/icon/color/flux-icon-color.svg">                                                      | [FluxCD](https://fluxcd.io/)              | GitOps tool for deploying applications to Kubernetes                                                   |
| <img width="32" src="https://www.talos.dev/images/logo.svg">                                                                                                      | [Talos Linux](https://www.talos.dev/)     | Talos Linux is Linux designed for Kubernetes                                                           |
| <img width="62" src="https://github.com/cncf/artwork/raw/main/projects/cilium/icon/color/cilium_icon-color.svg">                                                  | [Cilium](https://cilium.io/)              | GitOps tool for deploying applications to Kubernetes                                                   |
| <img width="32" src="https://github.com/cncf/artwork/raw/main/projects/containerd/icon/color/containerd-icon-color.svg">                                          | [containerd](https://containerd.io/)      | Container runtime integrated with Talos Linux                                                          |
| <img width="32" src="https://github.com/cncf/artwork/raw/main/projects/coredns/icon/color/coredns-icon-color.svg">                                                | [CoreDNS](https://coredns.io/)            | A DNS server that operates via chained plugins                                                         |
| <img width="32" src="https://github.com/cncf/artwork/raw/main/projects/prometheus/icon/color/prometheus-icon-color.svg">                                          | [Prometheus](https://prometheus.io)       | Monitoring system and time series database                                                             |
| <img width="32" src="https://github.com/cncf/artwork/raw/main/projects/helm/icon/color/helm-icon-color.svg">                                                      | [Helm](https://helm.sh)                   | The Kubernetes package manager                                                                         |
| <img width="32" src="https://raw.githubusercontent.com/cncf/artwork/3f0fb8808bff60f0899233e5e49aa1af055bb6ab/archived/openebs/icon/color/openebs-icon-color.svg"> | [OpenEBS](https://openebs.io)             | Container-attached storage                                                                             |
| <img width="32" src="https://github.com/cncf/artwork/raw/main/projects/opentelemetry/icon/color/opentelemetry-icon-color.svg">                                    | [OpenTelemetry](https://opentelemetry.io) | Making robust, portable telemetry a built in feature of cloud-native software.                         |
| <img width="32" src="https://github.com/cncf/artwork/raw/main/projects/cert-manager/icon/color/cert-manager-icon-color.svg">                                      | [Cert Manager](https://cert-manager.io/)  | X.509 certificate management for Kubernetes                                                            |
| <img width="32" src="https://grafana.com/static/img/menu/grafana2.svg">                                                                                           | [Grafana](https://grafana.com)            | Analytics & monitoring solution for every database.                                                    |
| <img width="32" src="https://github.com/grafana/loki/blob/main/docs/sources/logo.png?raw=true">                                                                   | [Loki](https://grafana.com/oss/loki/)     | Horizontally-scalable, highly-available, multi-tenant log aggregation system                           |
