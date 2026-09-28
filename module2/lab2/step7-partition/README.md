# Step 7 — network partition

**Slide:** Lab 2 — network partition · **~10 min + 15 min debrief**

```sh
kubectl -n "$NS" apply -k lab2/step7-partition     # step 2, nothing new
```

[`ratings-partition.yaml`](ratings-partition.yaml) drops every packet
between the `ratings` pods and the `reviews` pods, both ways, for 2
minutes. Nothing answers, not even the TCP handshake. Meanwhile Kubernetes
still sees `ratings` as healthy: the kubelet is not partitioned, so the
probes pass and the endpoints stay.

## Hypothesis

Lab 1 step 5 ran almost the same experiment with the black hole, before
the mesh had any timeout. Write down what you expect now:

- does the page degrade (fallback) or hang, and for how long?
- does failure accrual (step 2) eject the `ratings` endpoint?
- what happens in the first seconds after the partition lifts?

## Run it

```sh
kubectl -n "$NS" delete job k6 --ignore-not-found && kubectl -n "$NS" apply -f k6/constant-load.yaml
sleep 20
kubectl -n "$NS" apply -f lab2/step7-partition/ratings-partition.yaml
```

While it runs:

```sh
linkerd -n "$NS" viz stat deploy --from deploy/reviews-v2 -t 30s
lab2/route-stats.sh reviews-v2 ratings-get
linkerd diagnostics proxy-metrics -n "$NS" deploy/reviews-v2 \
  | grep '^outbound_http_balancer_endpoints' | grep 'parent_name="ratings"'
kubectl -n "$NS" get endpointslices -l kubernetes.io/service-name=ratings
```

The last command shows what Kubernetes believes; the one before shows
what the proxies believe. When the 2 minutes are up, or earlier:

```sh
kubectl -n "$NS" delete -f lab2/step7-partition/ratings-partition.yaml
kubectl -n "$NS" logs -f job/k6 -c k6
```

## Compare

| | Lab 1 step 5, black hole | Here, partition |
| --- | --- | --- |
| page time with v2 | | |
| page time with v3 | | |
| degraded pages | | |
| failed requests | | |
| endpoint ejected? | | |

## Questions

- Did failure accrual kick in? Look at what it counts: responses. What
  does a partitioned endpoint send back?
- The endpoints never left the EndpointSlice. Which component, if any,
  knew that `ratings` was unreachable?
- The mesh timeout turned a hang into a degraded page. What turned it
  into a degraded page and not an error page?

## Debrief (15 min)

- Your experiments are YAML files. Where should they live: next to the
  manifests they test, in the same repository, reviewed the same way?
- How would you run them every night? A Chaos Mesh `Schedule` creates a
  new experiment from a template on a cron. See
  [`nightly-schedule.yaml`](nightly-schedule.yaml), not applied in the lab.
- What makes an experiment a **test**: a pass/fail criterion. The k6 run
  already has one, its thresholds, and the Job ends `Failed` when they
  are crossed. What would the equivalent be as a Prometheus query in CI?
  And who gets paged when the nightly run fails?

Before the game day, make sure nothing is left running:

```sh
kubectl -n "$NS" get podchaos,networkchaos,schedule
kubectl -n "$NS" delete podchaos,networkchaos,schedule --all
```
