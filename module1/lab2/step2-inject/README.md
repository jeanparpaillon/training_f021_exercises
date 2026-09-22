# Step 2 — inject the namespace

**Slide:** Lab 2 — inject the namespace · **~10 min**

The mesh gets into the application through an annotation and a restart. No
application code, no image rebuild, no Dockerfile.

```sh
kubectl -n "$NS" apply -k lab2/step2-inject
kubectl -n "$NS" rollout status deploy/productpage-v1
```

This overlay starts from the end of lab 1 (step 5, production-shaped), so it
also catches up anyone who fell behind.

## What changed

```sh
kubectl -n "$NS" get pods
kubectl -n "$NS" get pod -l app=productpage \
  -o jsonpath='{range .items[0].spec.initContainers[*]}{.name}{"\n"}{end}'
kubectl -n "$NS" get pod -l app=productpage \
  -o jsonpath='{range .items[0].spec.containers[*]}{.name}{"\n"}{end}'
```

Do not trust the `READY` column here — look at the container lists. Current
Linkerd injects the proxy as a **native sidecar**: an entry in
`initContainers` with `restartPolicy: Always`, the mechanism lab 1 step 4
mentioned. Native sidecars are init containers, so they do not add to the
`n/m` count the way an ordinary extra container would.

Three things were added to each meshed pod:

- `linkerd-init` — a regular init container that rewrites the pod's iptables
  rules so every inbound and outbound connection is redirected to the proxy on
  localhost. Runs once, exits.
- `linkerd-proxy` — the native sidecar. Starts next, and the kubelet waits for
  it to report started before running anything after it.
- nothing at all in the application container. `productpage` still thinks it
  is calling `reviews:9080` directly.

Confirm the injection took:

```sh
linkerd -n "$NS" check --proxy
```

## Why `wait-for-details` still works — and when it would not

This is the mesh gotcha most people meet the hard way.

The init container from lab 1 step 4 makes a network call. Under a mesh, that
call is redirected by iptables to the proxy on localhost. If the proxy is not
running yet, the call is refused — and an init container that retries forever
means a pod that **never starts**. Whole namespaces have been taken down by
exactly this during a mesh rollout.

It works here because the proxy is a native sidecar and therefore starts
*before* the later init containers. Check the order:

```sh
kubectl -n "$NS" get pod -l app=productpage \
  -o jsonpath='{range .items[0].spec.initContainers[*]}{.name}{" "}{.restartPolicy}{"\n"}{end}'
kubectl -n "$NS" logs deploy/productpage-v1 -c wait-for-details
```

`linkerd-init`, then `linkerd-proxy` (`restartPolicy: Always`), then
`wait-for-details`.

With an older mesh, or with native sidecars turned off
(`linkerd install --set proxy.nativeSidecar=false`), the proxy is an ordinary
container that only starts after every init container has finished — and this
pod hangs in `Init:1/2` forever. The escape hatches are
`config.linkerd.io/skip-outbound-ports` on the pod, or not making network
calls from init containers at all.

## Annotation on the workload, or on the namespace?

This overlay annotates the **Deployments**, which is what makes the step a
manifest you can read and diff. In production you normally annotate the
namespace once:

```sh
kubectl annotate namespace "$NS" linkerd.io/inject=enabled
kubectl -n "$NS" rollout restart deploy
```

Everything deployed into it is then meshed by default. Per-workload
annotation is how you migrate an existing namespace one service at a time.

`toolbox` and `loadgen` are deliberately left unmeshed — step 3 uses that.

## The cost, measured now rather than claimed later

```sh
kubectl -n "$NS" top pods --containers | grep linkerd-proxy
```

One more container per pod, its memory and CPU, and one more hop on every
request. Write the numbers down; the debrief comes back to them.

## Questions

- The rollout restarted every meshed pod. What would that have cost you on a
  namespace with real traffic, and how would you have sequenced it?
- The proxy intercepts traffic through iptables rules set by an init container
  that needs `NET_ADMIN`. What does that imply on a cluster with a restricted
  Pod Security Standard?
