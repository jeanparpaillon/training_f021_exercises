# Step 1 — baseline, then a naive drain

**Slide:** Lab 3 — goal · **~10 min**

## Baseline

A short run with nothing happening: the numbers every later run is
compared to.

```sh
DURATION=1m lab3/load
```

Read the summary: `http_req_failed`, the four `checks`, `p(99)`.

## A naive drain

Bookinfo as lab 2 left it: one replica of everything, no budget. Linkerd:
one replica of each controller.

**Hypothesis first:** how many failed requests for a drain of the worker?

```sh
kubectl -n bookinfo get pods -o wide
kubectl -n linkerd get pods -o wide
DURATION=3m lab3/load > k6.log 2>&1 &
sleep 30
kubectl drain prod-worker --ignore-daemonsets --delete-emptydir-data
kubectl uncordon prod-worker
wait; tail -40 k6.log
```

Then look at what the drain left behind:

```sh
kubectl -n bookinfo get pods -o wide        # where is everything now? READY column?
linkerd viz stat -n bookinfo deploy         # MESHED column
```

## Questions

- Which failures are *failed requests* and which are *degraded pages*
  (200 with an apology)? Which service caused each?
- Are all pods still meshed (`2/2`)? If not, which component was missing
  when they were created, and why did nothing refuse them?
  (`kubectl get mutatingwebhookconfiguration linkerd-proxy-injector-webhook-config -o jsonpath='{.webhooks[0].failurePolicy}'`)
- `kubectl drain` evicted everything at once, nothing waited. What would have
  made it wait?
