# Lab 2 — service mesh hands-on

**Day 1, slot 3 (14h–15h30).** Same application as lab 1. Everything lab 1
ended without — encryption, per-route metrics, real load balancing, retries,
weighted releases — added without touching a line of application code.

Linkerd for the hands-on, Istio as a trainer demo at the end. Not because one
wins, but because installing Linkerd takes five minutes and leaves enough RAM
on a laptop to run the app next to it. Step 6 is where the two get compared
properly.

## Before you start

You need the end state of lab 1. If you have it, keep it. If not, step 2
applies it for you — every lab 2 overlay builds on `lab1/step3-balancing`.

```sh
export NS=<your-namespace>
make -C .. -j4 pull-linkerd       # pre-pull, the room shares one uplink
```

## The steps

| | Step | Slide | ~ |
| --- | --- | --- | --- |
| 1 | [install Linkerd](step1-install/) | Lab 2 — install Linkerd | 15 min |
| 2 | [inject the namespace](step2-inject/) | Lab 2 — inject the namespace | 10 min |
| 3 | [mTLS](step3-mtls/) | Lab 2 — mTLS | 10 min |
| 4 | [golden metrics](step4-metrics/) | Lab 2 — golden metrics | 15 min |
| 5 | [traffic management](step5-traffic/) | Lab 2 — traffic management | 20 min |
| 6 | [Istio demo + debrief](step6-istio-demo/) | Lab 2 — trainer demo / debrief | 15 + 15 min |

Steps 3 and 4 add no objects — they read the state step 2 produced. Their
overlays exist so that `kubectl apply -k` works from any step.

## How the steps work

Same rule as lab 1: each step is a kustomize overlay on the one before, so
applying a step applies everything up to it.

```sh
kubectl -n "$NS" apply -k lab2/step5-traffic     # lands you at the end of step 5
diff <(kubectl kustomize lab2/step4-metrics) \
     <(kubectl kustomize lab2/step5-traffic)     # just this step's delta
```

Step 6 is the exception: it is a separate cluster or namespace with Istio, run
by the trainer.

## Cleanup

```sh
kubectl -n "$NS" delete -k lab2/step5-traffic
kubectl annotate namespace "$NS" linkerd.io/inject-       # if you annotated the namespace
```

Removing the control plane (trainer, end of day):

```sh
linkerd viz uninstall | kubectl delete -f -
linkerd uninstall | kubectl delete -f -
```
