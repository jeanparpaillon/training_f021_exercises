# Step 5 — traffic management

**Slide:** Lab 2 — traffic management · **~20 min**

Lab 1 step 3 ended on a question: *how would you send 10% of traffic to v3
with only the objects you have?* You could not. This is the answer.

```sh
kubectl -n "$NS" apply -k lab2/step5-traffic
kubectl -n "$NS" get httproute
```

## Watch the split

```sh
linkerd -n "$NS" viz stat deploy --from deploy/productpage
```

Roughly 90% of the calls now reach `reviews-v1`, 10% `reviews-v3`, and `v2`
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

The annotations on the HTTPRoute are the other half of what lab 1 step 6 was
missing:

```yaml
retry.linkerd.io/http: 5xx      # retry on server errors
retry.linkerd.io/limit: "2"     # at most twice
timeout.linkerd.io/request: 5s  # the whole request, retries included
```

See them work by making a backend fail:

```sh
kubectl -n "$NS" scale deploy/reviews-v3 --replicas=0
linkerd -n "$NS" viz routes deploy/productpage --to deploy/reviews -o wide
```

The `EFFECTIVE_SUCCESS` column stays high while `ACTUAL_SUCCESS` drops: the
proxy is absorbing the failures. That gap is exactly what a retry buys you —
and exactly what it hides, which is why you want both columns.

Tighten the timeout to `timeout.linkerd.io/response: 100ms` and watch the
same request start failing on purpose. Then put it back.

```sh
kubectl -n "$NS" scale deploy/reviews-v3 --replicas=1
```

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
