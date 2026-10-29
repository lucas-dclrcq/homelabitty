# Talos

Declarative [Talos Linux](https://www.talos.dev) machine configuration for the cluster, built from
composable multi-document patches rendered with [minijinja](https://github.com/mitsuhiko/minijinja)
(layout borrowed from [onedr0p/home-ops](https://github.com/onedr0p/home-ops/tree/main/talos)).
Nothing in this directory is applied automatically; configs are rendered on demand and pushed to
nodes with `talosctl`.

## Layout

| Path                          | Purpose                                                     |
| ----------------------------- | ----------------------------------------------------------- |
| `cluster.yaml.j2`             | Documents applied to every node                             |
| `controlplane.yaml.j2`        | Control-plane-only documents, including `machine.type`      |
| `workers.yaml.j2`             | Worker-only documents                                       |
| `nodes/<role>/<node>.yaml.j2` | Per-node documents (hostname, bond member MAC)              |
| `schematic.yaml.j2`           | Shared [Image Factory](https://factory.talos.dev) schematic |
| `talsecret.sops.yaml`         | SOPS-encrypted `talosctl gen secrets` bundle                |

## Rendering

`just talos render-config <node>` builds the final machine config in three layers:

```
talosctl machineconfig patch <(cluster.yaml.j2) \
    -p @<(controlplane.yaml.j2 | workers.yaml.j2) \
    -p @<(nodes/<role>/<node>.yaml.j2)
```

Each layer passes through `minijinja-cli` (strict Jinja templating; the schematic ID arrives as a
`-D` define) with the SOPS-decrypted `talsecret.sops.yaml` as template context (`sops exec-file`),
before `talosctl` merges them. Later patches strategically merge into earlier ones: documents with
the same kind/name are deep-merged, new documents are appended.

Two conventions keep the layers honest:

- **Directory placement is the single source of truth for a node's role.** The role patch is chosen
  by which `nodes/<role>/` directory contains the node file, and `machine.type` is set by the role
  patch, not the node file.
- **Secrets never live in the templates.** All sensitive values are Jinja references
  (`{{ certs.os.crt }}`, ...) into the encrypted secrets bundle, resolved at render time.

## Schematics

The schematic defines the Image Factory build (system extensions, kernel args). It is POSTed to the
factory to get a content-addressed ID, which is templated into the `UnattendedInstallConfig` installer image and used by
`download-image` and `upgrade-node`. All nodes share the same schematic.

## Gotchas

- `machine.ca` and `cluster.ca` merge as a cert+key **unit**: a patch supplying only `key` blanks
  `crt`. This is why `controlplane.yaml.j2` repeats the `crt` references alongside the keys.
- No `KubeAdmissionControlConfig` document is emitted on purpose: PSA must stay disabled
  cluster-wide so Rook can run.
- Day-to-day Talos/Kubernetes **version upgrades are driven in-cluster by tuppr**
  (`kubernetes/apps/system-upgrade/tuppr/`); the versions pinned here must follow its bumps
  (renovate groups them).

## Common tasks

```sh
just talos render-config <node>        # render a node's full machine config to stdout
just talos apply-node <node> [args]    # render and apply (talosctl apply-config)
just talos upgrade-node <node>         # upgrade Talos using the schematic image
just talos upgrade-k8s <version>       # upgrade Kubernetes across the cluster
just talos download-image <version>    # fetch a metal ISO from the Image Factory
just talos generate-talosconfig        # regenerate talos/talosconfig from the SOPS secrets
```

Verify a refactor of these templates by diffing rendered output before and after, then confirming
`just talos apply-node <node> --dry-run` reports no unexpected changes on every node.
