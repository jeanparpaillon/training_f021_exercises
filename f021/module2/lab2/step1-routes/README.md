# Step 1 — timeouts and retries per route

**Slide:** Lab 2 — timeouts and retries per route · **~15 min**

Lab 1 step 5 left two timeouts that nobody could change without a release:
`reviews` v2 waits 10 s for `ratings`, and `productpage` waits 3 s for
`reviews`, twice. This step sets them in the callers' proxies:

| Route | On | Timeout | Retries |
| --- | --- | --- | --- |
| `ratings-get` ([`ratings-routes.yaml`](ratings-routes.yaml)) | `GET /ratings/...` | 500 ms | 1, 250 ms per try, on 5xx |
| `ratings` (same file) | anything else | 500 ms | none |
| `reviews` ([`reviews-route.yaml`](reviews-route.yaml)) | everything | 1 s | none — productpage already retries |

The budget is the 2 s page from lab 1 step 5: productpage tries `reviews`
twice, 1 s each, and `reviews` gets its answer from `ratings`, or gives up
on it, within 500 ms.

```sh
kubectl -n "$NS" apply -k lab2/step1-routes
diff <(kubectl kustomize lab1/step6-fallback) <(kubectl kustomize lab2/step1-routes)
kubectl -n "$NS" get httproutes.policy.linkerd.io \
  -o custom-columns=NAME:.metadata.name,ACCEPTED:.status.parents[0].conditions[0].status
```

## Replay the black hole

The experiment from lab 1 step 5, unchanged:

```sh
kubectl -n "$NS" apply -f faults/ratings-blackhole.yaml
kubectl -n "$NS" scale deploy/ratings-v1 --replicas=0
```

```sh
kubectl -n "$NS" exec deploy/toolbox -- sh -c 'for i in 1 2 3 4 5 6 7 8; do
  time wget -qO /tmp/p http://productpage:9080/productpage
  grep -o "reviews-v[0-9]\|Ratings service is currently unavailable" /tmp/p | sort -u | tr "\n" " "; echo
  done' 2>&1 | grep -v "user\|sys"
```

With v2 and v3, the page now comes back in about half a second, without the
stars and with *"Ratings service is currently unavailable"*: the fallback
from lab 1 step 6, reached 20 times sooner. Run k6 once in this state and
compare p99 with your lab 1 step 5 number.

Then look at what the proxy did on each call:

```sh
lab2/route-stats.sh reviews-v2 ratings-get
```

For every **request** from the Java code, two **attempts**: the first cut
at 250 ms (`RESPONSE_HEADERS_TIMEOUT`), the retry cut when the whole 500 ms
ran out (`REQUEST_TIMEOUT`). The application saw one failure; the black
hole saw two requests.

Put ratings back:

```sh
kubectl -n "$NS" scale deploy/ratings-v1 --replicas=1
kubectl -n "$NS" delete -f faults/ratings-blackhole.yaml
```

## Why two routes for ratings

Retries are safe only on idempotent requests. `GET /ratings/0` is; `POST
/ratings/0` replaces the ratings of product 0, and sending it twice is not
harmless. The retry annotations apply to a whole route, so GET gets a route
of its own.

The GET route matches on `PathPrefix /ratings` **and** `method: GET`, not
on the method alone. Route precedence looks at the path first: a match
with no path counts as less specific than the catch-all's implicit
`PathPrefix /`. With `method: GET` alone, every GET would take the
catch-all route and silently go unretried. Nothing warns you: the route is
`Accepted`, and it just gets no traffic. `route-stats.sh` shows which
route the requests actually took.

## Retries across layers

`productpage` already retries `reviews` once, in its code. Add a mesh retry
on top and count. Keep the black hole on `ratings`, so that `reviews` v2
and v3 are slow:

```sh
kubectl -n "$NS" apply -f faults/ratings-blackhole.yaml
kubectl -n "$NS" scale deploy/ratings-v1 --replicas=0
kubectl -n "$NS" annotate httproute.policy.linkerd.io reviews --overwrite \
  retry.linkerd.io/http=5xx retry.linkerd.io/limit=2 retry.linkerd.io/timeout=300ms
```

Before you load the page, work it out on paper. How many attempts can one
page load make on `reviews` now, and how many on `ratings` behind them?
Then run the timing loop above again, followed by:

```sh
lab2/route-stats.sh productpage-v1 reviews
lab2/route-stats.sh reviews-v2 ratings-get
```

Look at the counts, and also at **which version** served each page. A
retry is a new balancing decision, and `reviews-v1` never calls `ratings`.

Remove the extra layer. `apply -k` will not do it: annotations added by
`kubectl annotate` are not part of what `apply` manages.

```sh
kubectl -n "$NS" annotate httproute.policy.linkerd.io reviews \
  retry.linkerd.io/http- retry.linkerd.io/limit- retry.linkerd.io/timeout-
kubectl -n "$NS" scale deploy/ratings-v1 --replicas=1
kubectl -n "$NS" delete -f faults/ratings-blackhole.yaml
```

## Questions

- `route-stats.sh` shows requests and attempts: what `linkerd viz routes`
  calls `EFFECTIVE_SUCCESS` and `ACTUAL_SUCCESS`. Why do you want both?
  What does a dashboard that only shows the first one hide from you?
- With the mesh retry on `reviews`, the pages looked better, served by v1.
  What did the retries really fix, and what did they cost `ratings`?
- An ingress that retries 3 times, productpage's 2 attempts, a mesh retry
  of 3 attempts on `reviews`: how many requests can one click send to a
  `reviews` that is already failing? And to `ratings` behind it?
- Which layer should keep the retry, and why the one closest to the
  failure?
- The annotations cap retries with a count (`retry.linkerd.io/limit`). The
  older ServiceProfile mechanism uses a **budget**: retries may add at most
  N % to the traffic. Which of the two protects a failing service better
  under load?
