# Lab 1 — deploy a multi-service application

No mesh yet: lab 2 adds that on top of what you
build here.

The application is [Bookinfo](https://istio.io/latest/docs/examples/bookinfo/):
four services, one of them (`reviews`) in three versions. It is small enough to
fit on a laptop and structured enough to show fan-out, versioning and failure.

```
                       +--------------+
   user --- Ingress -->| productpage  |   Python/Flask
                       +--------------+
                          |        |
                          v        v
                    +---------+  +---------+     +---------+
                    | details |  | reviews |---->| ratings |
                    |  Ruby   |  |  Java   |     |  Node   |
                    +---------+  +---------+     +---------+
                                  v1  v2  v3
                                  no / black / red stars
```

## Before you start

```sh
export NS=<your-namespace>          # one namespace per attendee
kubectl config set-context --current --namespace="$NS"   # optional, saves typing
kubectl auth can-i create deployments -n "$NS"
```

Images are large-ish and the room shares one uplink. Pre-pull them (see
[`../Makefile`](../Makefile)):

```sh
make -C .. -j4 pull-tools pull-bookinfo
make -C .. load          # kind only: pulls everything, then pushes it into
                         # the cluster's own image store
```

## The steps

| | Step | Slide | ~ |
| --- | --- | --- | --- |
| 1 | [deploy Bookinfo](step1-deploy/) | Lab 1 — deploy Bookinfo | 15 min |
| 2 | [service discovery](step2-discovery/) | Lab 1 — service discovery | 15 min |
| 3 | [round-robin across versions](step3-balancing/) | Lab 1 — round-robin across reviews versions | 10 min |

## How the steps work

Each step is a kustomize overlay on the one before it, so **applying a step
applies everything up to it**. Nobody has to catch up:

```sh
kubectl -n "$NS" apply -k lab1/step3-balancing   # lands you at the end of step 3
```

See what a step would change before applying it:

```sh
kubectl kustomize lab1/step3-balancing             # the full rendered state
diff <(kubectl kustomize lab1/step2-discovery) \
     <(kubectl kustomize lab1/step3-balancing)     # just this step's delta
```

[`base/`](base/) is Bookinfo as Istio ships it — no probes, one replica each,
no mesh. Every overlay builds on that, and the diff above is the honest answer
to "what did this step actually do?".

## Cleanup

```sh
kubectl -n "$NS" delete -k lab1/step3-balancing
```

Keep it running if you are going straight into lab 2 — lab 2 starts from the
step 3 state.
