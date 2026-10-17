# Lab 3 — upgrade Kubernetes with zero downtime

**Slides:** *Upgrading Kubernetes*, then *Lab 3* · **~75 min**

`prod` from `K8S_FROM` to `K8S_TO`, the kubeadm way — control plane, then
each kubelet — while a load generator hits Bookinfo. kind nodes are kubeadm
clusters in containers: this is the real procedure, only the package
manager is missing (binaries come from `dl.k8s.io`).

| Step | | ~ |
| --- | --- | --- |
| [step1-baseline](step1-baseline/) | load, then a naive drain | 10 min |
| [step2-ready](step2-ready/) | make Bookinfo **and the mesh** drain-safe | 15 min |
| [step3-control-plane](step3-control-plane/) | `kubeadm upgrade apply` | 15 min |
| [step4-kubelets](step4-kubelets/) | node by node: drain, kubelet, uncordon | 15 min |
| [step5-after](step5-after/) | add-ons, clients, the numbers | 10 min |

| File | What it is |
| --- | --- |
| [`k6.js`](k6.js), [`load`](load) | the load generator: k6 in your console's Docker, against the NodePort |
| [`step2-ready/`](step2-ready/) | Bookinfo drain-safe (overlay) + Linkerd HA values |

**The referees**, one per terminal tab:

```sh
lab3/load > k6.log 2>&1 &                       # or in its own tab, in the foreground
watch -n2 linkerd viz stat -n bookinfo deploy   # success rate, from the server side
```

k6 runs **outside** the cluster, like users: `kubectl drain` evicts every
pod, and a load generator running as a pod would be evicted with its
summary.

**End state** (start of lab 4): `prod` at `K8S_TO`, Linkerd HA, Bookinfo
drain-safe. From nothing: `make catch-up-lab3` in `module1/` (creates the
cluster directly at `K8S_TO`).

```sh
cd ~/trainings_exercises/f021bis/module1
source versions.env
```

## Debrief table

| | Failed requests (k6) | Degraded pages (k6 checks) | p99 | Notes |
| --- | --- | --- | --- | --- |
| step 1, naive drain | | | | |
| step 2, drain | | | | |
| step 3, control plane | | | | |
| step 4, kubelets | | | | |
