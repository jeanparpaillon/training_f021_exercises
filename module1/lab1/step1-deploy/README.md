# Step 1 — deploy Bookinfo

**Slide:** Lab 1 — deploy Bookinfo · **~15 min**

Four services, no mesh, no resilience, nothing production-shaped yet. This is
the application the rest of the day works on.

```
                       +--------------+
   user --- Ingress -->| productpage  |
                       +--------------+
                          |        |
                          v        v
                    +---------+  +---------+     +---------+
                    | details |  | reviews |---->| ratings |
                    +---------+  +---------+     +---------+
                                  v1  v2  v3
```

`reviews` exists in three versions behind a single Service: v1 shows no
ratings, v2 black stars, v3 red stars. You can therefore see which pod served
a request just by looking at the page.

## Deploy

```sh
export NS=<your-namespace>
kubectl -n "$NS" apply -k lab1/step1-deploy
kubectl -n "$NS" rollout status deploy/productpage-v1
kubectl -n "$NS" get pods
```

Six pods: `details-v1`, `ratings-v1`, `reviews-v1/v2/v3`, `productpage-v1`.

## Reach it

The Ingress ships with a placeholder host, because on a shared cluster 13
identical Ingresses would collide. Give it your own:

```sh
kubectl -n "$NS" patch ingress bookinfo --type=json \
  -p="[{\"op\":\"replace\",\"path\":\"/spec/rules/0/host\",\"value\":\"bookinfo-$NS.$BASE_DOMAIN\"}]"
curl -sI "http://bookinfo-$NS.$BASE_DOMAIN/productpage"
```

On a local `kind` cluster with no ingress controller, skip the Ingress and
port-forward instead:

```sh
kubectl -n "$NS" port-forward svc/productpage 9080:9080
# then open http://localhost:9080/productpage
```

## Look at what you deployed

```sh
kubectl -n "$NS" get deploy,svc
kubectl -n "$NS" get endpoints reviews
```

## Questions to answer before moving on

- `kubectl get endpoints reviews` lists three addresses. Which Deployments are
  they, and why does one Service cover three of them?
- Reload `/productpage` a dozen times. What changes, and what does that tell
  you about where the request went?
- Nothing in these manifests says in which order the services start. What
  happens today if `details` is slower to boot than `productpage`?
