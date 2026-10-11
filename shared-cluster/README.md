# The shared cluster

The cluster the room works on during the session. Attendees drive it from
their own machine with a local `kubectl`; nothing is installed for them
beyond that.

| | |
| --- | --- |
| API server | `https://srv2052563.hstgr.cloud:6443` |
| Kubernetes | 1.37 |
| Public URL | `https://srv2052563.hstgr.cloud/` (valid Let's Encrypt certificate) |
| Ingress controller | Traefik, IngressClass `traefik` (the default one) |
| Storage | `local-path` (`StorageClass` `standard`) |
| Your namespace | your first name, lower case — you are `admin` in it, and only in it |
| Web console | `https://srv2052563.hstgr.cloud/<namespace>/` (password from the trainer) |

## Connect

The trainer gives you a kubeconfig. Then:

```sh
export KUBECONFIG=~/Downloads/f021-<you>.kubeconfig    # or merge it into ~/.kube/config
export NS=<you>                                        # e.g. NS=jean
kubectl config set-context --current --namespace="$NS"
kubectl auth can-i create deployments -n "$NS"         # yes
kubectl version                                        # client within one minor of 1.37
```

Use a `kubectl` from 1.36 to 1.38: older clients work for these labs but warn
about the version skew on every call. `kubectl kustomize` is built in.

Everything else in the labs is `kubectl -n "$NS" ...`, and works the same here
as on kind.

## Reaching your services

There is **one** host name with a certificate, so Ingresses are told apart by
path, not by host:

```
https://srv2052563.hstgr.cloud/<namespace>/<app>/<path>
```

e.g. `https://srv2052563.hstgr.cloud/jean/bookinfo/productpage`. Traefik
strips `/<namespace>/<app>` before passing the request on, so the
application still sees `/productpage`. You only need two things in your
Ingress:

```yaml
metadata:
  annotations:
    # strips /<namespace>/<app>; provided by the trainer, shared by everybody
    traefik.ingress.kubernetes.io/router.middlewares: traefik-strip-ns-app@kubernetescrd
spec:
  ingressClassName: traefik
  rules:
    - host: srv2052563.hstgr.cloud
      http:
        paths:
          - path: /<namespace>/<app>/...
```

Lab 1 step 1 generates this Ingress for Bookinfo; see
[`../module1/lab1/step1-deploy/`](../module1/lab1/step1-deploy/).

Things to know:

- **Always put your namespace first in the path.** `/<namespace>/` itself is
  your web console; anything longer wins over it in Traefik, so
  `/<namespace>/bookinfo/...` and the console coexist.
- **The application must use relative links** to work under a prefix. Bookinfo
  mostly does: styles, login and logout work. Its logo
  (`/static/img/izzy.png`) and the links of its `/` index page are absolute,
  so the logo is missing in the browser and you start from `/productpage`.
- Other subdomains of `srv2052563.hstgr.cloud` do resolve to the cluster, but
  the certificate does not cover them: `curl -k` only.
- No Ingress, or something that is not HTTP? `kubectl -n "$NS" port-forward
  svc/<name> <port>` always works from your machine.

## Trainer — preparing the cluster

Each attendee gets a namespace, a `RoleBinding` to `ClusterRole/admin` in it,
and a console. Then, once for the room:

```sh
kubectl apply -f shared-cluster/traefik-strip-prefix.yaml
```

Check it end to end with your own namespace:

```sh
NS=<trainer-namespace>
kubectl -n "$NS" apply -k module1/lab1/step1-deploy
curl -s -o /dev/null -w '%{http_code}\n' \
  "https://srv2052563.hstgr.cloud/$NS/bookinfo/productpage"     # 200
```

### What the module READMEs assume, and what is actually there

The module READMEs say *"on the shared cluster the trainer has installed
it"* for a number of add-ons. Today the cluster has **Traefik and nothing
else**, and a **single node**. Before each day:

| Needed by | Install | Status |
| --- | --- | --- |
| module 1 lab 2, every day after | Linkerd + linkerd-viz | not installed |
| module 1 lab 2 step 6 (demo) | Istio | not installed |
| module 2 lab 1 step 4, module 3 lab 2 step 8 | several worker nodes with `topology.kubernetes.io/zone` labels | **single node** |
| module 2 lab 2 | Chaos Mesh, with rights on Chaos objects for `admin` | not installed |
| module 3 | metrics-server, VPA, Prometheus (+ adapter), KEDA, OpenCost | not installed |
| module 4 | Kyverno / Pod Security labels, audit log, Vault | not installed |
| module 4 lab 2 step 4 | a CNI that enforces NetworkPolicy, and policies that let the `traefik` namespace reach `productpage` | to check |
