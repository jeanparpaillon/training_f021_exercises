# Step 2 — service discovery

**Slide:** Lab 1 — service discovery · **~15 min**

Decomposition turned in-process calls into network calls. This step is about
the only thing that makes those calls possible: a name that resolves.

Adds a `toolbox` pod (a busybox shell) and a second, headless Service in front
of the same reviews pods.

```sh
kubectl -n "$NS" apply -k lab1/step2-discovery
kubectl -n "$NS" rollout status deploy/toolbox
```

## Resolve names from inside the cluster

```sh
kubectl -n "$NS" exec -it deploy/toolbox -- sh

# inside the pod:
nslookup reviews
nslookup reviews.$NS.svc.cluster.local
cat /etc/resolv.conf
```

The `search` line in `resolv.conf` is why `reviews` alone works from inside
the namespace, and why the same short name means a different service in
someone else's namespace.

## ClusterIP vs headless

```sh
# inside the toolbox pod:
nslookup reviews            # -> ONE address: the Service's virtual IP
nslookup reviews-headless   # -> THREE addresses: the pod IPs themselves
```

Both Services select the same pods. The difference is who load-balances:

| | `reviews` (ClusterIP) | `reviews-headless` (clusterIP: None) |
| --- | --- | --- |
| DNS answer | one virtual IP | every ready pod IP |
| Balancing | kube-proxy, per connection | the client, however it likes |
| Used by | ordinary HTTP clients | gRPC clients, StatefulSets, mesh proxies |

Compare with what the API server thinks:

```sh
kubectl -n "$NS" get endpointslices -l kubernetes.io/service-name=reviews -o wide
```

## Call a service by name

```sh
# inside the toolbox pod:
wget -q -O - http://details:9080/details/0
wget -q -O - http://reviews:9080/reviews/0
```

## Questions to answer before moving on

- Scale `reviews-v2` to 0 and run `nslookup reviews-headless` again. How long
  before DNS stops handing out that pod?
- The virtual IP of `reviews` answers on port 9080, but no process anywhere is
  listening on that address. What is actually happening to the packet?
- Why would a gRPC client care about the difference between these two Services?
  (Slide: *gRPC on Kubernetes* — the answer comes back in lab 2.)
