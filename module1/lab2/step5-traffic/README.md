# Step 5 — traffic management

**Slide:** Lab 2 — traffic management · **~20 min**

Lab 1 step 3 ended on a question: *how would you send 10% of traffic to v3
with only the objects you have?* You could not. This is the answer.

```sh
kubectl -n "$NS" apply -k lab2/step5-traffic
kubectl -n "$NS" get httproutes.policy.linkerd.io
```

Use the full resource name: two CRDs are called `HTTPRoute` (Linkerd's
`policy.linkerd.io` and the Gateway API's `gateway.networking.k8s.io`), and
the short `kubectl get httproute` resolves to the Gateway API one — it
answers "No resources found" while the route is right there.

## Watch the split

```sh
linkerd -n "$NS" viz stat-outbound deploy/productpage-v1
kubectl -n "$NS" exec deploy/toolbox -- sh -c \
  'for i in $(seq 1 60); do wget -qO- http://productpage:9080/productpage \
     | grep -o "reviews-v[0-9]" | head -1; done | sort | uniq -c'
```

`stat-outbound` now shows the route by name (`reviews-canary`, type
`HTTPRoute`) with one line per backend.

Give it a minute. The stats cover the last minute (`-t` changes that), so
right after `apply` you still see a `[default]` row for `reviews:9080` — the
traffic from before the route existed. And 10% of loadgen's ~1 req/s is
~0.1 req/s: `reviews-v3` can read `0.00` / `NaN%` (0 requests out of 0) for a
while. The counting loop below drives enough traffic to see the split at once. Roughly 90% of the calls now reach `reviews-v1`, 10% `reviews-v3`, and `v2`
drops out entirely. Reload the page a few dozen times: mostly no stars,
occasionally red ones.

Before the route existed, the split was ~33/33/33 — not because anyone chose
it, but because there were three endpoints. **With a route, the split is what
you declare.**

Shift it live, with no rollout and no restart:

```sh
kubectl -n "$NS" patch httproute reviews-canary --type=json \
  -p='[{"op":"replace","path":"/spec/rules/0/backendRefs/0/weight","value":50},
       {"op":"replace","path":"/spec/rules/0/backendRefs/1/weight","value":50}]'
```

That is a canary release: the same manifest, a different number, re-applied by
CI as the error rate stays flat. Day 5 wires this to GitOps.

## Why the extra Services

`reviews` selects `app: reviews` and covers all three versions, so it cannot
address v3 alone. `reviews-versioned-services.yaml` adds one Service per
version to use as `backendRefs`. Istio does the same job with `subsets` in a
DestinationRule and no extra Services — compare with step 6.

## Retries and timeouts

The annotations on the HTTPRoute add what plain Kubernetes Services cannot do
at all:

```yaml
retry.linkerd.io/http: 5xx      # retry on server errors
retry.linkerd.io/limit: "2"     # at most twice
timeout.linkerd.io/request: 5s  # the whole request, retries included
```

`stat-outbound` has a `TIMEOUTS` and a `RETRIES` column for exactly these.

See the timeout work by making it absurdly tight:

```sh
kubectl -n "$NS" annotate httproutes.policy.linkerd.io reviews-canary \
  timeout.linkerd.io/request=1ms --overwrite
```

Reload the page: *Error fetching product reviews*. After a scrape interval,
`stat-outbound` shows the route's `SUCCESS` collapsing and `TIMEOUTS`
climbing to ~90%, per backend. `RETRIES` stays at 0%: a timeout is not a
`5xx`, and this route only retries `5xx`. Put it back:

```sh
kubectl -n "$NS" annotate httproutes.policy.linkerd.io reviews-canary \
  timeout.linkerd.io/request=5s --overwrite
```

Scaling `reviews-v3` to 0 is *not* a way to see retries: with no endpoints
left, Linkerd simply sends that backend's share to `reviews-v1` — the page
never fails and `RETRIES` stays at 0%. Useful in itself (a canary that dies
takes no traffic down with it), but it means Bookinfo has no easy way to
produce the `5xx` a retry needs. Day 2 injects faults properly.

## Two things to say out loud

- **Retries are only safe on idempotent requests.** `GET /reviews` is. A POST
  that charges a card is not. Linkerd retries whatever you tell it to; the
  safety judgement is yours.
- **Retries amplify load.** A service already failing under load now gets up
  to 3× the requests. Linkerd caps this with a retry budget rather than a
  plain multiplier — day 2 goes into what that means under a real incident.

## Questions

- You set 90/10. What signal tells you it is safe to go to 50/50, and where
  would that signal come from?
- The retry sits in productpage's proxy, so the retried call goes back through
  the same route. What happens when *every* service in a chain retries twice?
