# Module 1 — Kubernetes administration in production

Exercises for module 1 of **F021bis — Kubernetes in production**. The slides are
in `../../../trainings/f021bis/slides/module1.md`; every lab here names the
slides it belongs to.

| | Lab | Slot |
| --- | --- | --- |
| [lab1/](#lab-1--break-and-repair-an-ha-control-plane) | break and repair an HA control plane: etcd quorum, partition, lost member | 1 |
| [lab2/](#lab-2--add-and-upgrade-a-component-linkerd-with-helm) | add a component and upgrade it: API versions, CRDs, Linkerd with Helm | 2 |
| [lab3/](#lab-3--upgrade-kubernetes-with-zero-downtime) | upgrade Kubernetes in place, node by node, under load, with zero downtime | 3 |
| [lab4/](#lab-4--backup-and-restore) | etcd snapshot and restore, then Velero: backup, restore, migration | 4 |
| [lab5/](#lab-5--troubleshooting) | troubleshooting: application through the mesh, then network, storage, nodes | 5 |

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
| `ha` | 3 control planes (stacked etcd) + kind's HAProxy in front | `$K8S_TO` | lab 1 | deleted at the end of lab 1 |
| `prod` | 1 control plane + 1 worker | `$K8S_FROM`, upgraded to `$K8S_TO` in lab 3 | labs 2 → 5 | kept until the end of the module |

`prod` carries the whole module: Linkerd and Bookinfo go on it in lab 2, the
upgrade of lab 3 is measured with Linkerd's metrics, lab 4 backs it up and
restores it, lab 5 breaks it. **Do not delete it between labs.** If it is
lost, `make -C lab2 catch-up` rebuilds it at the end of lab 2.

**`prod` lab compromise:** its control plane is untainted, so workloads
run on both nodes. A drained node then has somewhere to send its pods, which
is what lab 3 needs, at the cost of one less node. In production, keep
workloads off the control plane.

## Conventions

- **Steps are directories**, `labN/stepM-<name>/`, each with a `README.md` —
  the step file: commands, what to look for, questions to answer before moving
  on. Kubernetes manifests in a step are kustomize overlays, as in F021:
  `kubectl apply -k labN/stepM-…` brings you to the end of that step.
- **Hypothesis first.** Before every failure you inject, write down what you
  expect: which commands still work, which fail, for how long. A wrong guess
  is the most useful thing a lab can give you.
- **Two levels of access.** `kubectl` goes through the API server. When the
  API server is down, you go one level down with `docker exec <node> …`:
  `crictl` for containers, `journalctl -u kubelet`, the static pod manifests
  in `/etc/kubernetes/manifests/`. Each lab says which level you need.
- **Contexts.** kind switches the context to `kind-<cluster>` on creation.
  Check `kubectl config current-context` before anything destructive.
- **Clean up what you break** before the end of the slot: the next lab starts
  from a healthy `prod`.

## Prerequisites

Everything below is either in the console image or installed into `~/bin`
(on the `PATH`) by `make -C lab0 tools`, which runs in your console:

| Tool | Used in | Where |
| --- | --- | --- |
| `kubectl`, `kind`, `helm`, `docker` | all | console image |
| `etcdctl` / `etcdutl` | labs 1, 4 | **not installed**: run from the etcd container, see the helper below |
| `linkerd` CLI | labs 2, 3, 5 | `~/bin`, same version as the control plane |
| `step` (smallstep) | lab 2 | `~/bin`, for the Linkerd trust anchor and issuer |
| `velero` CLI | lab 4 | `~/bin` |
| `k6` | labs 3, 5 | runs as a Job in the cluster, nothing to install |

The exercises repo is cloned in the console home:

```sh
git clone https://github.com/jeanparpaillon/trainings_exercises.git
cd trainings_exercises/f021bis/module1
```

### Versions

Pinned in `versions.env`, sourced by every Makefile and step file. One minor
version apart on purpose: lab 3 upgrades from one to the other.

| Variable | Value | Notes |
| --- | --- | --- |
| `K8S_FROM` | `v1.36.x` | `kindest/node` image of `prod` at creation |
| `K8S_TO` | `v1.37.x` | target of lab 3; the console's `kubectl` is 1.37 |
| `LINKERD_FROM` | edge release before `LINKERD_TO` | installed in lab 2 step 2 |
| `LINKERD_TO` | `2026.9.3` (charts) | same as the F021 fleet; upgrade target of lab 2 step 4 |
| `VELERO_VERSION` | — | CLI and server image, plus the matching AWS plugin |

The trainer pins the exact patches and checks the `kindest/node` digests for
kind v0.33.0 (the console's kind) before the session.

### The etcd helper

kind nodes have no `etcdctl`, and in lab 1 the API server is sometimes down,
so `kubectl exec` is no use. The etcd container has `etcdctl` and `etcdutl`;
`lab0/etcdctl.sh` defines a shell function that reaches it through the node's
container runtime, with the kubeadm certificates:

```sh
source lab0/etcdctl.sh
etcdctl ha-control-plane member list -w table
etcdctl ha-control-plane2 endpoint status --cluster -w table
```

It runs `docker exec <node> crictl exec <etcd container> etcdctl --endpoints
https://127.0.0.1:2379 --cacert … --cert … --key … "$@"`. Read it before using
it: in lab 4 you need the same thing without the helper.

---

## Lab 1 — break and repair an HA control plane

**Slides:** *Kubernetes High Availability Architectures*, then *Lab 1* · **~60 min**

**Goal:** see with your own eyes what the failure table of the theory says —
what survives the loss of one, then two, etcd members; what a partition does;
how you get a member back when its data is gone.

**Cluster:** `ha` — three control-plane nodes, stacked etcd, no worker (kind
untaints the control planes when there is none), and the `ha-external-load-balancer`
container (HAProxy) as the stable API endpoint: *architecture A + C* of the
theory, on one machine.

| Step | | ~ |
| --- | --- | --- |
| `step1-build` | create `ha`, find each component: etcd members, leader, API servers behind HAProxy, the leader-elected scheduler and controller-manager (`kubectl -n kube-system get lease`) | 10 min |
| `step2-lose-one` | a workload writing to the API continuously (a Deployment that bumps a ConfigMap every second, `lab1/writer/`); `docker stop ha-control-plane3`: the writer keeps going, `endpoint status` shows 2/3; restart it, watch it catch up (`raft index`) | 10 min |
| `step3-lose-quorum` | stop a second member: reads and writes fail (`kubectl get` times out — API reads are quorum reads), existing pods keep running, the writer's errors pile up; restart one member, everything resumes on its own | 10 min |
| `step4-leader` | stop the node that holds the etcd leader, then the one holding the `kube-controller-manager` lease: measure how long each election takes, and what is unavailable in between | 5 min |
| `step5-partition` | cut `ha-control-plane3` off its peers with `iptables` inside its node container (ports 2379/2380 only, the API stays reachable through HAProxy): the minority member loses its leader and its API server times out on etcd; through HAProxy, find out how many requests fail, and whether HAProxy ever takes that API server out (its health check is in `/usr/local/etc/haproxy/haproxy.cfg` in the load-balancer container). Remove the rules | 10 min |
| `step6-lost-member` | wipe `/var/lib/etcd` on `ha-control-plane3` (disk loss): its etcd crashloops. Repair: `member remove`, `member add` with the same peer URL, empty data directory, let the static pod restart and resync. Check `member list` and `endpoint health --cluster` | 15 min |

**What to bring back to the debrief:** the table of the theory, filled with
your measurements — for each failure, what you could still do with `kubectl`,
for how long, and what the writer saw.

**Clean up:** `kind delete cluster --name ha`. The next labs need the room.

Questions for the step files:

- step 3: why does `kubectl get pods` fail when the pods themselves are fine?
  What does a list with `resourceVersion=0` (served from the API server's
  cache) change, and why does kubectl not use it?
- step 5: the partitioned API server process is still up. Which health
  endpoint should a load balancer check so that it is taken out, and does
  that endpoint include etcd? (`curl -k "https://<node>:6443/readyz?verbose"`
  and the same for `/livez`.)
- step 6: why must the member be *removed and re-added* rather than just
  restarted with empty data? What would happen with a 2-member cluster during
  the repair?

---

## Lab 2 — add and upgrade a component: Linkerd with Helm

**Slides:** *Upgrading what runs on Kubernetes*, then *Lab 2* · **~75 min**

**Goal:** install a component the way it will be maintained — Helm, pinned
versions, values in a file — and upgrade it: CRDs, then control plane, then
data plane. On the way, meet the API lifecycle of Kubernetes itself.

**Cluster:** `prod`, created in step 1 at `$K8S_FROM`, kept until the end of
the module.

| Step | | ~ |
| --- | --- | --- |
| `step1-cluster` | `kind create cluster --name prod --config lab2/kind.yaml` (1 control plane + 1 worker, `$K8S_FROM`); untaint the control plane; deploy Bookinfo (the F021 manifests, `../../f021/module1/lab1/base`) in namespace `bookinfo` with its Ingress | 10 min |
| `step2-apis` | API versions and schemas: `kubectl api-resources`, `kubectl explain --recursive`, the OpenAPI document (`/openapi/v3`); apply `lab2/step2-apis/legacy.yaml` (a removed `policy/v1beta1` PodDisruptionBudget, a deprecated field) and read the errors and warnings; find what was served as deprecated in `apiserver_requested_deprecated_apis` | 15 min |
| `step3-install` | Linkerd `$LINKERD_FROM` with Helm: trust anchor and issuer generated with `step`, `helm install` of `linkerd-crds`, then `linkerd-control-plane` (`--set-file` for the certificates, values in `lab2/values/`), then `linkerd-viz`; `linkerd check`; mesh Bookinfo (namespace annotation, rollout restart) | 20 min |
| `step4-upgrade` | to `$LINKERD_TO`: read the release notes, `helm diff`-style review with `helm template` + `diff`, then CRDs **first** (`helm upgrade linkerd-crds`), control plane, viz. `linkerd check --proxy` shows the data plane is still at the old version: proxies change only when pods restart. Roll Bookinfo, check again | 20 min |
| `step5-rollback` | `helm history`, `helm rollback` of the control plane; why a CRD chart is not rolled back the same way (Helm never deletes or downgrades CRDs it did not template) | 10 min |

**End state** (start of lab 3): `prod` at `$K8S_FROM`, Linkerd `$LINKERD_TO`
with viz, Bookinfo meshed in namespace `bookinfo`. `make -C lab2 catch-up`
gets there from nothing.

Questions for the step files:

- step 2: who chooses the version an object is *stored* in etcd, and how do
  you migrate stored objects before a version is removed?
- step 3: the trust anchor's private key is not in the cluster. Where does it
  live in production, and what happens the day it expires?
- step 4: why CRDs before the control plane, and never the other way round?
  What breaks if you upgrade the CLI but not the control plane?

---

## Lab 3 — upgrade Kubernetes with zero downtime

**Slides:** *Upgrading Kubernetes*, then *Lab 3* · **~75 min**

**Goal:** upgrade `prod` from `$K8S_FROM` to `$K8S_TO` the kubeadm way —
control plane, then kubelets, one node at a time — while a load generator
hits Bookinfo, and prove with Linkerd's success rate that no request was
lost.

kind nodes are kubeadm clusters in containers, so the upgrade is the real
procedure: new `kubeadm` binary, `kubeadm upgrade plan/apply`, drain, new
`kubelet`, restart, uncordon. Only the package manager is missing: the
binaries are downloaded from `dl.k8s.io` into the node.

| Step | | ~ |
| --- | --- | --- |
| `step1-baseline` | start `lab3/k6.yaml` (constant arrival rate on productpage, 10 min); `linkerd viz stat -n bookinfo deploy` gives the success rate before anything is touched. Then drain the worker as is: count the failed requests | 10 min |
| `step2-ready` | make Bookinfo survive a drain: 2 replicas, topology spread across the two nodes, PodDisruptionBudgets, readiness probes, `preStop` sleep. Drain again: zero failures. Check skew rules: `kubectl version`, kubelet versions per node | 15 min |
| `step3-control-plane` | in `prod-control-plane`: install `kubeadm` `$K8S_TO`, `kubeadm upgrade plan`, `kubeadm upgrade apply`; watch the static pods being replaced one by one (`crictl ps`), the API server restart, the load generator through it | 15 min |
| `step4-kubelets` | for each node: `kubectl drain`, `kubeadm upgrade node` (worker), new `kubelet`, `systemctl restart kubelet`, `kubectl uncordon`. `kubectl get nodes` shows the versions converging | 15 min |
| `step5-after` | add-ons and clients: CoreDNS and kube-proxy came with `kubeadm upgrade apply`; check Linkerd still passes `linkerd check`; deprecated APIs gone in `$K8S_TO`; final k6 summary vs baseline | 10 min |

**Optional, if the room has the resources:** the other way to upgrade, a
blue/green *migration* — a new cluster at `$K8S_TO`, the workload moved there,
traffic switched. It is lab 4 step 4, because it needs Velero.

**Debrief:** the k6 summary of step 1 vs step 4, and the list of what made
the difference.

Questions for the step files:

- step 2: `kubectl drain` refused to evict a pod. Which one and why? What
  does `--disable-eviction` do, and why must you never use it to get past
  a PDB?
- step 3: what is the supported skew between the API server and kubelets in
  `$K8S_TO`? Between two API servers in an HA control plane during the upgrade?
- step 4: why the worker's `kubeadm upgrade node` is fast and the control
  plane's `apply` is not.

---

## Lab 4 — backup and restore

**Slides:** *Backup and restore*, then *Lab 4* · **~80 min**

**Goal:** back up `prod` two ways and restore it — the whole cluster state
from an etcd snapshot, then namespaces and their volumes with Velero — and
learn what each one gets back, and what it does not.

| Step | | ~ |
| --- | --- | --- |
| `step1-stateful` | give Bookinfo state: ratings v2 on MySQL (`examples-bookinfo-mysqldb`, PVC on `local-path`), so a restore can be checked by its data — add a rating row, note it | 10 min |
| `step2-etcd-snapshot` | `etcdctl snapshot save` in the etcd container, copy it out of the node (`docker cp`), `etcdutl snapshot status`. Also back up `/etc/kubernetes/pki`: without the CA, the snapshot is useless | 10 min |
| `step3-etcd-restore` | after the snapshot, create a ConfigMap, then delete namespace `bookinfo`. Restore: `etcdutl snapshot restore` into a new data directory, point the etcd static pod at it, restart kubelet. `bookinfo` is back — the MySQL row too? (no: etcd holds objects, not volume data). The ConfigMap made after the snapshot is gone: a restore rolls the whole cluster back | 20 min |
| `step4-velero` | an S3-compatible store as a container on the `kind` Docker network (`lab4/s3/`); `velero install` with the AWS plugin and the node agent (file-system backup); `velero backup create bookinfo --include-namespaces bookinfo --default-volumes-to-fs-backup`; delete the namespace; `velero restore create --from-backup bookinfo`. This time the MySQL row is back | 25 min |
| `step5-schedule` | `velero schedule create` with a TTL, a backup storage location check, and the restore test as the real backup (a backup never restored is not a backup) | 5 min |
| `step6-migrate` *(optional)* | blue/green migration: a second cluster `green` at `$K8S_TO`, Velero pointed at the same bucket, restore Bookinfo there, compare. Needs about 1.5 GiB more per pair: the trainer says if the room can afford it, otherwise it is a demo | 10 min |

Questions for the step files:

- step 3: what else did the etcd restore roll back that you did not look at?
  Think of everything a controller stores as progress: Leases, node
  heartbeats, EndpointSlices, ReplicaSet revisions.
- step 3: in an HA cluster, how many etcd members do you restore, and from
  how many snapshots?
- step 4: which objects does Velero skip or rewrite on restore, and why
  (Nodes, Events, `ClusterIP`, PV names)?

---

## Lab 5 — troubleshooting

**Slides:** *Troubleshooting*, then *Lab 5* · **~60 min**

**Goal:** find and fix faults you did not inject yourself, with a method —
symptom, scope, layer — and the right tool at each layer: Linkerd viz for the
application, events and logs for Kubernetes, the node for the network and the
kubelet.

**How it runs:** `lab5/break <n>` injects scenario `n` without telling you
what it does (it applies an obfuscated kustomization or runs commands in the
nodes; do not read it before you are done). `lab5/check <n>` says whether
the fault is gone. `lab5/reset` restores the end state of lab 4. One scenario
at a time, ~10 min each, in order of layer: pick at least one per group.

| Group | Scenario | Symptom you get | Tools that find it |
| --- | --- | --- | --- |
| Application, through the mesh | 1 | stars gone from the page, intermittently | `linkerd viz stat`, `edges`, `tap` — one `reviews` version calls the wrong port |
| | 2 | the page is slow, p99 up | `linkerd viz top`, `stat --to`, latency per route — a slow `ratings` replica |
| | 3 | `503` on the whole page | `kubectl get endpointslices`, `describe svc` — a selector that matches nothing |
| Kubernetes objects | 4 | a Deployment stuck at 0/2 after an update | `rollout status`, ReplicaSet events — a quota or an admission refusal |
| Network / CNI | 5 | every name fails to resolve | `kubectl debug` with a netshoot ephemeral container, CoreDNS logs — DNS is down or blocked by a NetworkPolicy |
| | 6 | pods on the worker cannot reach pods on the control plane, same-node traffic is fine | `ip route` and `iptables` in the nodes, kindnet logs — a pod-CIDR route dropped |
| Storage | 7 | MySQL `Pending` after a reschedule | `describe pvc/pv`, node affinity of a `local-path` volume |
| Nodes | 8 | a node `NotReady`, pods `Terminating` 5 minutes later | `describe node`, `journalctl -u kubelet` in the node — kubelet stopped / bad config |

**Debrief:** for one scenario per pair, the path you followed — first
symptom, each command, what it ruled out — and the shortest path in
hindsight.

---

## Size (trainer)

Estimates, **to measure on a dry run before the session**: a 3-node
control-plane-only `ha` cluster idling at ~2.5 GiB; `prod` with Linkerd, viz
and Bookinfo at ~3 GiB, MySQL and Velero included. With 8 trainees in **4 pairs**:

- lab 1: 4 × `ha` ≈ 10 GiB — at the limit, start it pair by pair and keep
  `ha` alive only for the lab;
- labs 2–5: 4 × `prod` ≈ 12 GiB, `green` (lab 4 step 6) does not fit for
  everyone at once;
- each console pulls its own `kindest/node` images (~1 GB each, two versions
  here): pre-pull `$K8S_FROM` and `$K8S_TO` in every console before slot 1
  (`make -C lab0 pull`, from the trainer's machine via `kubectl exec`).

If the server cannot take it, the fallback is the same labs on the trainees'
own machines (kind, Docker, 8 GiB free).
