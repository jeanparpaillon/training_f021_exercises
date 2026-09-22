# Step 3 — mTLS

**Slide:** Lab 2 — mTLS · **~10 min**

Nothing to apply — this step reads the state you reached in step 2. (The
overlay exists anyway, so `kubectl -n "$NS" apply -k lab2/step3-mtls` is safe
if you need to catch up.)

Traffic between meshed pods is now encrypted and mutually authenticated. You
did not configure it, distribute a certificate or change a URL.

## Prove it

```sh
linkerd -n "$NS" viz edges deployment
```

Every meshed edge shows `SECURED` with a client and server identity of the
form `<serviceaccount>.<namespace>.serviceaccount.identity.linkerd.cluster.local`.
That is why lab 1's base kept Bookinfo's four ServiceAccounts: in a mesh the
ServiceAccount stops being an RBAC detail and becomes the workload's identity.

Look at a request in flight:

```sh
linkerd -n "$NS" viz tap deploy/productpage | head -20
```

## Find the unencrypted edges

`loadgen` and `toolbox` were never injected, so their calls arrive at meshed
pods over plain HTTP:

```sh
linkerd -n "$NS" viz edges deployment | grep -i -v secured
```

A mesh secures the traffic it can see. Anything outside it — a job, a CronPod,
a client in another namespace, an operator — is still in clear text, and the
edges table is how you find out.

## What mTLS here does and does not mean

- It authenticates **workloads**, not users. `productpage` proves it is
  `bookinfo-productpage`; it says nothing about who is browsing.
- It is encryption in transit between pods. It is not encryption at rest, and
  it does not protect the pod's own loopback.
- By default it **encrypts** but does not **authorize**: every meshed workload
  may still call every other one. Restricting that is Linkerd's authorization
  policy (`Server` / `AuthorizationPolicy`) — the direct mesh equivalent of the
  NetworkPolicy work in exercise A, at L7 instead of L3.

## Questions

- Compare this with doing TLS in the application: who would have had to
  generate, distribute and rotate the certificates, and how often?
- `linkerd viz edges` shows an unsecured edge from `loadgen`. In a real
  cluster, which of your workloads would show up in that list?
