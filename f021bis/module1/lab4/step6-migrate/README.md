# Step 6 — migrate Bookinfo to a new cluster *(optional)*

**Slide:** In place, or migrate? · **~10 min**

The other way to upgrade (lab 3): a new cluster at `K8S_TO`, the workload
restored into it from the backups, traffic switched. About 3 GiB more per
pair: the trainer says whether the room can afford it, otherwise it is a
demo.

## green

```sh
make green
kubectl --context kind-green get nodes
velero --kubecontext kind-green backup get       # prod's backups: same bucket
```

`make green` creates the cluster ([`kind.yaml`](kind.yaml), page on
127.0.0.1:30081), installs Linkerd with the **same** trust anchor and
issuer, and Velero on the same bucket. Linkerd first: the backed-up pods
carry their injected proxies, which need a control plane that trusts
their identity.

## Restore

```sh
velero --kubecontext kind-green restore create migrate --from-backup bookinfo --wait
kubectl --context kind-green -n bookinfo rollout status deploy --timeout=5m
curl -s http://127.0.0.1:30081/productpage | grep -c glyphicon-star    # 5: the data came along
```

## Switch, then clean up

The switch itself is DNS or the load balancer in front of both — here,
the port you curl. Keep the old cluster until you trust the new one:

```sh
kind delete cluster --name green
```

## Questions

- What did *not* come over? (Anything outside `bookinfo`: cluster-scoped
  objects, other namespaces, Helm releases of the platform.)
- MySQL was copied at backup time. What happens to writes made on `prod`
  between the backup and the switch?
- Which is cheaper for this application: lab 3's in-place upgrade, or this?
