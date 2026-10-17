# Step 4 — the kubelets, one node at a time

**Slide:** The kubeadm upgrade, step by step · **~15 min**

The k6 run of step 3 is still going. Same sequence for each node: drain,
binaries, kubelet restart, uncordon. Control plane first.

## prod-control-plane

```sh
kubectl drain prod-control-plane --ignore-daemonsets --delete-emptydir-data
docker exec -e K8S_TO="$K8S_TO" prod-control-plane sh -c '
  curl -fsSLo /tmp/kubelet "https://dl.k8s.io/release/$K8S_TO/bin/linux/amd64/kubelet"
  install -m 0755 /tmp/kubelet /usr/bin/kubelet
  systemctl daemon-reload && systemctl restart kubelet'
kubectl wait --for=condition=Ready node/prod-control-plane --timeout=2m
```

**Wait for the API before going on.** A new kubelet minor version restarts
the static pods it runs — here the whole control plane — and a restarting
API server refuses requests until its RBAC caches are loaded: `kubectl`
gets `Forbidden` for a few seconds, even as admin. A drain started in that
window fails half-way.

```sh
until kubectl get --raw /readyz >/dev/null 2>&1; do sleep 2; done
kubectl uncordon prod-control-plane
```

## prod-worker

A worker also needs `kubeadm upgrade node`, which only refreshes its local
kubelet configuration:

```sh
kubectl drain prod-worker --ignore-daemonsets --delete-emptydir-data
docker exec -e K8S_TO="$K8S_TO" prod-worker sh -c '
  for b in kubeadm kubelet; do
    curl -fsSLo /tmp/$b "https://dl.k8s.io/release/$K8S_TO/bin/linux/amd64/$b"
  done
  install -m 0755 /tmp/kubeadm /usr/bin/kubeadm
  kubeadm upgrade node
  install -m 0755 /tmp/kubelet /usr/bin/kubelet
  systemctl daemon-reload && systemctl restart kubelet'
kubectl wait --for=condition=Ready node/prod-worker --timeout=2m
kubectl uncordon prod-worker
kubectl get nodes
```

## After the last uncordon

```sh
kubectl -n bookinfo get pods -o wide
```

Everything is on one node: the last drain sent it there, and nothing moves
a running pod back. Rebalance on purpose:

```sh
kubectl -n bookinfo rollout restart deploy
kubectl -n linkerd rollout restart deploy
```

## Questions

- Why is `kubeadm upgrade node` on a worker fast and `upgrade apply` on the
  control plane not?
- You could have left the kubelets at `K8S_FROM`. For how many more minor
  upgrades of the control plane?
- What keeps pods spread *over time*, without someone restarting them?
  (Look up the descheduler.)
