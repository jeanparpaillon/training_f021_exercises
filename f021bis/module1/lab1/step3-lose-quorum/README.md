# Step 3 — lose quorum

**Slide:** Lab 1 — your tools · **~10 min**

**Hypothesis first:** one member left. Can you still *read*? Do the running
pods keep running?

## Break

```sh
date +%T; docker pause ha-control-plane2 ha-control-plane3
```

## Observe

```sh
kubectl get pods -A --request-timeout=5s
etcdctl ha-control-plane endpoint status -w table      # still answers, as a non-leader
etcdctl ha-control-plane endpoint health                # but cannot commit
```

Below the API, the writer's container is still there:

```sh
docker exec ha-control-plane crictl ps --name writer
docker exec ha-control-plane sh -c 'crictl logs --tail 5 $(crictl ps -q --name writer)'
```

Try going around the load balancer, straight to the last API server, with
a read served from its cache (`resourceVersion=0`):

```sh
ip=$(docker inspect -f '{{.NetworkSettings.Networks.kind.IPAddress}}' ha-control-plane)
kubectl --server "https://$ip:6443" get --raw \
  '/api/v1/namespaces/writer/configmaps?resourceVersion=0' --request-timeout=5s
```

## Repair

Bring back **one** member, and time it:

```sh
date +%T; docker unpause ha-control-plane3
until kubectl get --raw /readyz --request-timeout=3s >/dev/null 2>&1; do sleep 1; done; date +%T
docker unpause ha-control-plane2
```

On a dry run the API answered again ~8 s after the first `unpause`.

## Questions

- Why do even reads fail? (`kubectl get` asks for the latest state: a
  quorum read.) What did the cached read answer, and why can the API server
  not serve from its cache either?
- The containers kept running with no API at all. What *stopped* working
  for them? (Think: a pod that crashes now, a node that dies now, a Service
  that gains an endpoint now.)
- Nothing had to be repaired: why did the cluster come back by itself?
