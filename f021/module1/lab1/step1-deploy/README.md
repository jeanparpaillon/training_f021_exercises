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

## Generate your Ingress

The kustomization includes `ingress.yaml`, which is **not** in git: every
attendee needs their own, otherwise 13 Ingresses fight over the same rule.
Render it once from the template for your cluster — this is the only file in
the whole course that carries your namespace:

```sh
export NS=<your-namespace>

# shared cluster: Traefik, one host name, your namespace in the path
sed "s/CHANGEME/$NS/g" lab1/step1-deploy/ingress.yaml.tmpl > lab1/step1-deploy/ingress.yaml

# kind: ingress-nginx, a nip.io host name with your namespace in it
sed "s/CHANGEME/$NS/g" lab1/step1-deploy/ingress-kind.yaml.tmpl > lab1/step1-deploy/ingress.yaml
```

Every later step and module builds on this one, so they all pick it up.

## Deploy

```sh
kubectl -n "$NS" apply -k lab1/step1-deploy
kubectl -n "$NS" rollout status deploy/productpage-v1
kubectl -n "$NS" get pods
```

Six pods: `details-v1`, `ratings-v1`, `reviews-v1/v2/v3`, `productpage-v1`.
`reviews` is Java and takes a while to start; wait for all six to be `Running`.

## Reach it

An Ingress is only a routing rule. It needs an ingress controller to act on
it, and a path from your machine to that controller.

**Shared cluster** — both are in place: Traefik, behind
`https://srv2052563.hstgr.cloud` (see [`../../../shared-cluster/`](../../../shared-cluster/)).

```sh
kubectl get ingressclass                   # expect: traefik (default)
kubectl -n "$NS" get ingress bookinfo
curl -s -o /dev/null -w '%{http_code}\n' "https://srv2052563.hstgr.cloud/$NS/bookinfo/productpage"   # 200
curl -s "https://srv2052563.hstgr.cloud/$NS/bookinfo/api/v1/products"   # the JSON API, same Ingress
```

then open `https://srv2052563.hstgr.cloud/<your-namespace>/bookinfo/productpage`
in a browser. Look at the Ingress: every path starts with
`/<your-namespace>/bookinfo`, and the `router.middlewares` annotation points at
a Traefik middleware that strips that prefix, so `productpage` still receives
`/productpage`. `/<your-namespace>/` alone is your web console.

**kind** — `make create ingress` from the repo root. `kind.yaml` maps host
ports 80/443 into the node, and `ingress` installs ingress-nginx on them.

```sh
kubectl get ingressclass                   # expect: nginx
kubectl -n "$NS" get ingress bookinfo      # ADDRESS filled in
curl -sI "http://bookinfo.$NS.127.0.0.1.nip.io/productpage"       # HTTP/1.1 200 OK
curl -s  "http://bookinfo.$NS.127.0.0.1.nip.io/api/v1/products"   # the JSON API
```

Any `*.127.0.0.1.nip.io` name resolves to `127.0.0.1`, so no `/etc/hosts`
editing.

**No ingress controller at all**, or want to bypass it? Port-forward, from
your machine, to the Service:

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
