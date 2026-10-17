# Step 2 — etcd snapshot, and what goes with it

**Slide:** etcd: snapshot and restore · **~10 min**

## Snapshot

From the member, into its data directory (a hostPath: the file is on the
node), then out of the node:

```sh
etcdctl prod-control-plane snapshot save /var/lib/etcd/snap.db
etcdutl prod-control-plane snapshot status /var/lib/etcd/snap.db -w table
mkdir -p lab4/backup
docker cp prod-control-plane:/var/lib/etcd/snap.db lab4/backup/snap.db
```

The same without the helper, which is what a backup job would run:

```sh
docker exec prod-control-plane sh -c 'crictl exec $(crictl ps -q --name "^etcd$") \
  etcdctl --endpoints https://127.0.0.1:2379 \
    --cacert /etc/kubernetes/pki/etcd/ca.crt \
    --cert /etc/kubernetes/pki/etcd/healthcheck-client.crt \
    --key /etc/kubernetes/pki/etcd/healthcheck-client.key \
    endpoint status -w table'
```

## What else

A snapshot without the CA is a cluster no kubelet trusts, and without
`sa.key` every ServiceAccount token is invalid:

```sh
docker cp prod-control-plane:/etc/kubernetes/pki lab4/backup/pki
ls lab4/backup/pki lab4/backup/pki/etcd
```

There is no encryption at rest here — the API server has no
`--encryption-provider-config` — so every Secret is in the snapshot, base64
only. With encryption on, the key file would be one more thing to back up,
and the snapshot useless without it.

```sh
docker exec prod-control-plane grep -c encryption-provider /etc/kubernetes/manifests/kube-apiserver.yaml   # 0
```

## After the snapshot

Something that exists only after it:

```sh
kubectl -n default create configmap after-snapshot --from-literal=t="$(date +%T)"
```

## Questions

- `snap.db` holds every Secret of the cluster. Where would you store it, and
  who may read it?
- In an HA cluster, which member do you snapshot?
