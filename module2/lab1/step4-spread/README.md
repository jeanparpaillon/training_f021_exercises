# Step 4 — spread and budgets

**Slide:** Lab 1 — spread and budgets · **~15 min**

Needs more than one worker node. See the prerequisites in
[`../../README.md`](../../README.md).

```sh
kubectl get nodes -L topology.kubernetes.io/zone
```

## Replicas, spread and budgets

- [`spread.yaml`](spread.yaml) sets two replicas for `productpage` and each
  `reviews` version, with `topologySpreadConstraints` on
  `kubernetes.io/hostname` (hard) and `topology.kubernetes.io/zone` (soft)
- [`pdb.yaml`](pdb.yaml) adds a `PodDisruptionBudget` with `minAvailable: 1`
  on each of those four Deployments

```sh
kubectl -n "$NS" apply -k lab1/step4-spread
kubectl -n "$NS" get pods -o wide -l 'app in (productpage,reviews)'
kubectl -n "$NS" get pdb
```

Check the placement. The two replicas of each Deployment must be on two
different nodes. With `module2/kind.yaml` (workers in `zone-a`, `zone-a`,
`zone-b`), look at the zones as well. `ALLOWED DISRUPTIONS` is 1 on every
PDB.

Now take the spread constraints out of your head for a moment. Nothing but
luck would have kept two replicas apart without them.

## Drain a worker under load

Pick a worker that runs a `productpage` pod, start k6, wait 20 s, then:

```sh
kubectl drain <worker> --ignore-daemonsets --delete-emptydir-data
```

In a second terminal:

```sh
kubectl -n "$NS" get pdb -w
kubectl -n "$NS" get pods -o wide -w
```

The drain evicts through the eviction API, one pod at a time, and waits
(`Cannot evict pod as it would violate the pod's disruption budget`) when a
Deployment's other replica is not Ready yet. The k6 numbers should stay
flat. Steps 2 and 3 are what make the evictions clean.

Put the node back:

```sh
kubectl uncordon <worker>
```

The evicted pods do **not** move back. Nothing rebalances a running
Deployment. Look at `-o wide` again, and think about what the next drain
will do.

`--delete-emptydir-data` is needed because `productpage` and `reviews` mount
an `emptyDir` on `/tmp`. The drain refuses to lose data silently, and this
flag says that data is disposable.

## Questions

- What happens if you drain two workers at once? Try it with
  `kubectl drain <w1> <w2> ...` and watch where the replacement pods go.
- `details` and `ratings` still have one replica and no PDB. What did the
  drain do to them, and what did the page look like meanwhile?
- What does a `minAvailable: 1` PDB do on a Deployment with a single
  replica? What will the ops team do about it at 3 a.m., and what
  protection is left afterwards?
- What does a PDB **not** protect against? Name three events that never
  ask it.
