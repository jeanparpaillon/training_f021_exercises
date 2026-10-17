# Module 1 — Kubernetes administration in production

Exercises for module 1 of **F021bis — Kubernetes in production**. The slides are
in `../../../trainings/f021bis/slides/module1.md`; every lab here names the
slides it belongs to.

| | Lab | Slot |
| --- | --- | --- |
| [lab1/](lab1/) | break and repair an HA control plane: etcd quorum, partition, lost member | 1 |
| [lab2/](lab2/) | add a component and upgrade it: API versions, CRDs, Linkerd with Helm | 2 |
| [lab3/](lab3/) | upgrade Kubernetes in place, node by node, under load, with zero downtime | 3 |
| [lab4/](lab4/) | etcd snapshot and restore, then Velero: backup, restore, migration | 4 |
| [lab5/](lab5/) | troubleshooting: application through the mesh, then network, storage, nodes | 5 |
| [lab0/](lab0/) | tools and images, once, before slot 1 | — |

Module 1 is **cluster administration**: unlike F021, where everyone had a
namespace on a shared cluster, here you own whole clusters — you create them,
break them, upgrade them, restore them. Their control planes are yours to
kill.

## Where the labs run

In your **web console** on the f021bis dev cluster (see
[`../shared-cluster/README.md`](../shared-cluster/README.md)): each console
runs its own Docker daemon, so `kind create cluster` works from it, and your
clusters are yours alone. The shared cluster itself (context
`training-f021bis`) is not used by the labs.

You work **in pairs, one cluster per pair at a time**: the server has 4 CPUs
and 15 GiB for the whole room (see [Size](#size-trainer)). One of the pair
drives, in their console; swap at each lab.

Two clusters over the module, both kind:

| Cluster | Nodes | Kubernetes | Used by | Lifetime |
| --- | --- | --- | --- | --- |
| `ha` | 3 control planes (stacked etcd) + kind's Envoy load balancer | `K8S_TO` | lab 1 | deleted at the end of lab 1 |
| `prod` | 1 control plane (untainted) + 1 worker | `K8S_FROM`, upgraded to `K8S_TO` in lab 3 | labs 2 → 5 | kept until the end of the module |

`prod` carries the whole module: Linkerd and Bookinfo go on it in lab 2, the
upgrade of lab 3 is measured under load, lab 4 backs it up and restores it,
lab 5 breaks it. **Do not delete it between labs.** If it is lost or beyond
repair, rebuild it at the end of any lab, from `module1/`:

```sh
make catch-up-lab2      # or catch-up-lab3, catch-up-lab4 — ~5 min
```

**`prod` lab compromise:** its control plane is untainted, so workloads
run on both nodes. A drained node then has somewhere to send its pods, which
is what lab 3 needs, at the cost of one less node. In production, keep
workloads off the control plane.

## Conventions

- **Run everything from `module1/`**, after `source versions.env`. Paths in
  the step files are relative to it.
- **Steps are directories**, `labN/stepM-<name>/`, each with a `README.md` —
  the step file: commands, what to look for, questions to answer before
  moving on. Bookinfo's states are kustomize overlays, as in F021:
  `kubectl apply -k lab3/step2-ready` brings Bookinfo to the end of that
  step. `apply -k` never deletes: when a step removes something, its file
  says what to delete by hand.
- **Hypothesis first.** Before every failure you inject, write down what you
  expect: which commands still work, which fail, for how long. A wrong guess
  is the most useful thing a lab can give you.
- **Two levels of access.** `kubectl` goes through the API server. When the
  API server is down, you go one level down with `docker exec <node> …`:
  `crictl` for containers, `journalctl -u kubelet`, the static pod manifests
  in `/etc/kubernetes/manifests/`. Each lab says which level you need.
- **Contexts.** kind switches the context to `kind-<cluster>` on creation.
  Check `kubectl config current-context` before anything destructive.
- **Users are outside the cluster.** Bookinfo is reached on
  `127.0.0.1:30080` from the console, and the load generator (`lab3/load`)
  runs there too, not as a pod: a drain would evict it.
- **Clean up what you break** before the end of the slot: the next lab starts
  from a healthy `prod`.

## Prerequisites

Everything below is either in the console image or installed into `~/bin`
(on the `PATH`) by [`lab0/`](lab0/):

| Tool | Used in | Where |
| --- | --- | --- |
| `kubectl`, `kind`, `helm` (v4), `docker` | all | console image |
| `etcdctl` / `etcdutl` | labs 1, 4 | the etcd container's, via [`lab0/etcdctl.sh`](lab0/etcdctl.sh) |
| `linkerd` CLI | labs 2, 3, 5 | `~/bin`, two versions side by side |
| `step` (smallstep) | lab 2 | `~/bin`, for the Linkerd trust anchor and issuer |
| `velero` CLI | lab 4 | `~/bin` |
| `k6` | labs 3, 5 | a container of your console's Docker (`lab3/load`) |

The exercises repo is cloned in the console home:

```sh
git clone https://github.com/jeanparpaillon/trainings_exercises.git
cd trainings_exercises/f021bis/module1
make -C lab0 tools pull
source versions.env
```

### Versions

All in [`versions.env`](versions.env), sourced by the step files and
included by the Makefiles.

| Variable | Value | Notes |
| --- | --- | --- |
| `K8S_FROM` | `v1.36.4` | `prod` at creation; kind v0.33.0's node image |
| `K8S_TO` | `v1.37.0` | lab 3's target, `ha`, `green`; the console's `kubectl` is 1.37 |
| `LINKERD_FROM` / `LINKERD_TO` | `2026.8.4` / `2026.9.3` | charts; CLI `edge-26.8.4` / `edge-26.9.3`. `LINKERD_TO` is the F021 fleet's |
| `GATEWAY_API_VERSION` | `v1.4.0` | CRDs Linkerd needs and does not install |
| `VELERO_VERSION` | `v1.18.4` | CLI and server, AWS plugin `v1.14.4` |
| `SEAWEEDFS_IMAGE` | `chrislusf/seaweedfs:4.48` | lab 4's S3 store |

## Size (trainer)

Measured on a dry run (one pair, one laptop): `prod` with Linkerd HA, viz,
Bookinfo drain-safe, MySQL and Velero uses **~3 GiB**; `ha` (three control
planes, nothing else) somewhat less. With 8 trainees in **4 pairs**:

- lab 1: 4 × `ha` — start the clusters pair by pair, delete them at the end
  of the slot;
- labs 2–5: 4 × `prod` ≈ 12 GiB — at the limit of the server's 15 GiB;
  `green` (lab 4 step 6) does not fit for everyone: demo it;
- each console pulls its own `kindest/node` images (~1 GB each, two
  versions): `make -C lab0 pull-consoles` from the trainer's machine before
  slot 1.

If the server cannot take it, the fallback is the same labs on the trainees'
own machines (kind, Docker, 8 GiB free): nothing here depends on the
console except `127.0.0.1` being where kind publishes its ports.

## What was learned writing these labs

Kept here because each one is a production lesson the step files build on:

- **Restarting two kind nodes can swap their IPs** and break etcd for good:
  lab 1 loses nodes with `docker pause`, never `docker stop`.
- **A load generator in the cluster is drained with it**: k6 runs outside.
- **One Linkerd proxy-injector = unmeshed pods after a drain**: its webhook
  fails open by default. Lab 3 makes the mesh HA and fail closed.
- **Required anti-affinity on two nodes hangs every rolling update** unless
  `maxUnavailable` is at least 1.
- **A kubelet minor upgrade restarts its static pods**: on a control-plane
  node, wait for `/readyz` before draining the next node.
- **An etcd restore needs `--bump-revision --mark-compacted`**, or every
  watcher (kube-proxy first) misses the restored objects.
- **Velero skips `hostPath` volumes** — local-path's default — and the backup
  still says `Completed`. Lab 4 uses `local` PVs.
- **Bookinfo's MySQL image is MySQL 9**, which ratings-v2 cannot log into:
  lab 4 uses `mysql:8.4`.
- **Linkerd balances on latency**: a slow or broken replica behind the same
  Service as healthy ones gets almost no traffic — and hides from lab 5.
