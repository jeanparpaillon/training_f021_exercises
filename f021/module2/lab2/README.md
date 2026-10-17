# Lab 2 — resilience in the mesh, then chaos

**Day 2, slot 3 (14h–15h30).** Lab 1 ended with the slow dependency still
unprotected: its timeouts are hardcoded in two languages. Part A moves
timeouts, retries and circuit breaking into the mesh, without touching the
code. Part B proves the result with Chaos Mesh, one written hypothesis per
experiment.

```
                         +--------------+
   k6 (Job, meshed) ---->| productpage  |
                         +--------------+
                            |        |  HTTPRoute reviews: timeout 1 s, no retry
                            v        v
                      +---------+  +---------+     +---------+
                      | details |  | reviews |---->| ratings |
                      +---------+  +---------+     +---------+
                                    v1  v2  v3   HTTPRoutes ratings: timeout 500 ms,
                                                 GET retried once
                                                 Service: failure accrual
```

## Before you start

Lab 2 starts from the end of lab 1. If you have it, keep it; step 1 applies
it anyway, since every lab 2 overlay builds on `lab1/step6-fallback`.

```sh
export NS=<your-namespace>
kubectl -n "$NS" apply -k lab2/step1-routes      # from module2/
```

All paths below are relative to `module2/`.

## The steps

| | Step | Slide | ~ |
| --- | --- | --- | --- |
| **A** | | | |
| 1 | [timeouts and retries per route](step1-routes/) | Lab 2 — timeouts and retries per route | 15 min |
| 2 | [circuit breaking with failure accrual](step2-failure-accrual/) | Lab 2 — circuit breaking with failure accrual | 15 min |
| 3 | [trainer demo: Istio](step3-istio-demo/) | Lab 2 — trainer demo: Istio | 10 min |
| **B** | | | |
| 4 | [install Chaos Mesh](step4-chaos-mesh/) | Lab 2 — install Chaos Mesh | 5 min |
| 5 | [pod kill](step5-pod-kill/) | Lab 2 — first experiment: pod kill | 10 min |
| 6 | [network delay](step6-delay/) | Lab 2 — network delay | 10 min |
| 7 | [network partition](step7-partition/) + debrief | Lab 2 — network partition / debrief | 10 + 15 min |

## How the steps work

Same rule as lab 1: each step is a kustomize overlay on the one before.

```sh
kubectl -n "$NS" apply -k lab2/step2-failure-accrual
diff <(kubectl kustomize lab2/step1-routes) \
     <(kubectl kustomize lab2/step2-failure-accrual)
```

Two exceptions:

- **Step 3** is a trainer demo on the day-1 Istio namespace. It is not in
  the chain: step 4 builds on step 2.
- **Steps 4 to 7 add nothing to the application.** Their experiments
  (`PodChaos`, `NetworkChaos`) sit next to the overlay and are applied by
  hand while k6 runs, then deleted. They are not in the overlay, or every
  `apply -k` would start them again.

The faults you apply and remove live in [`../faults/`](../faults/): the
black hole from lab 1, and [`ratings-faulty.yaml`](../faults/ratings-faulty.yaml)
for step 2.

## Measuring

The k6 run and the three numbers from lab 1 (failed requests, degraded
pages, p99) still apply. Part A adds one instrument, because the mesh now
does things the application does not see:

```sh
lab2/route-stats.sh reviews-v2           # every route reviews-v2 calls
lab2/route-stats.sh productpage-v1 reviews
```

It sums the Linkerd proxy counters of one Deployment, per route: the
**requests** the application made, the **attempts** the proxy actually sent
(retries included), and the **retries**. `linkerd viz routes` would show
the same as EFFECTIVE and ACTUAL success, but it only reads ServiceProfiles,
not HTTPRoutes. The script needs `linkerd` on the `PATH` and `NS` set.

## Hypothesis first (Part B)

Before any experiment, write this down, with numbers:

```
Hypothesis:  <steady state that should hold, in numbers>
Injection:   <fault, target, size>
Observe:     <where: linkerd viz, k6 summary>
Abort if:    <threshold at which you stop the experiment>
Result:      confirmed / refuted -> action
```

A result you did not predict is a finding. A result you did not write a
prediction for is only noise.

## Cleanup

Keep Bookinfo at the end of step 2 for the game day. Only make sure no fault
or experiment is left behind:

```sh
kubectl -n "$NS" delete podchaos,networkchaos,schedule --all
kubectl -n "$NS" delete -f faults/ratings-faulty.yaml --ignore-not-found
kubectl -n "$NS" delete -f faults/ratings-blackhole.yaml --ignore-not-found
kubectl -n "$NS" apply -k lab2/step7-partition
```
