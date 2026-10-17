# Step 4 — the leaders

**Slide:** Lab 1 — your tools · **~5 min**

Two different kinds of leader: etcd's Raft leader, and the lease holders of
`kube-controller-manager` and `kube-scheduler`.

## The etcd leader

Move leadership on purpose first: `move-leader` is what you do before
maintenance on the leader's node. It must be sent to the current leader.

```sh
etcdctl ha-control-plane endpoint status --cluster -w table       # who leads?
etcdctl ha-control-plane member list                              # IDs are hex
# from the LEADER's node, to the member you want:
etcdctl <leader-node> move-leader <hex id of ha-control-plane2>
etcdctl ha-control-plane endpoint status --cluster -w table       # RAFT TERM +1
```

Then the unplanned version: make sure `ha-control-plane2` leads, and pause it.

```sh
date +%T; docker pause ha-control-plane2
etcdctl ha-control-plane endpoint status --cluster -w table
docker unpause ha-control-plane2
```

## The controller-manager lease

```sh
kubectl -n kube-system get lease kube-controller-manager -o yaml | grep -E 'holderIdentity|leaseDurationSeconds|renewTime'
```

If the holder is not `ha-control-plane`, pause its node and watch the lease
change hands:

```sh
kubectl -n kube-system get lease kube-controller-manager -w
```

## Questions

- The Raft election took about a second; the lease takeover up to
  `leaseDurationSeconds`. What does not happen in the cluster during that
  window? (Nothing reconciles: no ReplicaSet creates pods, no node is
  marked NotReady.)
- Why is a planned `move-leader` better than letting the election happen?
