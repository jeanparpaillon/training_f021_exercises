# Step 5 — make it production-shaped

**Slide:** Lab 1 — make it production-shaped · **~20 min**

Upstream Bookinfo has no probes, one replica per service and no resource
requests. It is a demo. This step turns it into something you could put in
front of users.

```sh
kubectl -n "$NS" apply -k lab1/step5-production
kubectl -n "$NS" rollout status deploy/reviews-v1
kubectl -n "$NS" get pods -o wide
```

## What changed

| | Before | After |
| --- | --- | --- |
| Probes | none | startup / readiness / liveness on `/health` |
| Replicas | 1 everywhere | 2 for productpage, details, ratings |
| Resources | unset (BestEffort) | requests + memory limits (Burstable) |
| Voluntary disruption | unbounded | PodDisruptionBudget, `minAvailable: 1` |
| Placement | wherever | topologySpreadConstraints over nodes |

`reviews` stays at one replica **per version** — three pods already sit behind
the Service, and three JVMs per attendee is enough for a laptop. Say out loud
that this is a lab compromise, not a recommendation.

## Probes — three different questions

```sh
kubectl -n "$NS" get pod -l app=reviews,version=v1 -o jsonpath='{.items[0].status.containerStatuses[*].ready}'
kubectl -n "$NS" describe pod -l app=reviews,version=v1 | grep -A3 -E "Liveness|Readiness|Startup"
```

- **startupProbe** — "has it finished booting?" Liberty needs ~30 s; the
  startup probe gives it 30 × 5 s and holds the other two off. Without it a
  liveness probe kills the pod before it ever comes up, in a loop, forever.
- **readinessProbe** — "can it take traffic?" Controls Service endpoints.
- **livenessProbe** — "is it wedged?" Controls restarts. A liveness probe that
  checks a dependency instead of the process turns one slow backend into a
  cluster-wide restart storm — check `/health` only.

Watch readiness move an endpoint in and out:

```sh
kubectl -n "$NS" get endpoints productpage -w &
kubectl -n "$NS" delete pod -l app=productpage --wait=false
```

## Resources

Requests are what the scheduler reserves; limits are what the kernel enforces.
Note there is **no CPU limit**: a CPU limit throttles rather than kills, and
shows up later as latency nobody can explain. Memory limits are there because
the alternative is the node OOM-killing something at random.

```sh
kubectl -n "$NS" get pods -o custom-columns=\
NAME:.metadata.name,QOS:.status.qosClass
```

## PodDisruptionBudget

Covers **voluntary** disruption only — drains and upgrades, not crashes.

```sh
kubectl -n "$NS" get pdb
kubectl -n "$NS" describe pdb productpage
```

`minAvailable: 1` with `replicas: 2` lets a drain take one pod and wait for
its replacement. Setting `minAvailable` equal to `replicas` is the classic
mistake: the node becomes undrainable and cluster upgrades stall.

## Spread

```sh
kubectl -n "$NS" get pods -l app=productpage -o wide   # NODE column
```

On a single-node kind cluster both pods land on the same node, and that is
fine: `whenUnsatisfiable: ScheduleAnyway` makes the constraint a preference.
Make it `DoNotSchedule` on a real cluster — and accept that pods can then sit
`Pending` rather than be badly placed.

## Questions to answer before moving on

- Two replicas of productpage on one node: which failures does that protect
  against, and which does it not?
- Which of these five changes would have prevented an outage you have actually
  had?
