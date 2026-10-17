# Step 3 — Linkerd with Helm

**Slides:** Helm: a release is the unit of change · Lab 2 — installing Linkerd with Helm · **~20 min**

`linkerd install | kubectl apply` (F021) is quick; nothing records what was
installed, with which settings. Here: three Helm releases, a pinned chart
version each, values in [`../values/`](../values/), certificates you made.

## Prerequisites the chart does not bring

Linkerd needs the Gateway API CRDs and does not install them
(`installGatewayAPI: false` is the chart default): someone else owns them,
here you.

```sh
kubectl apply --server-side -f \
  "https://github.com/kubernetes-sigs/gateway-api/releases/download/$GATEWAY_API_VERSION/standard-install.yaml"
linkerd version --client --short       # LINKERD_CLI_FROM, from lab 0
linkerd check --pre
```

## Identity

A trust anchor (root CA) and an issuer (intermediate, one year) signed by
it. In production the anchor's key never comes near the cluster.

```sh
mkdir -p lab2/certs && cd lab2/certs
step certificate create root.linkerd.cluster.local ca.crt ca.key \
  --profile root-ca --no-password --insecure
step certificate create identity.linkerd.cluster.local issuer.crt issuer.key \
  --profile intermediate-ca --not-after 8760h --no-password --insecure \
  --ca ca.crt --ca-key ca.key
cd ../..
step certificate inspect lab2/certs/issuer.crt --short
```

## Three releases, in order

```sh
helm repo add linkerd-edge https://helm.linkerd.io/edge
helm search repo linkerd-edge/linkerd-control-plane --versions | head -5

helm install linkerd-crds linkerd-edge/linkerd-crds \
  -n linkerd --create-namespace --version "$LINKERD_FROM"

helm install linkerd-control-plane linkerd-edge/linkerd-control-plane \
  -n linkerd --version "$LINKERD_FROM" \
  -f lab2/values/control-plane.yaml \
  --set-file identityTrustAnchorsPEM=lab2/certs/ca.crt \
  --set-file identity.issuer.tls.crtPEM=lab2/certs/issuer.crt \
  --set-file identity.issuer.tls.keyPEM=lab2/certs/issuer.key \
  --wait --timeout 10m
linkerd check

helm install linkerd-viz linkerd-edge/linkerd-viz \
  -n linkerd-viz --create-namespace --version "$LINKERD_FROM" \
  -f lab2/values/viz.yaml --wait --timeout 10m
linkerd viz check
helm ls -A
```

If `helm.linkerd.io` times out: [`../../lab0/README.md`](../../lab0/README.md#if-helmlinkerdio-is-slow).

`linkerd check` prints `‼` lines about *latest versions* and *version
channel*: it asks versioncheck.linkerd.io, unreachable from the room. Ignore
those; the ones that matter are the `×`, and the *versions match* lines in
step 4.

## Mesh Bookinfo

[`kustomization.yaml`](kustomization.yaml) adds the injection annotation to
the namespace. Injection happens when a pod is **created**:

```sh
kubectl apply -k lab2/step3-install
kubectl -n bookinfo get pods                    # still 1/1: nothing changed
kubectl -n bookinfo rollout restart deploy
kubectl -n bookinfo rollout status deploy --timeout=5m
kubectl -n bookinfo get pods                    # 2/2: app + proxy
linkerd viz stat -n bookinfo deploy
```

## Questions

- What is in a Helm release, and where is it stored?
  (`kubectl -n linkerd get secret -l owner=helm`)
- The issuer certificate expires in a year. What happens to the mesh that
  day, and what would you put in place now?
- Why did the running pods not get a proxy when the namespace was annotated?
