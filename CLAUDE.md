# training_f021_exercises

This repo hosts the exercises for **training_f021** (Advanced Kubernetes training).
The training material itself lives in the sibling repo `../training_f021`.

Each module contains exercises for corresponding module in `training_f021/slides/pages`

Exercises rely on a Kubernetes cluster, either the **shared cluster** of the session
(see `shared-cluster/README.md`: `srv2052563.hstgr.cloud`, one namespace per attendee,
driven from a local `kubectl`) or one deployed locally with `kind`
(https://kind.sigs.k8s.io/) (or `k3s` if machine allows it).

## Accessing the shared cluster

It is a single-node `kind` cluster named `training` (node `training-control-plane`),
running in Docker on the server.

- **kubectl from this machine**: the default kubeconfig has context `hstgr` (user
  `hstgr-admin`, API `https://srv2052563.hstgr.cloud:6443`), cluster-admin.
  `kubectl get nodes` works as is.
- **The server itself**: `ssh root@srv2052563.hstgr.cloud`. `kind` and a root
  kubeconfig are there too, so `ssh root@srv2052563.hstgr.cloud kubectl …` also works.
  Helm releases are managed from there (`helm` is only installed on the server).

## Edge: Traefik only, no host nginx

Traefik (Helm release `traefik`, values in `shared-cluster/traefik-values.yaml`, the
full set: never `--reuse-values`) terminates TLS and gets Let's Encrypt certificates
itself (resolver `le`, HTTP-01, `acme.json` on a PVC). Nothing runs in front of it: the
kind node container publishes NodePorts 30080/30443 on `0.0.0.0:80/443`, and the
Service has `externalTrafficPolicy: Local` so Traefik sees real client addresses. The
migration runbook and rollback are in `shared-cluster/README.md` ("Trainer — the
edge"). Until it has been run, the server still has nginx with certbot vhosts in
`/etc/nginx/sites-enabled/` terminating TLS and passing to `127.0.0.1:8080`; check
`docker port training-control-plane` before assuming either state.

Rules that are easy to break:

- **The port mapping was edited in the node's `hostconfig.json`**, not set by the kind
  config, because kind mappings are fixed at creation and a rebuild loses everything
  (the consoles setup is not in this repo). `docker rm`/`kind delete` loses it too.
- **IPv4 only.** The host names have AAAA records, but the cluster is single-stack:
  kube-proxy programs no IPv6 NodePort, so binding the mapping on `::` would DNAT to the
  node's IPv6 address and hit nothing. IPv6 needs a dual-stack rebuild.
- **`web` is the default entrypoint** (`ports.web.asDefault`). An Ingress with no
  entrypoint annotation is HTTP only. Never make `websecure` a default, nor put the
  certResolver on a router that would catch `*.nip.io` names: Traefik would ask Let's
  Encrypt for every attendee host, and nip.io's rate limit is shared with the internet.
- **HTTPS is opt-in** with `traefik.ingress.kubernetes.io/router.entrypoints: websecure`
  (TLS and resolver come from the entrypoint). A new HTTPS host also needs adding to
  the redirect router in `shared-cluster/traefik-https.yaml`.
- **Rocket.Chat's Ingress belongs to its Helm release**: its annotation is set through
  `ingress.annotations` values, not `kubectl annotate`, or the next upgrade drops it.
- **Proxy settings are Traefik's**: `websecure` has `readTimeout: 0` for registry
  pushes (v3 defaults to 60 s).

Namespaces: one per attendee (abdelatif, ahlem, feriel, fouzia, imad, jean, milissa,
yahia), plus `consoles` (the attendees' ttyd web consoles) and `traefik`. Attendees run
their commands, `curl` included, from their web console, i.e. from a pod: there
`127.0.0.1` is the pod itself.

## Exposing over HTTP

Anything an attendee exposes over HTTP must work on both clusters. On the shared
cluster an Ingress uses `ingressClassName: traefik` and a host with the namespace in it,
`<app>.<ns>.195.35.2.222.nip.io`, and no entrypoint annotation (HTTP only): nip.io
resolves it to the server, so it works from the console and from a browser with no
`--resolve`. HTTPS only covers the trainer's hosts (`srv2052563.hstgr.cloud` with the
consoles at `/<ns>/`, `chat.`, `registry.`). On kind the host is `<app>.<ns>.127.0.0.1.nip.io` with
`ingressClassName: nginx`. Files that carry the namespace are rendered from a `.tmpl`
with `sed "s/CHANGEME/$NS/g"` and git-ignored.
