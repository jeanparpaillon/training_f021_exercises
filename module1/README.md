# Module 1 — large-scale microservices

Exercises for day 1 of **F021 — Advanced Kubernetes**. The slides are in
`../../training_f021/slides/pages/module1.md`; every step here names the slide
it belongs to.

| | | Slot |
| --- | --- | --- |
| [lab1/](lab1/) | deploy a multi-service application, no mesh | 2 (11h–12h30) |
| [lab2/](lab2/) | service mesh hands-on, Linkerd + Istio demo | 3 (14h–15h30) |
| exerciseA/ | namespace-as-a-service — tenants, quotas, NetworkPolicy | 4 (16h30–17h15) |
| exerciseB/ | multi-cluster — Linkerd multicluster, mirrored service | 4 (16h30–17h15) |
| [Makefile](Makefile) | pre-pull the images both labs need | prep |

The application is [Bookinfo](https://istio.io/latest/docs/examples/bookinfo/)
throughout: four services, one of them in three versions. It is reused on day 2
(resilience) and day 3 (performance), so what you build today stays.

## Conventions

- **One namespace per attendee.** No manifest hardcodes a namespace; every
  command is `kubectl -n "$NS" ...`. Set `NS` once and forget it.
- **Steps are cumulative kustomize overlays.** `kubectl -n "$NS" apply -k
  lab1/step3-balancing` brings you to the end of step 3 from anywhere,
  including from an empty namespace. Nobody has to catch up, and nobody has to
  redo the earlier steps by hand.
- **Read the diff, not just the file.** Each step directory holds only what it
  changes; `diff <(kubectl kustomize <prev>) <(kubectl kustomize <this>)` is
  the honest answer to "what did this step do?".
- Each step has a `README.md` — the step file — with the commands, what to
  look for, and questions to answer before moving on.

## Prerequisites

- `kubectl` 1.27+ (kustomize is built in, no separate binary needed)
- a cluster: local `kind`, `k3s`, or a namespace on the shared cluster
- an ingress controller for the Ingress in lab 1 step 1 — or use the
  `port-forward` fallback that step documents. On `kind`, from the repo root:

  ```sh
  make create     # kind cluster; kind.yaml maps host ports 80/443 into the node
  make ingress    # ingress-nginx controller, listening on those ports
  ```
- `linkerd` CLI for lab 2, installed in lab2/step1-install
- `istioctl` for the lab 2 step 6 demo (trainer only)

## Pre-pull the images

The room shares one uplink and Bookinfo pulls 6 images before anything
renders. Do this before the session, not during it:

```sh
make -j4 pull       # everything both labs need
make load           # kind only: push them into the cluster's own image store
make check          # what is already local
```

See [`Makefile`](Makefile) for the per-lab targets and the version variables.
