# Lab 1 — harden the application

**Day 2, slot 2 (11h–12h30).** Make Bookinfo survive the failures from the
slot 1 theory using only what Kubernetes and the client code offer. The mesh
stays injected, because it is how we measure, but none of its resilience
features are used yet: lab 2 adds those.

```
                         +--------------+
   k6 (Job, meshed) ---->| productpage  |   Python, gunicorn
                         +--------------+
                            |        |
                            v        v
                      +---------+  +---------+     +---------+
                      | details |  | reviews |---->| ratings |
                      |  Ruby   |  |  Java   |     |  Node   |
                      +---------+  +---------+     +---------+
                                    v1  v2  v3
```

## Before you start

Read [`../README.md`](../README.md) first: it covers the multi-node cluster,
the starting state and the k6 load generator. In short:

```sh
export NS=<your-namespace>
kubectl -n "$NS" apply -k lab1/step1-baseline     # from module2/
linkerd -n "$NS" viz stat deploy                  # every deployment meshed
```

All paths below are relative to `module2/`.

## The steps

| | Step | Slide | ~ |
| --- | --- | --- | --- |
| 1 | [baseline](step1-baseline/) | Lab 1 — baseline under load | 10 min |
| 2 | [probes done right](step2-probes/) | Lab 1 — probes done right | 20 min |
| 3 | [graceful shutdown](step3-shutdown/) | Lab 1 — graceful shutdown | 15 min |
| 4 | [spread and budgets](step4-spread/) | Lab 1 — spread and budgets | 15 min |
| 5 | [timeouts in the client](step5-timeouts/) | Lab 1 — timeouts in the client | 10 min |
| 6 | [fallback](step6-fallback/) + debrief | Lab 1 — fallback / debrief | 5 + 15 min |

Steps 5 and 6 add no objects: they observe what the application code does.
Their overlays exist so that `kubectl apply -k` works from any step.

## How the steps work

Same rule as day 1: each step is a kustomize overlay on the one before, so
applying a step applies everything up to it.

```sh
kubectl -n "$NS" apply -k lab1/step4-spread       # lands you at the end of step 4
diff <(kubectl kustomize lab1/step3-shutdown) \
     <(kubectl kustomize lab1/step4-spread)       # just this step's delta
```

Two things are deliberately **not** overlays, because you apply them, watch
them hurt, and take them away again:

- [`step2-probes/trap-liveness.yaml`](step2-probes/trap-liveness.yaml), a bad
  liveness probe applied with `kubectl patch`
- [`../faults/ratings-blackhole.yaml`](../faults/ratings-blackhole.yaml), a
  `ratings` that accepts connections and never answers. Steps 2 and 5 use
  it, and lab 2 replays it.

## Measure every step the same way

One k6 run per experiment, and the same three numbers each time:

```sh
kubectl -n "$NS" delete job k6 --ignore-not-found
kubectl -n "$NS" apply -f k6/constant-load.yaml
# ... do the thing (restart, delete, drain) about 20 s into the run ...
kubectl -n "$NS" logs -f job/k6 -c k6
```

| Number | Where in the k6 summary | What it tells you |
| --- | --- | --- |
| failed requests | `http_req_failed` | what the user got an error page for |
| degraded pages | the `reviews shown` / `ratings shown` checks | a `200` with an apology in it |
| p99 | `http_req_duration` | how long the unlucky 1 % waited |

Keep a table: one row per step and experiment. The debrief uses it.

`linkerd viz stat` is the other instrument, but it has blind spots this lab
runs straight into. It reports each pod's own proxy, so the requests a pod
answered badly as it died leave with it. Where the two disagree, k6 is the
user's point of view.

## Cleanup

Keep everything: lab 2 starts from `lab1/step6-fallback`. Only make sure no
fault is left behind:

```sh
kubectl -n "$NS" delete -f faults/ratings-blackhole.yaml --ignore-not-found
kubectl -n "$NS" apply -k lab1/step6-fallback     # restores replicas and probes
kubectl uncordon <worker>                         # if a drain was left half-done
```
