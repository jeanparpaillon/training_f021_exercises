# The shared cluster

The cluster the room works on during the session. Attendees drive it from
their own machine with a local `kubectl`; nothing is installed for them
beyond that.

| | |
| --- | --- |
| API server | `https://srv2052563.hstgr.cloud:6443` |
| Kubernetes | 1.37 |
| Public URL | `https://srv2052563.hstgr.cloud/` (valid Let's Encrypt certificate): web consoles |
| Lab applications | `http://<app>.<namespace>.195.35.2.222.nip.io/` (plain HTTP) |
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

Each Ingress gets its own host name, with your namespace in it:

```
http://<app>.<namespace>.195.35.2.222.nip.io/<path>
```

e.g. `http://bookinfo.jean.195.35.2.222.nip.io/productpage`. nip.io is
wildcard DNS: `<anything>.195.35.2.222.nip.io` resolves to `195.35.2.222`,
the server, where Traefik picks your Ingress by host name. The same URL works
with `curl` from your web console and in the browser on your machine. Your
Ingress only needs:

```yaml
spec:
  ingressClassName: traefik
  rules:
    - host: <app>.<namespace>.195.35.2.222.nip.io
      http:
        paths:
          - path: /...
```

Lab 1 step 1 generates this Ingress for Bookinfo; see
[`../module1/lab1/step1-deploy/`](../module1/lab1/step1-deploy/).

Things to know:

- **Always put your namespace in the host name.** Two Ingresses with the
  same host and path fight over the same rule.
- **HTTP only.** Only the trainer's host names (`srv2052563.hstgr.cloud`,
  `chat.`, `registry.`) get a certificate; `*.nip.io` names are served on
  port 80 alone.
- **Not `127.0.0.1.nip.io`** as on kind: from your machine that is your
  machine, and from the web console it is the console pod itself.
- `https://srv2052563.hstgr.cloud/<namespace>/` is your web console. Path
  prefixes under that host are still possible with the `strip-ns-app`
  middleware (see [`traefik-strip-prefix.yaml`](traefik-strip-prefix.yaml)),
  but the application must then use relative links; prefer a host name.
- No Ingress, or something that is not HTTP? `kubectl -n "$NS" port-forward
  svc/<name> <port>` always works from your machine.

## Trainer — preparing the cluster

Each attendee gets a namespace, a `RoleBinding` to `ClusterRole/admin` in it,
and a console. Then, once for the room:

```sh
kubectl apply -f shared-cluster/traefik-strip-prefix.yaml
kubectl apply -f shared-cluster/trainee-read.yaml
kubectl apply -f shared-cluster/gatewayapi-rbac.yaml
```

[`gatewayapi-rbac.yaml`](gatewayapi-rbac.yaml) adds the Gateway API types
(HTTPRoute, GRPCRoute, ReferenceGrant, Gateway…) to the built-in `admin`,
`edit` and `view` roles by aggregation, which the Gateway API CRDs do not do
themselves. Needed from module 1 lab 2 step 5 on.

[`trainee-read.yaml`](trainee-read.yaml) lets attendees read the whole
cluster (every namespace, nodes, CRDs, APIServices…, never Secrets) from
kubectl, their console and Headlamp, which is what Headlamp's overview and
`linkerd check` / `linkerd viz check` need; writes stay limited to their own
namespace. A new attendee needs a Headlamp subject added there.

**Currently applied on top of all this:**
[`trainee-cluster-admin.yaml`](trainee-cluster-admin.yaml) makes every attendee
`cluster-admin` (certificate, console and Headlamp). It overrides the scoped
grants above; `kubectl delete -f shared-cluster/trainee-cluster-admin.yaml`
falls back to them.

After `linkerd viz install`, also:

```sh
kubectl apply -f shared-cluster/linkerd-viz-rbac.yaml
```

[`linkerd-viz-rbac.yaml`](linkerd-viz-rbac.yaml) lets attendees port-forward
into `linkerd-viz` (what `linkerd viz check | stat | top | edges` do) and
`linkerd viz tap` their own namespace, not the others'.

The dashboard is at `https://linkerd.srv2052563.hstgr.cloud/` (user
`trainee`, password from the trainer); see
[`linkerd-dashboard.yaml`](linkerd-dashboard.yaml) for the install flag and
the password Secret it needs.

Monitoring: kube-prometheus-stack in `monitoring`, installed with
[`kube-prometheus-stack-values.yaml`](kube-prometheus-stack-values.yaml)
(the commands are in its header). Grafana is at
`https://grafana.srv2052563.hstgr.cloud/` (user `admin`, password in Secret
`monitoring/grafana-admin`); Prometheus is at
`http://kube-prometheus-stack-prometheus.monitoring.svc:9090` in the cluster.
Prometheus picks up every ServiceMonitor, PodMonitor and PrometheusRule in any
namespace (no `release` label needed), Grafana every ConfigMap labelled
`grafana_dashboard: "1"`, and attendees get the `monitoring.coreos.com` types
through `admin`/`edit`/`view`. etcd, scheduler, controller-manager and
kube-proxy are not scraped: kind binds their metrics to 127.0.0.1.

Then, for the Linkerd metrics (`request_total`, `response_latency_ms`… with
`namespace` / `deployment` labels, for Grafana, PrometheusRules and Flagger):

```sh
kubectl apply --validate=false -f shared-cluster/linkerd-scrape.yaml
```

[`linkerd-scrape.yaml`](linkerd-scrape.yaml) holds Linkerd's own scrape jobs as
ScrapeConfigs. The linkerd-viz Prometheus stays, for `linkerd viz` and its
dashboard. (`--validate=false`: the OpenAPI download often times out over this
link; the server still validates.)

Edge setup (Traefik, TLS, port mapping) is described in
[Trainer — the edge](#trainer--the-edge) below.

Check it end to end with your own namespace:

```sh
NS=<trainer-namespace>
sed "s/CHANGEME/$NS/g" module1/lab1/step1-deploy/ingress.yaml.tmpl \
  > module1/lab1/step1-deploy/ingress.yaml
kubectl -n "$NS" apply -k module1/lab1/step1-deploy
curl -s -o /dev/null -w '%{http_code}\n' \
  "http://bookinfo.$NS.195.35.2.222.nip.io/productpage"         # 200
```

## Trainer — the edge

Traefik is the only HTTP layer on the server: it terminates TLS, gets the
Let's Encrypt certificates (ACME HTTP-01) and routes on the Host header.
Nothing runs in front of it. The kind node's docker port mapping is the whole
"edge":

```
client ─► 195.35.2.222:80/443        docker DNAT on the host (port mapping of the kind node)
        ─► 172.18.0.2:30080/30443    NodePort of Service traefik (kube-proxy DNAT, policy Local)
        ─► Traefik pod :8000/:8443   TLS + routing                traefik-values.yaml
        ─► backend pod IP            straight from the EndpointSlices, no ClusterIP
```

No proxy, so Traefik sees the real client address (`externalTrafficPolicy:
Local` stops kube-proxy from SNATing it away).

| File | What it is |
| --- | --- |
| [`traefik-values.yaml`](traefik-values.yaml) | the full Helm values of the `traefik` release: ACME resolver `le`, `web` as default entrypoint, `acme.json` on a PVC |
| [`traefik-https.yaml`](traefik-https.yaml) | HTTP→HTTPS redirect for the hosts that have a certificate |
| [`traefik-strip-prefix.yaml`](traefik-strip-prefix.yaml) | path-prefix middleware for attendees |

How a route ends up on HTTP or HTTPS:

- **No annotation → HTTP only.** `web` is the default entrypoint, so routers
  that name none attach to port 80 alone. That covers every attendee Ingress
  (`*.nip.io`), and is what keeps Traefik from asking Let's Encrypt for nip.io
  names, which share one rate limit with the whole internet.
- **`traefik.ingress.kubernetes.io/router.entrypoints: websecure` → HTTPS.** TLS
  and the `le` resolver are set on the `websecure` entrypoint itself, so that one
  annotation is enough; Traefik orders the certificate for the Ingress host on
  first sight. The host must also be added to `traefik-https.yaml`, or plain
  HTTP on it gets a 404 instead of a redirect.

That annotation goes on the `consoles/*`, `default/hello`,
`headlamp/headlamp`, `registry/registry` and `rocketchat` Ingresses. The
Rocket.Chat one belongs to its Helm release: set it with
`--set-string 'ingress.annotations.traefik\.ingress\.kubernetes\.io/router\.entrypoints=websecure'`,
or the next `helm upgrade` drops it.

**IPv4 only.** The host names have AAAA records (`2a02:4780:28:966e::1`), but
the cluster is single-stack IPv4: kube-proxy programs no IPv6 NodePort, so the
port mapping is bound on `0.0.0.0` only and IPv6 connections to 80/443 are
refused. Browsers fall back to IPv4, and so does Let's Encrypt (it retries
over IPv4 when the IPv6 connection fails, not when it gets an HTTP error).
Serving IPv6 needs a dual-stack kind cluster, i.e. a rebuild.

### Migrating from the host nginx

Until this is done, the server runs the previous layout: nginx with
certbot-managed vhosts in `/etc/nginx/sites-enabled/` (`k8s`, `k8s-chat`,
`k8s-registry`, `k8s-labs`) terminating TLS and passing plain HTTP to
`127.0.0.1:8080`, which the kind node publishes for NodePort 30080.

kind port mappings cannot be changed on a running cluster, and recreating it
loses everything in it (consoles' homes, Rocket.Chat's MongoDB, the registry's
images: the `local-path` volumes live in the node's docker volume, and the
consoles setup is not in this repo). Instead, the mapping is edited in the
node container's `hostconfig.json` while dockerd is stopped, which ends up in
the same state as a cluster created with the right `extraPortMappings`.

Do it outside session hours: from step 2 the consoles are unreachable until
step 4 is finished, and step 4 restarts the whole cluster (a few minutes).

From your machine:

```sh
S=root@srv2052563.hstgr.cloud
kubectl get ingress -A -o yaml > ingress-backup.yaml
```

**1. Backups** (on the server):

```sh
D=/var/lib/docker/containers/$(docker inspect -f '{{.Id}}' training-control-plane)
cp "$D/hostconfig.json" /root/hostconfig.json.bak
tar czf /root/nginx-letsencrypt.tgz /etc/nginx /etc/letsencrypt
```

**2. Traefik and routes** (from your machine):

```sh
scp shared-cluster/traefik-values.yaml $S:/root/
ssh $S helm upgrade traefik traefik/traefik -n traefik --version 41.7.1 -f /root/traefik-values.yaml
kubectl -n traefik rollout status deploy/traefik

kubectl apply -f shared-cluster/traefik-https.yaml
A=traefik.ingress.kubernetes.io/router.entrypoints=websecure
kubectl -n consoles annotate ingress --all "$A"
kubectl -n default  annotate ingress hello     "$A"
kubectl -n headlamp annotate ingress headlamp  "$A"
kubectl -n registry annotate ingress registry  "$A"
ssh $S "helm upgrade rocketchat rocketchat/rocketchat -n rocketchat --version 7.0.2 --reuse-values \
  --set-string 'ingress.annotations.traefik\.ingress\.kubernetes\.io/router\.entrypoints=websecure'"
```

The certificates may already be issued at this point: Let's Encrypt follows
the old nginx's HTTP→HTTPS redirect, and nginx passes the challenge to
Traefik's `web` entrypoint.

**3. Stop nginx** (on the server). Disabled, not removed, for the rollback:

```sh
systemctl disable --now nginx
```

**4. Publish the NodePorts on 80/443** (on the server):

```sh
D=/var/lib/docker/containers/$(docker inspect -f '{{.Id}}' training-control-plane)
systemctl stop docker.socket docker        # stops the kind node with it
python3 - "$D/hostconfig.json" <<'EOF'
import json, sys
p = sys.argv[1]
h = json.load(open(p))
h["PortBindings"]["30080/tcp"] = [{"HostIp": "0.0.0.0", "HostPort": "80"}]
h["PortBindings"]["30443/tcp"] = [{"HostIp": "0.0.0.0", "HostPort": "443"}]
json.dump(h, open(p, "w"))
EOF
systemctl start docker
docker start training-control-plane        # restart policy is on-failure: not started by dockerd
docker port training-control-plane         # 30080 -> 0.0.0.0:80, 30443 -> 0.0.0.0:443, 6443
docker inspect -f '{{.NetworkSettings.Networks.kind.IPAddress}}' training-control-plane   # still 172.18.0.2
```

The node must come back on `172.18.0.2`: the API server certificate and the
kubelet are bound to it. It does when it is the only container on the `kind`
network, which is the case here.

**5. Check** (from your machine, once `kubectl get nodes` answers again):

```sh
kubectl get nodes                                       # Ready
kubectl get pods -A | grep -v -E 'Running|Completed'    # only the header, after a minute or two
kubectl -n traefik logs deploy/traefik | grep -i -E 'acme|error'
curl -sv https://srv2052563.hstgr.cloud/ -o /dev/null 2>&1 | grep -E 'issuer|HTTP/'   # Let's Encrypt
curl -sI http://chat.srv2052563.hstgr.cloud/ | head -1                                 # 301
curl -s -o /dev/null -w '%{http_code}\n' "http://bookinfo.$NS.195.35.2.222.nip.io/productpage"  # 200
```

Then by hand: a console opens and its terminal works (WebSocket), a
`docker push` to the registry goes through, Rocket.Chat loads, and a
`curl` to a `*.nip.io` URL from a console works (it goes out to the public IP
and back in through the same mapping).

**6. Clean up**, once it has run for a few days (on the server):

```sh
for c in srv2052563.hstgr.cloud chat.srv2052563.hstgr.cloud registry.srv2052563.hstgr.cloud; do
  certbot delete --non-interactive --cert-name $c
done
apt purge nginx nginx-common python3-certbot-nginx
```

**Rollback** (before step 6). On the server:

```sh
D=/var/lib/docker/containers/$(docker inspect -f '{{.Id}}' training-control-plane)
systemctl stop docker.socket docker
cp /root/hostconfig.json.bak "$D/hostconfig.json"
systemctl start docker && docker start training-control-plane
systemctl enable --now nginx
```

then from your machine remove the opt-in, so the routes match on `web` again
behind nginx:

```sh
A=traefik.ingress.kubernetes.io/router.entrypoints-
kubectl -n consoles annotate ingress --all "$A"
kubectl -n default  annotate ingress hello     "$A"
kubectl -n headlamp annotate ingress headlamp  "$A"
kubectl -n registry annotate ingress registry  "$A"
ssh $S "helm rollback rocketchat -n rocketchat"
```

### Next rebuild

When the cluster is recreated anyway, put the mapping in the server's kind
config directly, so the `hostconfig.json` edit is not needed:

```yaml
extraPortMappings:
  - { containerPort: 30080, hostPort: 80,  listenAddress: "0.0.0.0" }
  - { containerPort: 30443, hostPort: 443, listenAddress: "0.0.0.0" }
```

alongside the API server on `0.0.0.0:6443`. That is also the time to go
dual-stack (`networking.ipFamily: dual`) if IPv6 matters.

### What the module READMEs assume, and what is actually there

The module READMEs say *"on the shared cluster the trainer has installed
it"* for a number of add-ons. Today the cluster has **Traefik, Linkerd + viz and kube-prometheus-stack**, and a **single node**. Before each day:

| Needed by | Install | Status |
| --- | --- | --- |
| module 1 lab 2, every day after | Linkerd + linkerd-viz | **installed** |
| module 1 lab 2 step 6 (demo) | Istio | not installed |
| module 2 lab 1 step 4, module 3 lab 2 step 8 | several worker nodes with `topology.kubernetes.io/zone` labels | **single node** |
| module 2 lab 2 | Chaos Mesh, with rights on Chaos objects for `admin` | not installed |
| module 3 | metrics-server, VPA, Prometheus Adapter, KEDA, OpenCost | not installed |
| module 3, module 5 | kube-prometheus-stack | **installed**, with Linkerd metrics |
| module 4 | Kyverno / Pod Security labels, audit log, Vault | not installed |
| module 4 lab 2 step 4 | a CNI that enforces NetworkPolicy, and policies that let the `traefik` namespace reach `productpage` | to check |
