# Step 5 — partition a member

**Slide:** Lab 1 — your tools · **~10 min**

A node that is up, answers on its API port, and cannot talk to its etcd
peers: the nastiest failure of the lab, because nothing is *down*.

**Hypothesis first:** what does a client sent to that node's API server get?

## Break

Drop etcd's peer traffic (port 2380, both directions) on `ha-control-plane3`
only. Its API server talks to its own etcd on 127.0.0.1:2379, which still
works; port 6443 stays reachable.

```sh
date +%T
docker exec ha-control-plane3 iptables -I INPUT -p tcp --dport 2380 -m comment --comment lab1 -j DROP
docker exec ha-control-plane3 iptables -I INPUT -p tcp --sport 2380 -m comment --comment lab1 -j DROP
```

## Observe

```sh
for i in $(seq 20); do kubectl get ns --request-timeout=3s >/dev/null && echo ok || echo FAIL; sleep 0.5; done
etcdctl ha-control-plane3 endpoint status -w table --command-timeout=3s   # its own view
etcdctl ha-control-plane endpoint status --cluster -w table               # the majority's
docker logs --since 1m ha-external-load-balancer 2>&1 | grep -E 'eject|health_check_failure' | tail -3
```

The partitioned API server is up — ask it directly what it thinks of itself:

```sh
ip=$(docker inspect -f '{{.NetworkSettings.Networks.kind.IPAddress}}' ha-control-plane3)
kubectl --server "https://$ip:6443" get --raw '/readyz?verbose' --request-timeout=5s | grep -i etcd
kubectl --server "https://$ip:6443" get --raw '/livez?verbose' --request-timeout=5s | grep -i etcd
```

## Repair

```sh
docker exec ha-control-plane3 sh -c \
  'iptables -S INPUT | grep lab1 | sed "s/^-A/-D/" | while read -r r; do iptables $r; done'
etcdctl ha-control-plane endpoint status --cluster -w table    # same term and index everywhere
```

## Questions

- Envoy checks `/healthz`. Which endpoint should a load balancer in front
  of API servers check, and does it include etcd?
- If the partitioned node had been the etcd leader, what would the two
  sides have done?
- With a 2-member cluster, what would a partition between them do?
