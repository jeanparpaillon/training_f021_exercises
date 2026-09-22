# Step 6 — break something

**Slide:** Lab 1 — break something · **~10 min**, then the debrief

Everything from step 5 is still in place: probes, two replicas, PDBs, spread.
Now take `details` away.

```sh
kubectl -n "$NS" apply -k lab1/step6-break
kubectl -n "$NS" get pods -l app=details     # none left
```

Then load `/productpage` and look at the page.

## What the user sees

The book details block is replaced by an error. The page still renders —
`reviews` and `ratings` are untouched — but a service nobody would call
critical has visibly degraded the product.

```sh
kubectl -n "$NS" logs deploy/productpage-v1 -c productpage --tail=20
kubectl -n "$NS" exec deploy/toolbox -- sh -c \
  'time wget -q -O /dev/null http://productpage:9080/productpage'
```

Watch how long the request takes. productpage calls `details` with no timeout
worth the name, so the user waits for a failure instead of getting a fast
partial answer.

## Why nothing you added in step 5 helped

- **Probes** — `details` is not unhealthy. It is *absent*. There is nothing to
  probe.
- **Replicas** — two replicas of zero is still zero.
- **PDB** — this was not a voluntary disruption.
- **Init container** — it guarded *startup*. productpage was already running.

Redundancy is not fault tolerance. It only becomes fault tolerance once
something detects the failure and routes around it — the slide from slot 1,
now with a broken page attached to it.

## Put it back

```sh
kubectl -n "$NS" apply -k lab1/step5-production
kubectl -n "$NS" rollout status deploy/details-v1
```

## Debrief — what a mesh would add here

**Slide:** Lab 1 — debrief · **15 min**

The missing pieces, in the order lab 2 adds them:

| Gap you just saw | What handles it |
| --- | --- |
| No idea which call failed or how slow it was | L7 metrics per service and per route |
| Per-connection balancing, useless for gRPC | L7 load balancing in the proxy |
| No timeout, no retry, no fallback | timeouts and retries at the proxy |
| No way to send 10% of traffic to v3 | weighted routing |
| Traffic in clear text between pods | mTLS, with a workload identity |

None of these needs a line of application code. That is the claim lab 2 is
there to test — including what it costs.
