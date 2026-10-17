# Step 2 — make Bookinfo, and the mesh, drain-safe

**Slides:** Node management · In place, or migrate? · **~15 min**

Two workloads to fix: Bookinfo, and Linkerd's control plane, which every
Bookinfo request depends on.

## Bookinfo

Read [`drain-safe.yaml`](drain-safe.yaml) and [`pdb.yaml`](pdb.yaml) — one
setting per failure of step 1 — then:

```sh
kubectl apply -k lab3/step2-ready
kubectl -n bookinfo delete deploy reviews-v1 reviews-v3   # apply -k never deletes
kubectl -n bookinfo rollout status deploy --timeout=5m
kubectl -n bookinfo get pods -o wide                       # one of each per node
kubectl -n bookinfo get pdb                                # ALLOWED DISRUPTIONS 1
```

One reviews version only, at two replicas: three versions × two Open
Liberty JVMs is more memory than the room has. The page is now always
reviews-v2: 9 black stars.

## Linkerd

[`linkerd-ha.yaml`](linkerd-ha.yaml): two of each controller, spread,
budgeted, and the injector failing closed. Same release, one more values
file, after the first (later files win):

```sh
helm upgrade linkerd-control-plane linkerd-edge/linkerd-control-plane \
  -n linkerd --version "$LINKERD_TO" \
  -f lab2/values/control-plane.yaml -f lab3/step2-ready/linkerd-ha.yaml \
  --set-file identityTrustAnchorsPEM=lab2/certs/ca.crt \
  --set-file identity.issuer.tls.crtPEM=lab2/certs/issuer.crt \
  --set-file identity.issuer.tls.keyPEM=lab2/certs/issuer.key \
  --wait --timeout 10m
kubectl -n linkerd get pods -o wide
kubectl -n linkerd get pdb
kubectl -n bookinfo rollout restart deploy                 # remesh anything step 1 left 1/1
kubectl -n bookinfo rollout status deploy --timeout=5m
```

## Drain again

```sh
DURATION=4m lab3/load > k6.log 2>&1 &
sleep 30
kubectl drain prod-worker --ignore-daemonsets --delete-emptydir-data
kubectl uncordon prod-worker
sleep 10
kubectl drain prod-control-plane --ignore-daemonsets --delete-emptydir-data
kubectl uncordon prod-control-plane
wait; tail -40 k6.log
kubectl -n bookinfo get pods -o wide                       # all 2/2?
```

Measured on a dry run: 0 failed requests out of 2401, every check passed,
p99 41 ms, every pod still meshed.

## Check the skew before step 3

```sh
kubectl version
kubectl get nodes -o custom-columns=NODE:.metadata.name,KUBELET:.status.nodeInfo.kubeletVersion
```

## Questions

- Without `pdb.yaml`, what would the drain have done to two replicas of
  productpage on the same node? And with the PDB but without the spread?
- The first time this was written, the PDBs landed in namespace `default`
  and protected nothing — kustomize's `namespace:` only applies to what its
  own kustomization lists. How would you have noticed?
- Without the `deploymentStrategy` in `linkerd-ha.yaml`, `helm upgrade` hangs
  with a Pending pod. Why? (Required anti-affinity, two nodes, two replicas,
  `maxUnavailable` 25% of 2 rounded down.)
- A drain refused to evict a pod. What does `--disable-eviction` do, and why
  must you never use it to get past a PDB?
