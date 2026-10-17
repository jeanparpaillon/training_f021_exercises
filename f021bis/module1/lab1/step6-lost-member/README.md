# Step 6 — a member loses its disk

**Slide:** Lab 1 — your tools · **~15 min**

The failure that needs a human: a member whose data is gone. Restarting it
is not enough, and restoring a backup would be far too much.

## Break

Stop the static pod (move its manifest out: the kubelet stops what it no
longer finds), wipe the data, put the manifest back:

```sh
docker exec ha-control-plane3 sh -c '
  mv /etc/kubernetes/manifests/etcd.yaml /root/etcd.yaml
  while crictl ps -q --name "^etcd$" | grep -q .; do sleep 1; done
  rm -rf /var/lib/etcd/member
  mv /root/etcd.yaml /etc/kubernetes/manifests/etcd.yaml'
```

## Observe

```sh
docker exec ha-control-plane3 crictl ps -a --name '^etcd$'      # Exited, ATTEMPT growing
etcdlogs ha-control-plane3 2>&1 | grep -E '"level":"(panic|fatal)"' | head -2
etcdctl ha-control-plane member list -w table                   # still listed, "started"
```

The panic says it: `tocommit(N) is out of range [lastIndex(0)]. Was the raft
log corrupted, truncated, or lost?` The cluster remembers this member at
index N; the member remembers nothing. Raft refuses to pretend.

## Repair

From a healthy member: remove the old identity, add a new member with the
same name and peer URL.

```sh
etcdctl ha-control-plane member list            # ID, status, name, peer URL, …
etcdctl ha-control-plane member remove <hex id of ha-control-plane3>
etcdctl ha-control-plane member add ha-control-plane3 --peer-urls=https://<its ip>:2380
```

`member add` prints the `ETCD_INITIAL_CLUSTER` the new member must start
with. Compare it with the flags of the static pod:

```sh
docker exec ha-control-plane3 grep -E 'initial-cluster' /etc/kubernetes/manifests/etcd.yaml
```

kubeadm wrote `--initial-cluster-state=existing` and the three members when
this node joined: the manifest is already right. Start it on an **empty**
data directory, so it syncs from the others as the new member:

```sh
docker exec ha-control-plane3 sh -c '
  mv /etc/kubernetes/manifests/etcd.yaml /root/etcd.yaml
  while crictl ps -q --name "^etcd$" | grep -q .; do sleep 1; done
  rm -rf /var/lib/etcd/member
  mv /root/etcd.yaml /etc/kubernetes/manifests/etcd.yaml'
etcdctl ha-control-plane member list -w table               # a new ID
etcdctl ha-control-plane endpoint status --cluster -w table # same RAFT INDEX everywhere
```

## Questions

- Why remove and re-add, rather than restart on an empty directory? (The
  member ID: the cluster expects the old one to have the log it acked.)
- During the repair, the cluster ran on 2 out of 3. What happens if a second
  member fails then? What does that say about doing this one member at a
  time, and fast?
- When would you use a snapshot restore (lab 4) instead?

Then the lab's clean up: [`../README.md`](../README.md#clean-up).
