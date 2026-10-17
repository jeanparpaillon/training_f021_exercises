# Step 6 — network delay

**Slide:** Lab 2 — network delay · **~10 min**

```sh
kubectl -n "$NS" apply -k lab2/step6-delay         # step 2, nothing new
```

Two experiments on the same link, `productpage` → `reviews`, one on each
side of the 1 s timeout of the step 1 `reviews` route:

| File | Delay | vs the 1 s route timeout |
| --- | --- | --- |
| [`delay-below.yaml`](delay-below.yaml) | 300 ms ± 100 ms | below |
| [`delay-above.yaml`](delay-above.yaml) | 1500 ms | above |

Both delay the packets `productpage` sends to the `reviews` pods (`tc
netem`, applied by `chaos-daemon` in productpage's network namespace), for
2 minutes.

## Below the timeout

Hypothesis first. How much does p99 move? Do any requests fail? Does the
page change?

```sh
kubectl -n "$NS" delete job k6 --ignore-not-found && kubectl -n "$NS" apply -f k6/constant-load.yaml
sleep 20
kubectl -n "$NS" apply -f lab2/step6-delay/delay-below.yaml
kubectl -n "$NS" describe networkchaos productpage-reviews-delay | grep -A5 Records
linkerd -n "$NS" viz stat deploy --from deploy/productpage-v1
kubectl -n "$NS" logs -f job/k6 -c k6
kubectl -n "$NS" delete -f lab2/step6-delay/delay-below.yaml
```

## Above the timeout

Hypothesis again, and this time also write down **what the user sees**,
and after how long.

```sh
kubectl -n "$NS" delete job k6 --ignore-not-found && kubectl -n "$NS" apply -f k6/constant-load.yaml
sleep 20
kubectl -n "$NS" apply -f lab2/step6-delay/delay-above.yaml
lab2/route-stats.sh productpage-v1 reviews
kubectl -n "$NS" logs -f job/k6 -c k6
kubectl -n "$NS" delete -f lab2/step6-delay/delay-above.yaml
```

Count the attempts per page from `route-stats.sh`, and compare the page
time with the 2 s budget from lab 1 step 5.

## Questions

- Below the timeout: nothing failed, and still the experiment found
  something. What did the delay do to p99 and to productpage's gunicorn
  workers? At what request rate does 300 ms more per request start to
  exhaust them?
- Above the timeout: did the step 1 timeout fire? What did productpage do
  with the 504? Is the page time what you predicted, and which of the two
  retry layers from step 1 is responsible?
- Failed requests or degraded pages: which one does k6 count here? Which
  one would your alerting see?
- A delay on the network looks like a slow `reviews`. What would tell the
  two apart in `linkerd viz`?
