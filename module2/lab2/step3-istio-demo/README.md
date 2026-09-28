# Step 3 — trainer demo: Istio

**Slide:** Lab 2 — trainer demo: Istio · **~10 min**, demo only

Run by the trainer, on the `bookinfo-istio` namespace from module 1 lab 2
step 6. It is not part of the attendees' chain: step 4 builds on step 2.

The overlay starts from the day-1 Istio demo and adds, for `ratings`, what
steps 1 and 2 did on Linkerd, plus a bulkhead Linkerd does not have:

| Job | Linkerd (steps 1–2) | Istio (here) |
| --- | --- | --- |
| Timeout, retries | `HTTPRoute` + 4 annotations | `VirtualService`: `timeout`, `retries` ([file](ratings-virtualservice.yaml)) |
| Eject a bad endpoint | Service annotation `failure-accrual` | `DestinationRule` `outlierDetection` ([file](ratings-destination-rule.yaml)) |
| Bulkhead | — | `DestinationRule` `connectionPool` |
| Fault injection | — (Chaos Mesh, step 4) | `VirtualService` `fault` ([file](fault-injection.yaml)) |

```sh
kubectl -n bookinfo-istio apply -k lab2/step3-istio-demo
diff <(kubectl kustomize ../module1/lab2/step6-istio-demo) <(kubectl kustomize lab2/step3-istio-demo)
```

`reviews` routes 90 % to v1 (the day-1 canary), and v1 never calls
`ratings`. So the demo calls `ratings` from a `reviews-v3` pod directly,
through its Envoy.

## Outlier detection

```sh
kubectl -n bookinfo-istio apply -f faults/ratings-faulty.yaml
kubectl -n bookinfo-istio rollout status deploy/ratings-faulty
kubectl -n bookinfo-istio exec deploy/reviews-v3 -c reviews -- sh -c \
  'for i in $(seq 1 30); do curl -s -o /dev/null -w "%{http_code} " http://ratings:9080/ratings/0; done; echo'
```

All 200: the retries cover the failed attempts. Then the per-endpoint view
from the caller's Envoy:

```sh
istioctl -n bookinfo-istio proxy-config endpoint deploy/reviews-v3 \
  --cluster "outbound|9080||ratings.bookinfo-istio.svc.cluster.local"
# without istioctl:
kubectl -n bookinfo-istio exec deploy/reviews-v3 -c istio-proxy -- pilot-agent request GET clusters \
  | grep '^outbound|9080||ratings.bookinfo-istio' | grep -E 'health_flags|rq_error|rq_success'
```

The faulty endpoint shows `OUTLIER CHECK FAILED` (`/failed_outlier_check`).
Same result as step 2. Point out the knobs Istio adds:
`maxEjectionPercent`, and a linear back-off where Linkerd doubles.

```sh
kubectl -n bookinfo-istio delete -f faults/ratings-faulty.yaml
```

## Bulkhead

The connection pool allows 5 connections and 2 pending requests to
`ratings`. Make `ratings` hang, then send 20 calls at once:

```sh
kubectl -n bookinfo-istio apply -f faults/ratings-blackhole.yaml
kubectl -n bookinfo-istio scale deploy/ratings-v1 --replicas=0
kubectl -n bookinfo-istio rollout status deploy/ratings-blackhole
kubectl -n bookinfo-istio exec deploy/reviews-v3 -c reviews -- sh -c \
  'for i in $(seq 1 20); do curl -s -o /dev/null -w "%{http_code} %{time_total}\n" http://ratings:9080/ratings/0 & done; wait' | sort
```

Most calls get a `503` in a few milliseconds (overflow, response flag
`UO`). Only the few that got a slot wait for the 500 ms timeout (`504`).
The hanging dependency can hold 5 connections of the caller, not all of
them. Without the pool, all 20 would wait, and in a real service that is
20 threads out of the caller's pool.

```sh
kubectl -n bookinfo-istio scale deploy/ratings-v1 --replicas=1
kubectl -n bookinfo-istio delete -f faults/ratings-blackhole.yaml
```

## Fault injection

```sh
kubectl -n bookinfo-istio apply -f lab2/step3-istio-demo/fault-injection.yaml
kubectl -n bookinfo-istio exec deploy/reviews-v3 -c reviews -- sh -c \
  'for i in $(seq 1 16); do curl -s -o /dev/null -w "%{http_code}/%{time_total} " http://ratings:9080/ratings/0; done; echo'
kubectl -n bookinfo-istio apply -k lab2/step3-istio-demo      # revert
```

Half the calls get a 500, half wait 2 s, and some get both. Two things to
point out:

- the 500s are **not retried**, and the 2 s delays are **not cut** by the
  500 ms timeout. The fault filter runs before the router, so it tests the
  caller's own reaction, not the mesh's;
- nothing ran in the `ratings` pods. It is the cheapest chaos there is,
  but it only exists inside Istio. Part B brings the same to any cluster.

## Compare

Count the YAML: [`ratings-destination-rule.yaml`](ratings-destination-rule.yaml)
and [`ratings-virtualservice.yaml`](ratings-virtualservice.yaml) against
`../step1-routes/` and `../step2-failure-accrual/`. Then count the knobs:
Istio has more, as named fields, validated by a schema. Linkerd has fewer,
as annotations, validated by nothing. A typo in a Linkerd annotation is
silently ignored.
