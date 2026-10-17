# Step 1 — Bookinfo with state

**Slide:** Lab 4 — goal · **~10 min**

ratings-v2 reads the ratings from MySQL, on a PersistentVolume. Read
[`mysql.yaml`](mysql.yaml): two of its comments are about things that broke
while this lab was written (the MySQL version, the PV type).

```sh
kubectl apply -k lab4/step1-stateful
kubectl -n bookinfo delete deploy ratings-v1 && kubectl -n bookinfo delete pdb ratings-v1
kubectl -n bookinfo rollout status deploy --timeout=5m
kubectl -n bookinfo get pvc,pods -o wide
kubectl get pv -o custom-columns=NAME:.metadata.name,LOCAL:.spec.local.path,NODE:.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values
stars                                            # 9: 5 + 4
```

## Change the data

Reviewer 1 now gives one star. Write down the time:

```sh
date +%T
kubectl -n bookinfo exec deploy/mysqldb-v1 -c mysqldb -- sh -c \
  'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" test -e "UPDATE ratings SET Rating=1 WHERE ReviewID=1; SELECT * FROM ratings"'
stars                                            # 5: 1 + 4
```

This row exists in one place only: a directory on one node. It is what
the restores of this lab must bring back.

## Questions

- Which node is MySQL on, and why can it never run on the other one?
- MySQL is one replica with `Recreate`. Why can it not be drain-safe like
  the rest, and what would it take?
