# Step 1 — baseline

**Slide:** Lab 1 — baseline under load · **~10 min**

Nothing is hardened yet. This step records how the application behaves as
day 1 left it, so that every later step has something to be compared with.

```sh
kubectl -n "$NS" apply -k lab1/step1-baseline
linkerd -n "$NS" viz stat deploy
```

The overlay is the end of module 1 lab 2 step 4 (meshed, no HTTPRoute) with
the day-1 `loadgen` scaled to 0. From now on k6 generates the load.

## Steady state

```sh
kubectl -n "$NS" apply -f k6/constant-load.yaml
kubectl -n "$NS" logs -f job/k6 -c k6
```

Three minutes at 20 requests per second. While it runs:

```sh
linkerd -n "$NS" viz stat deploy
linkerd -n "$NS" viz stat deploy --from deploy/productpage-v1
```

Write down the success rate and p99 of `productpage`, from both k6 and
`viz stat`. That is the steady state everything else is measured against.

## Three routine operations, under load

Start a fresh k6 run for each (`delete job k6`, then `apply`). Wait 20 s,
then do one of these:

```sh
# 1. restart one version of reviews
kubectl -n "$NS" rollout restart deploy/reviews-v2

# 2. restart all three versions of reviews at once
kubectl -n "$NS" rollout restart deploy/reviews-v1 deploy/reviews-v2 deploy/reviews-v3

# 3. restart the front end
kubectl -n "$NS" rollout restart deploy/productpage-v1
```

And one that is not routine:

```sh
# 4. lose the only productpage pod
kubectl -n "$NS" delete pod -l app=productpage
```

For each one, note the failed requests, the degraded pages (the checks) and
the p99.

## What to look for

- Failed requests and degraded pages are not the same thing. Look at which
  operation produced which. `productpage` answers `200` even when it could
  not get the reviews: the user sees *"Sorry, product reviews are currently
  unavailable"*, but `http_req_failed` counts a success.
- Compare `viz stat` for productpage after run 3 with the k6 summary. The
  pod that answered the errors no longer exists, and neither do its metrics.
- Restarting `reviews-v2` alone may cost nothing at all. Find out why before
  you conclude that restarts are harmless. Hint: look for `range(2)` in
  `kubectl -n "$NS" exec deploy/productpage-v1 -c productpage -- cat productpage.py`.

## Questions

- A rolling restart is the most routine operation there is. How many
  requests did it cost, and which ones did nobody count?
- Why is a single `productpage` pod a problem that no restart policy fixes?
- `reviews` is a JVM that takes several seconds to boot. When did the new
  pod start receiving traffic, and was it ready to serve it?
