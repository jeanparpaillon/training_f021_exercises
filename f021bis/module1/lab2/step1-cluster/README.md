# Step 1 — `prod` and Bookinfo

**Slide:** Lab 2 — goal · **~10 min**

## The cluster

One minor version **below** the latest: lab 3 upgrades it.

```sh
kind create cluster --name prod --config lab2/kind.yaml --image "$KIND_NODE_FROM"
kubectl get nodes -o wide
```

kind taints the control plane when there is a worker. Remove the taint:
with only two nodes, a drain in lab 3 needs the other node to take the
pods. This is a lab compromise — in production, keep workloads off the
control plane.

```sh
kubectl describe node prod-control-plane | grep Taints
kubectl taint nodes prod-control-plane node-role.kubernetes.io/control-plane:NoSchedule-
```

## Bookinfo

F021's manifests, in namespace `bookinfo`, productpage on NodePort 30080:

```sh
kubectl kustomize bookinfo | less        # what is applied
kubectl apply -k bookinfo
kubectl -n bookinfo rollout status deploy --timeout=5m
curl -s http://127.0.0.1:30080/productpage | grep -c glyphicon-star
```

The star count is the module's smoke test: `9` with reviews v2 or v3 (5 + 4
stars), `0` with v1 or when ratings fails. Reload a few times: the three
reviews versions take turns.

## Questions

- `127.0.0.1:30080` in your console reaches a NodePort inside a container of
  the Docker daemon next to it. Follow the path (`lab2/kind.yaml`).
- Where did each pod land (`kubectl -n bookinfo get pods -o wide`)? Would
  that have been different before the untaint?
