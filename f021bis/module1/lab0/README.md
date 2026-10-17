# Lab 0 — tools, once, before slot 1

Everything the module needs that the console image does not ship, into
`~/bin` (already on your `PATH`), plus the two kind node images.

```sh
cd ~/trainings_exercises/f021bis/module1
make -C lab0 tools      # linkerd (the "from" version), step, velero
make -C lab0 pull       # kindest/node for K8S_FROM and K8S_TO, ~1 GB each
make -C lab0 check
```

| File | What it is |
| --- | --- |
| [`Makefile`](Makefile) | `tools`, `linkerd-to` (lab 2 step 4), `pull`, `charts`, `check`; `pull-consoles` for the trainer |
| [`etcdctl.sh`](etcdctl.sh) | `etcdctl`, `etcdutl`, `etcdlogs` as shell functions, through the node's container runtime |

Versions come from [`../versions.env`](../versions.env).

## The linkerd CLI

Two versions are installed side by side, `~/bin/linkerd-edge-26.8.4` and
`~/bin/linkerd-edge-26.9.3`, and `~/bin/linkerd` is a symlink to one of them.
Lab 2 installs the old control plane with the old CLI, upgrades the control
plane, then switches the CLI last (`make -C lab0 linkerd-to`): clients are
upgraded after servers.

## If helm.linkerd.io is slow

It sometimes times out. `make -C lab0 charts` downloads every Linkerd chart
of the module into `~/charts`; then replace `linkerd-edge/<chart> --version
<v>` by `~/charts/<chart>-<v>.tgz` in the step files, or pass
`CHARTS=~/charts` to the catch-up targets of [`../Makefile`](../Makefile).

## Trainer

From `module1/` on the trainer's machine, with the dev cluster's kubeconfig
(`../shared-cluster/`, `make kubeconfig`):

```sh
make -C lab0 pull-consoles     # both node images in every console, in parallel
```
