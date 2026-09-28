# Step 5 — timeouts in the client

**Slide:** Lab 1 — timeouts in the client · **~10 min**

Nothing to apply: the overlay is step 4 unchanged, and exists so that
`kubectl apply -k lab1/step5-timeouts` still lands you in the right state.

The Bookinfo images hardcode their timeouts. They cannot be changed from a
manifest, so this step **observes** them:

| Caller → callee | Timeout | Retries | Where |
| --- | --- | --- | --- |
| productpage → details | 3 s | none | `productpage.py` |
| productpage → reviews | 3 s | 1 (so up to 6 s) | `productpage.py`, the `range(2)` loop |
| reviews v2 → ratings | 10 s | none | reviews, Java (JAX-RS client) |
| reviews v3 → ratings | 2.5 s | none | same code, different value |

Read the Python ones yourself:

```sh
kubectl -n "$NS" exec deploy/productpage-v1 -c productpage -- \
  grep -n -B2 -A2 "timeout=" productpage.py
```

## A dead dependency

```sh
kubectl -n "$NS" scale deploy/reviews-v1 deploy/reviews-v2 deploy/reviews-v3 --replicas=0
```

Time a few page loads in a row, one second apart:

```sh
kubectl -n "$NS" exec deploy/toolbox -- sh -c \
  'for i in 1 2 3 4 5 6; do time wget -qO /dev/null http://productpage:9080/productpage; sleep 1; done' 2>&1 | grep real
```

Compare with a caller outside the mesh (`toolbox` is not injected):

```sh
kubectl -n "$NS" exec deploy/toolbox -- sh -c 'time wget -qO- http://reviews:9080/reviews/0'
```

Outside the mesh, a Service with no endpoints fails at once: kube-proxy
rejects the connection. Inside the mesh, productpage's proxy first **holds**
the request for up to 3 s, waiting for an endpoint to show up. Then it goes
into *fail-fast* and answers `503` at once for a while:

```sh
kubectl -n "$NS" logs deploy/productpage-v1 -c linkerd-proxy --tail=5
```

Friendly to a pod that is only restarting, costly to a service that is
really gone.

```sh
kubectl -n "$NS" apply -k lab1/step5-timeouts     # reviews back to 2 replicas each
```

## A slow dependency

The black hole again, with nothing else broken this time:

```sh
kubectl -n "$NS" apply -f faults/ratings-blackhole.yaml
kubectl -n "$NS" scale deploy/ratings-v1 --replicas=0
```

Time each `reviews` version on its own, straight to a pod:

```sh
for v in v1 v2 v3; do
  IP=$(kubectl -n "$NS" get pod -l app=reviews,version=$v -o jsonpath='{.items[0].status.podIP}')
  echo "== $v"; kubectl -n "$NS" exec deploy/toolbox -- sh -c "time wget -qO /dev/null http://$IP:9080/reviews/0" 2>&1 | grep real
done
```

Then the whole page, a dozen times, noting the time and which `reviews`
served it:

```sh
kubectl -n "$NS" exec deploy/toolbox -- sh -c 'for i in $(seq 1 12); do
  S=$(date +%s); wget -qO /tmp/p http://productpage:9080/productpage; E=$(date +%s)
  echo "$((E-S))s $(grep -o "reviews-v[0-9]" /tmp/p | head -1) $(grep -c "currently unavailable" /tmp/p)"; done'
```

Run k6 once in this state and look at p99.

## Put ratings back

```sh
kubectl -n "$NS" scale deploy/ratings-v1 --replicas=1
kubectl -n "$NS" delete -f faults/ratings-blackhole.yaml
```

## Questions

- Why is a slow dependency worse than a dead one? Compare what each did to
  p99 and to the number of busy gunicorn workers.
- `productpage` gives up after 3 s (6 s with its retry), while `reviews` v2
  waits 10 s for `ratings`. Which of these timeouts is useless? What should
  the values be for a **2 s** page budget, all hops and retries included?
- Some page loads took ~3 s and still showed reviews from v1. Follow the
  request: what happened to the first attempt?
- Where would you set these in the Java service (Resilience4j
  `TimeLimiter`, or the JAX-RS client properties) and in the Python one
  (`requests`)? How many teams, and how many releases, does changing them
  take? Lab 2 does it in the mesh, without touching the code.
