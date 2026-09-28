# Step 5 — first experiment: pod kill

**Slide:** Lab 2 — first experiment: pod kill · **~10 min**

```sh
kubectl -n "$NS" apply -k lab2/step5-pod-kill      # step 2, nothing new
```

## Write the hypothesis first

On paper, before anything is applied:

```
Hypothesis:  killing one reviews pod does not change the success rate,
             and p99 stays under 500 ms
Injection:   PodChaos pod-kill, one reviews pod out of six, no grace period
Observe:     k6 summary (failed, degraded, p99), linkerd viz stat
Abort if:    failed requests > 1 %
Result:      ?
```

Fill in your own numbers from lab 1 if you think these are wrong. Then
write down *why* you expect it to hold: which lab 1 settings should make it
true?

## Run it

[`reviews-pod-kill.yaml`](reviews-pod-kill.yaml) kills one `reviews` pod
with `gracePeriod: 0`: no SIGTERM, no `preStop`. It is a crash, not the
rolling restart of lab 1 step 3.

```sh
kubectl -n "$NS" delete job k6 --ignore-not-found && kubectl -n "$NS" apply -f k6/constant-load.yaml
sleep 20
kubectl -n "$NS" apply -f lab2/step5-pod-kill/reviews-pod-kill.yaml
kubectl -n "$NS" get pods -l app=reviews -w          # which one went, and how long the new one takes
```

```sh
kubectl -n "$NS" describe podchaos reviews-pod-kill  # Events: which pod was killed
kubectl -n "$NS" logs -f job/k6 -c k6
```

A pod kill is instantaneous. The `PodChaos` object stays as a record, and
applying it again does nothing. Delete it before the next run:

```sh
kubectl -n "$NS" delete -f lab2/step5-pod-kill/reviews-pod-kill.yaml
```

## Confirmed or refuted?

Write the result under the hypothesis. If it was refuted, find the lab 1
setting that was missing: replicas, spread, readiness or the startup probe.
To check, remove it and run again. For example, one replica per version:

```sh
kubectl -n "$NS" scale deploy/reviews-v1 deploy/reviews-v2 deploy/reviews-v3 --replicas=1
# ... run the experiment again ...
kubectl -n "$NS" apply -k lab2/step5-pod-kill      # back to two
```

Then run the same experiment on `productpage` (edit `app: reviews` to
`app: productpage`). Write the hypothesis again first: nothing retries
productpage for k6.

## Questions

- The killed pod had requests in flight. Who retried them, and would a
  POST have been retried?
- The replacement `reviews` pod passes its startup probe, then gets
  traffic. Is a freshly started JVM as fast as the one it replaces? Look
  at p99 during the first seconds, and at the 1 s route timeout from
  step 1.
- `mode: one` kills one pod out of six. Which `mode` and value would test
  the loss of a whole node? Would the PDBs of lab 1 step 4 stop it?
