# Lab 4 — backup and restore

**Slides:** *Backup and restore*, then *Lab 4* · **~80 min**

Back `prod` up two ways and restore it — the whole cluster from an etcd
snapshot, then a namespace and its volume with Velero — and find out what
each one does **not** bring back.

| Step | | ~ |
| --- | --- | --- |
| [step1-stateful](step1-stateful/) | Bookinfo with state: ratings on MySQL | 10 min |
| [step2-etcd-snapshot](step2-etcd-snapshot/) | snapshot + PKI, out of the node | 10 min |
| [step3-etcd-restore](step3-etcd-restore/) | restore it, and everything that comes with it | 20 min |
| [step4-velero](step4-velero/) | backup, delete, restore — with the data | 25 min |
| [step5-schedule](step5-schedule/) | schedules, and the restore test | 5 min |
| [step6-migrate](step6-migrate/) | *optional*: Bookinfo to a new cluster | 10 min |

| File | What it is |
| --- | --- |
| [`s3/`](s3/) | an S3 store (SeaweedFS) as a container next to the kind nodes, for Velero |
| `backup/` | where you copy what comes out of the nodes (git-ignored) |

## Check every restore by the data

| After… | namespace `bookinfo` back? | your MySQL change back? | ConfigMap made after the backup? |
| --- | --- | --- | --- |
| etcd restore (step 3) | | | |
| Velero restore (step 4) | | | |

**End state** (start of lab 5): Bookinfo stateful, Velero installed. From
nothing: `make catch-up-lab4` in `module1/`.

```sh
cd ~/trainings_exercises/f021bis/module1
source versions.env
source lab0/etcdctl.sh
stars() { curl -s http://127.0.0.1:30080/productpage | grep -c glyphicon-star; }
```
