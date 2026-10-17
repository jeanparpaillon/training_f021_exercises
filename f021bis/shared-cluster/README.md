# The f021bis dev cluster

kind cluster `training-f021bis` on `srv2052563.hstgr.cloud`, same layout as
f021's shared cluster (Traefik as the only edge, one namespace and one ttyd
web console per trainee), with two differences:

- **trainees are cluster-admin** (module 1 is cluster administration);
- **each console can run its own kind clusters**: the console pod has a
  privileged `dind` sidecar, so `kind create cluster` works from the console.

| | |
| --- | --- |
| Web console | `https://srv2052563.hstgr.cloud/<name>/`, login `<name>`, password from `/root/users/consoles.txt` |
| Your namespace | `<name>`; you are `cluster-admin` anyway |
| Lab applications | `http://<app>.<name>.195.35.2.222.nip.io/` (plain HTTP, IngressClass `traefik`) |
| Storage | `local-path` (`StorageClass` `standard`) |

## In the console

```sh
kubectl get nodes                          # the shared cluster, context training-f021bis
kind create cluster --name lab             # your own cluster, in your console's Docker
kubectl get nodes                          # kind switched the context to kind-lab
kubectl config use-context training-f021bis
```

Multi-node and HA clusters work the same (`kind create cluster --config …`
with several `control-plane` / `worker` nodes); mind the size, see below.
Your home (`/root`) and your Docker data (images, kind nodes) are on volumes:
they survive a console restart, but kind clusters come back stopped —
`docker start $(docker ps -aq)` restarts their nodes.

## Files

| File | What it is |
| --- | --- |
| [`kind.yaml`](kind.yaml) | the cluster: API on `0.0.0.0:6443` with the host name in its SANs, NodePorts 30080/30443 on the server's 80/443 |
| [`traefik-values.yaml`](traefik-values.yaml) | full Helm values of the `traefik` release (TLS, Let's Encrypt) |
| [`base/`](base/) | namespace `consoles`, cluster-admin for trainees, HTTP→HTTPS redirect |
| [`templates/trainee.yaml.tmpl`](templates/trainee.yaml.tmpl) | everything per trainee: namespace, admin RoleBinding, console (ttyd + dind), PVCs, Service, Ingress |
| [`console/`](console/) | console image: ttyd, kubectl, kind, helm, docker CLI, ansible |
| [`bin/render`](bin/render) | `trainees/` from the trainee names (git-ignored) |
| [`bin/secrets`](bin/secrets) | runs on the server: console passwords from `/root/users/consoles.txt` |

The passwords never leave the server: `make render` only reads the first
column of `consoles.txt`, `make secrets` runs on the server.

## Trainer — building it

From this directory, with `ssh root@srv2052563.hstgr.cloud` working:

```sh
make sysctl        # inotify limits for the nested kind clusters, once per server
make create        # kind cluster on the server
make kubeconfig    # ./kubeconfig, cluster-admin, git-ignored
make edge          # Traefik
make image         # console image, built on the server, loaded into kind
make secrets       # console passwords
make apply         # render trainees/ + kubectl apply -k .
make check         # each console answers 401 (basic auth), dind is up
```

Day to day:

- **New trainee / new password**: edit `/root/users/consoles.txt` on the
  server (`<name> <password> <url>`), then `make secrets apply`. A changed
  password restarts that console.
- **Console image change**: edit `console/`, bump `CONSOLE_IMAGE` in the
  Makefile, `make image apply`.
- **Trainee removed**: `kubectl apply -k` does not prune; delete their
  objects by hand (`kubectl -n consoles delete all,pvc,ingress,sa,secret -l console=<name>`,
  `kubectl delete ns <name>`).

## Size and security

- The server has 4 CPUs and 15 GiB. A kind node takes about 1 CPU at start
  and 1–2 GiB; each console also pulls its own `kindest/node` (~1 GB). Count
  on one or two small clusters per trainee at the same time, not more.
- The `dind` sidecar is privileged, inside a kind node that is itself a
  privileged container: a trainee is root on the server if they want to be.
  That is already true of cluster-admin; do not run this cluster next to
  anything that matters. dockerd listens on a unix socket only (no TCP), so
  one console cannot drive another's Docker.
