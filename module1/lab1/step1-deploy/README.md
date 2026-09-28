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

An Ingress is only a routing rule. It needs an ingress controller to act on
it, and a path from your machine to that controller:

- **shared cluster**: both are in place
- **kind**: `make create ingress` from the repo root. `kind.yaml` maps host
  ports 80/443 into the node, and `ingress` installs ingress-nginx on them.

```sh
kubectl get ingressclass            # expect: nginx
```

The Ingress ships with a placeholder host. Open
[`ingress.yaml`](ingress.yaml) and replace it with your own:

```yaml
    - host: bookinfo.127.0.0.1.nip.io   # was bookinfo.CHANGEME.example
```

Any `*.127.0.0.1.nip.io` name resolves to `127.0.0.1`, so no `/etc/hosts`
editing. On the shared cluster, use the domain the trainer gives you, with
your namespace in the name so 13 Ingresses don't collide. Then re-apply:

```sh
kubectl -n "$NS" apply -k lab1/step1-deploy
kubectl -n "$NS" get ingress bookinfo                      # ADDRESS filled in
curl -sI http://bookinfo.127.0.0.1.nip.io/productpage      # HTTP/1.1 200 OK
curl -s  http://bookinfo.127.0.0.1.nip.io/api/v1/products  # the JSON API, same Ingress
```

No ingress controller at all? Skip the Ingress and port-forward instead:

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
