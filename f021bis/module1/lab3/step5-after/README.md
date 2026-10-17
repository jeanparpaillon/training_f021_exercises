# Step 5 — after the upgrade

**Slide:** Lab 3 — debrief · **~10 min**

## What changed

```sh
kubectl version
kubectl get nodes -o wide
kubectl -n kube-system get pods -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[0].image
source lab0/etcdctl.sh
etcdctl prod-control-plane endpoint status -w table        # etcd moved minor version too
```

## What did not

```sh
linkerd check
linkerd check --proxy -n bookinfo
helm ls -A
```

Linkerd was not touched and still passes: its release notes list the
Kubernetes versions it supports. That is a check to do *before* step 3,
not after.

## The numbers

```sh
wait; tail -40 k6.log            # or: fg, then Ctrl-C — k6 prints its summary
```

Fill the debrief table of [`../README.md`](../README.md#debrief-table).

## Questions

- What did you *not* have to upgrade, and who told you it was safe?
- In-place was cheap here. Name one change you could not have made this way.
  (CNI, pod CIDR, etcd topology: lab 4 step 6 is the other way.)
