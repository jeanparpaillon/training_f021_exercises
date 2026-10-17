# Step 5 — schedules, and the restore test

**Slide:** What is there to back up? · **~5 min**

```sh
velero schedule create bookinfo-daily --schedule "0 2 * * *" --ttl 168h \
  --include-namespaces bookinfo
velero schedule get
velero backup create --from-schedule bookinfo-daily --wait     # run it now, once
velero backup get
```

`--ttl 168h`: each backup is deleted after a week — the RPO you chose, and
the history you keep.

A backup is proven by a restore. Restore into **another namespace**, so
production is not touched, and check the data there:

```sh
b=$(velero backup get -o json | jq -r '.items | sort_by(.metadata.creationTimestamp) | last | .metadata.name')
velero restore create restore-test --from-backup "$b" \
  --namespace-mappings bookinfo:bookinfo-restore-test --wait
kubectl -n bookinfo-restore-test rollout status deploy/mysqldb-v1 --timeout=5m
kubectl -n bookinfo-restore-test exec deploy/mysqldb-v1 -c mysqldb -- sh -c \
  'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" test -e "SELECT * FROM ratings"'
kubectl delete ns bookinfo-restore-test
```

## Questions

- How long did the restore take? That is the floor of your RTO for this
  application.
- What would you alert on, so that a schedule that silently stops is
  noticed? (`velero_backup_last_successful_timestamp`.)
