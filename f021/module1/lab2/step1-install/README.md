# Step 1 — install Linkerd

**Slide:** Lab 2 — install Linkerd · **~15 min**

No manifests in this step: the control plane is installed with the CLI, which
generates them. Why Linkerd for the hands-on and Istio only as a demo is on
the *goal and tooling choice* slide — short version: this takes five minutes
and fits in the room's RAM.

## Get the CLI

```sh
curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/install | sh
export PATH="$HOME/.linkerd2/bin:$PATH"
linkerd version --client
```

## Check the cluster before touching it

```sh
linkerd check --pre
```

This checks Kubernetes version, RBAC and whether anything conflicts. Fix what
it reports before continuing — every later problem in this lab traces back to
a skipped `linkerd check`.

## Install

CRDs first, then the control plane:

```sh
linkerd install --crds | kubectl apply -f -
linkerd install | kubectl apply -f -
linkerd check
```

Then the metrics extension — `linkerd viz` is what makes steps 3 and 4
possible, and it is a separate install on purpose:

```sh
linkerd viz install | kubectl apply -f -
linkerd check
```

## What you just installed

```sh
kubectl -n linkerd get deploy
kubectl -n linkerd-viz get deploy
```

- `linkerd-destination` — service discovery and policy, the thing every proxy
  asks "where do I send this, and am I allowed to?"
- `linkerd-identity` — a certificate authority issuing one identity per
  workload, which is what makes mTLS automatic in step 3
- `linkerd-proxy-injector` — the admission webhook that rewrites pod specs
- `linkerd-viz` — Prometheus, the metrics API and the dashboard

Note what is *not* there: nothing in your application namespace yet. The
control plane is installed; nothing is meshed.

## On a shared cluster

The control plane is cluster-wide — one install for the room, done by the
trainer. Attendees start at step 2.

## Questions

- `linkerd check` passes. What has actually changed for your application at
  this point? (Nothing. That is the point of the next step.)
- The identity component issues certificates with a 24-hour lifetime by
  default. What has to be true about the cluster for that to work?
