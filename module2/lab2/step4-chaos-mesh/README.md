# Step 4 — install Chaos Mesh

**Slide:** Lab 2 — install Chaos Mesh · **~5 min**

Nothing to apply in your namespace. The overlay is step 2 unchanged, and
exists so that `kubectl apply -k lab2/step4-chaos-mesh` still lands you in
the right state.

## Shared cluster

The trainer has installed Chaos Mesh cluster-wide. You can create Chaos
objects in your own namespace only, and an experiment can only select pods
in its own namespace: leave `selector.namespaces` out, and Chaos Mesh fills
it in with yours.

## kind

Chaos Mesh runs a controller (webhooks, scheduling) and a privileged
`chaos-daemon` on every node, which enters the pods' namespaces to inject
faults. On kind, the node runtime is containerd:

```sh
helm repo add chaos-mesh https://charts.chaos-mesh.org
helm install chaos-mesh chaos-mesh/chaos-mesh -n chaos-mesh --create-namespace \
  --version 2.8.4 \
  --set chaosDaemon.runtime=containerd \
  --set chaosDaemon.socketPath=/run/containerd/containerd.sock \
  --set controllerManager.replicaCount=1 \
  --set dashboard.securityMode=false
kubectl -n chaos-mesh get pods -w
```

`replicaCount=1` and `securityMode=false` are laptop settings: one
controller instead of three, and a dashboard that asks for no token.

If `chaos-controller-manager` crash-loops with `too many open files`, the
host's inotify limits are too low for another controller on a kind node
(the default `max_user_instances` of 128 is not enough). On the host:

```sh
sudo sysctl fs.inotify.max_user_instances=512 fs.inotify.max_user_watches=524288
```

## Look around

```sh
kubectl api-resources --api-group=chaos-mesh.org
kubectl -n chaos-mesh port-forward svc/chaos-dashboard 2333:2333     # http://localhost:2333
```

The fault types are separate CRDs: `PodChaos`, `NetworkChaos`,
`StressChaos`, `IOChaos`, `DNSChaos`, `TimeChaos`, `HTTPChaos`... The
dashboard can build experiments too. We write YAML instead, because the
debrief asks where these files should live.

## Questions

- `chaos-daemon` is privileged and runs on every node. What does that mean
  for who may install it on a production cluster, and who may create
  `NetworkChaos` objects?
- How is this different from Istio's fault injection in step 3? Think about
  where the fault happens, and what else it touches.
