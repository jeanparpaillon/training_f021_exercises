# Step 1 — build `ha`, find every component

**Slide:** Lab 1 — goal · **~10 min**

## Create it

```sh
kind create cluster --name ha --config lab1/kind.yaml --image "$KIND_NODE_TO"
docker ps --format '{{.Names}}\t{{.Status}}'
kubectl get nodes -o wide
```

Four containers: three control-plane nodes and `ha-external-load-balancer`.
Your kubeconfig points at the load balancer, not at a node:

```sh
kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'; echo
```

## The stable endpoint

kind's load balancer is Envoy. Read its configuration and keep its log open:
it records every health check.

```sh
docker exec ha-external-load-balancer cat /home/envoy/cds.yaml
docker logs -f ha-external-load-balancer 2>&1 | grep --line-buffered -i eject
```

- Which URL does it check on each API server, how often, and after how many
  failures does it take one out?

## etcd

```sh
etcdctl ha-control-plane member list -w table
etcdctl ha-control-plane endpoint status --cluster -w table
etcdctl ha-control-plane endpoint health --cluster
```

`IS LEADER`, `RAFT TERM` (increments on each election) and `RAFT INDEX`
(the last entry each member has) are the three columns to watch for the
rest of the lab. Note who the leader is.

Each etcd is a static pod, started by its node's kubelet from a file, not
by the API:

```sh
docker exec ha-control-plane3 grep -E 'initial-cluster|name=|data-dir' /etc/kubernetes/manifests/etcd.yaml
```

## The controllers

The scheduler and the controller-manager run on all three nodes, but only
one of each works at a time: the one holding the lease.

```sh
kubectl -n kube-system get lease kube-controller-manager kube-scheduler
```

## The writer

```sh
kubectl apply -k lab1/writer
kubectl -n writer get pods -o wide            # on ha-control-plane
kubectl -n writer logs -f deploy/writer       # in your second terminal
```

One line per second: time, HTTP status (`000` = no answer within 3 s),
duration. Read [`../writer/writer.yaml`](../writer/writer.yaml): which path
does the writer take to the API, and how is it different from yours?

```sh
kubectl get endpointslices -n default -l kubernetes.io/service-name=kubernetes
```

## Questions

- Your `kubectl` and the writer reach the API servers by two different
  paths. Draw both.
- Why does every node run a scheduler, if only one schedules?
