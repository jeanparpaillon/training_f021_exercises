# Step 4 — Velero, with the data

**Slide:** Velero: backups at the object level · **~25 min**

## Where backups go

Outside the cluster: an S3 store as a container of your console's Docker,
next to the kind nodes. Read [`../s3/start`](../s3/start), then:

```sh
S3_URL=$(lab4/s3/start); echo "$S3_URL"
```

## Install Velero

```sh
velero install \
  --provider aws --plugins "velero/velero-plugin-for-aws:$VELERO_AWS_PLUGIN_VERSION" \
  --image "velero/velero:$VELERO_VERSION" \
  --bucket velero --secret-file lab4/s3/credentials-velero \
  --backup-location-config "region=us-east-1,s3ForcePathStyle=true,s3Url=$S3_URL" \
  --use-node-agent --use-volume-snapshots=false --wait
velero backup-location get                       # PHASE Available
kubectl -n velero get pods -o wide               # the server + one node agent per node
```

The node agent reads volumes from the node's filesystem: that is how a
`local` volume with no snapshot support gets backed up. Which volumes:
the pod annotation `backup.velero.io/backup-volumes` in
[`../step1-stateful/mysql.yaml`](../step1-stateful/mysql.yaml) — opt-in, the
data only.

## Back up

Change the data again first (step 3 lost it), and note it:

```sh
kubectl -n bookinfo exec deploy/mysqldb-v1 -c mysqldb -- sh -c \
  'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" test -e "UPDATE ratings SET Rating=1 WHERE ReviewID=1"'
stars                                            # 5
velero backup create bookinfo --include-namespaces bookinfo --wait
velero backup describe bookinfo --details
```

Read `Phase` first — `Completed`, not `PartiallyFailed` — then `Pod Volume
Backups`: `var-lib-mysql`, with a size. A backup whose volume list is
empty saved the objects and **not** the data.

## The disaster, again

```sh
kubectl delete ns bookinfo
stars                                            # 0
velero restore create bookinfo --from-backup bookinfo --wait
velero restore describe bookinfo
kubectl -n bookinfo rollout status deploy --timeout=5m
kubectl -n bookinfo exec deploy/mysqldb-v1 -c mysqldb -- sh -c \
  'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" test -e "SELECT * FROM ratings"'
stars                                            # 5: your change is back
```

The restore re-created the PVC, a new empty PV under it, and the pod with
an init container (`restore-wait`) that holds MySQL until the node agent
has written the data back. Fill the Velero row of the table.

## Questions

- Two traps were hit while writing this step, both ending in a backup that
  says `Completed` and holds no data: local-path's default `hostPath` PVs
  (skipped, with a warning in the server log only), and an S3 store that
  refused signed requests (`PartiallyFailed`). What would have caught them
  before the day you needed the backup?
- Which objects does Velero skip or change on restore? (Nodes, Events; the
  ClusterIP of Services; PV names.)
- Velero went through the API. What could it not restore that etcd could,
  and the other way round?
