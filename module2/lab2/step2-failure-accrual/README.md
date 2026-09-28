# Step 2 — circuit breaking with failure accrual

**Slide:** Lab 2 — circuit breaking with failure accrual · **~15 min**

Linkerd's circuit breaker works per **endpoint**, not per service. Each
client proxy counts the consecutive failures of each endpoint it balances
over, and stops sending to one that crosses the threshold. To see it,
`ratings` needs two endpoints, one of them bad.

[`../../faults/ratings-faulty.yaml`](../../faults/ratings-faulty.yaml) adds
a second `ratings` replica behind the same Service. It is up, its `/health`
answers 200, and every real request gets a 500. Readiness cannot catch it,
which is what a broken database connection or a bad config looks like.

## 1. The faulty replica, with the step 1 retries

Start from step 1, start k6, and add the faulty replica:

```sh
kubectl -n "$NS" apply -k lab2/step1-routes
kubectl -n "$NS" delete job k6 --ignore-not-found && kubectl -n "$NS" apply -f k6/constant-load.yaml
kubectl -n "$NS" apply -f faults/ratings-faulty.yaml
```

```sh
linkerd -n "$NS" viz stat deploy --from deploy/reviews-v2 -t 30s
lab2/route-stats.sh reviews-v2 ratings-get
```

The retries hide it: the 500 attempts are there, but the requests succeed.
The faulty endpoint also gets much less traffic than half. Retrying a
failed attempt costs time, and the balancer, which picks the endpoint with
the lower latency out of two (P2C with EWMA), reads that time as slowness.
That is a side effect of retries, not a circuit breaker, and it depends on
timing you do not control.

## 2. Without the retries

To see the bare failure, take the GET retries away for a moment:

```sh
kubectl -n "$NS" delete httproute.policy.linkerd.io ratings-get
sleep 30; linkerd -n "$NS" viz stat deploy --from deploy/reviews-v2 -t 30s
```

Now `ratings-faulty` gets its share: about half of the calls, at 0 %
success. In k6, the `ratings shown` check starts failing for the v2 and v3
pages.

## 3. Failure accrual

Enable it on the `ratings` Service, on its own, with the retries still off
([`ratings-accrual.yaml`](ratings-accrual.yaml)):

```sh
kubectl -n "$NS" patch svc ratings --patch-file lab2/step2-failure-accrual/ratings-accrual.yaml
sleep 30; linkerd -n "$NS" viz stat deploy --from deploy/reviews-v2 -t 30s
```

After 3 consecutive failures, each client proxy ejects the endpoint.
`ratings-faulty` drops to about 0.1 rps: those are the **probes**, one
real request each time the penalty runs out (5 s, then 10, 20, up to 30 s).
Each probe that fails is a degraded page for a real user.

Repair it, and watch it come back after the next probe:

```sh
kubectl -n "$NS" exec deploy/ratings-faulty -c ratings -- touch /tmp/healthy
sleep 40; linkerd -n "$NS" viz stat deploy --from deploy/reviews-v2 -t 15s
```

Break it again for the last part:

```sh
kubectl -n "$NS" exec deploy/ratings-faulty -c ratings -- rm /tmp/healthy
```

## 4. Both

The step overlay is step 1 (retries back) plus failure accrual:

```sh
kubectl -n "$NS" apply -k lab2/step2-failure-accrual
kubectl -n "$NS" delete job k6 --ignore-not-found && kubectl -n "$NS" apply -f k6/constant-load.yaml
kubectl -n "$NS" logs -f job/k6 -c k6
```

Failure accrual keeps the bad endpoint out, and the retry covers the probe
requests that land on it. `ratings shown` should be back to (almost) 100 %.

Remove the fault:

```sh
kubectl -n "$NS" delete -f faults/ratings-faulty.yaml
```

## Questions

- What happens when the **only** endpoint is ejected? Try it: scale
  `ratings-v1` to 0 with the faulty replica still broken. What does
  `reviews` get back, and how fast?
- How is this different from a retry? Which one reduces the load on the
  bad endpoint, and which one increases it?
- The probes are real user requests. What would it take to probe with
  something else, and why does Linkerd not do it?
- Istio calls this *outlier detection* and lets you cap it
  (`maxEjectionPercent`). Why would you want to forbid ejecting every
  endpoint?
- Readiness said the faulty pod was fine the whole time. Should its
  `/health` have checked more? Remember lab 1 step 2.
