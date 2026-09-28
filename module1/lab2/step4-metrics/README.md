# Step 4 — golden metrics

**Slide:** Lab 2 — golden metrics · **~15 min**

Still nothing to apply. `loadgen` from lab 1 step 3 is what makes this step
show anything at all — if you scaled it down, bring it back:

```sh
kubectl -n "$NS" scale deploy/loadgen --replicas=1
```

## Success rate, requests per second, latency

```sh
linkerd -n "$NS" viz stat deploy
linkerd -n "$NS" viz stat deploy/productpage --to deploy/reviews
```

Three numbers per service, none of which anybody instrumented: the proxy sees
every request and reports it. That is the observability argument for a mesh in
one command.

Per-route, rather than per-service:

```sh
linkerd -n "$NS" viz routes deploy/productpage
linkerd -n "$NS" viz routes deploy/productpage --to deploy/reviews
```

## The dashboard

```sh
linkerd -n "$NS" viz dashboard &
```

Walk the topology graph: productpage → details, productpage → reviews,
reviews → ratings. It is the diagram from lab 1 step 1, drawn from live
traffic instead of from documentation.

## Break something, with instruments this time

```sh
kubectl -n "$NS" scale deploy/details-v1 --replicas=0
linkerd -n "$NS" viz stat deploy --from deploy/productpage
```

Without a mesh, the only signal would be a broken page. Now the success rate of the
productpage → details edge collapses, you can see how long the failing calls
take, and `tap` shows the individual failures:

```sh
linkerd -n "$NS" viz tap deploy/productpage | grep -v "200"
kubectl -n "$NS" scale deploy/details-v1 --replicas=1
```

## What this is not

- These are **proxy-level** metrics: RED metrics per hop. They tell you which
  edge is slow, not which SQL query is. You still need application traces and
  logs.
- Linkerd's Prometheus is sized for the dashboard's own retention, not for
  long-term storage. In production it federates to yours — worth a sentence,
  it is a common mistake to discover this after an incident.
- Every request now costs a proxy hop on each side. Keep an eye on the latency
  column while you look at the success-rate column.

## Questions

- `viz stat` shows p50/p95/p99 per edge. Which of those would you alert on for
  productpage, and why not the others?
- The metrics are scraped from the proxies. What happens to the numbers for a
  service whose proxy was never injected?
