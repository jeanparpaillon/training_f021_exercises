# f021bis exercises

Exercises for **F021bis — Kubernetes in production**. The slides are in
`../../trainings/f021bis/slides/` (one `moduleN.md` per module, plus
sub-decks it imports); each module README here names the slides each lab
belongs to, and the slides point back with `📖 module1/README.md — Lab N`.

## Layout

```
shared-cluster/            the f021bis dev cluster (kind `training-f021bis` on the
                           server): trainee consoles with a dind sidecar. Its README
                           is the reference for consoles, sizes, trainer runbook
module1/                   cluster administration (HA, upgrades, backup, troubleshooting)
  README.md                overview, conventions, versions, size, lessons learned
  versions.env             every pinned version; KEY=value, sourced by bash AND
                           included by make — no quotes, no spaces
  Makefile                 catch-up-lab2/3/4 (rebuild `prod` at the end of a lab),
                           `green` (lab 4 step 6); CLUSTER= / KIND_CONFIG= / CHARTS=
  .gitignore               lab2/certs/, lab4/backup/
  bookinfo/                F021's Bookinfo (by relative path) in namespace bookinfo,
                           productpage NodePort 30080 — base of every Bookinfo overlay
  lab0/                    Makefile (tools into ~/bin, image pulls, charts), etcdctl.sh
  labN/
    README.md              lab intro: steps table, files, end state
    stepM-<name>/README.md the step file; manifests next to it when the step ships any
  lab1/writer/             the API client whose log lab 1 measures
  lab2/{kind.yaml,values/} prod's kind config, Helm values of Linkerd
  lab3/{k6.js,load}        load generator, run OUTSIDE the cluster
  lab4/s3/                 SeaweedFS S3 store for Velero (start script, identity, creds)
  lab5/{break,check,reset,lib.sh,scenarios/N.sh}
                           fault injection; each scenario defines symptom,
                           break_it, check_it, fix_it
module2/ … module4/        Ansible, Zabbix, Ansible certification (not written yet)
```

Bookinfo states are cumulative overlays: `bookinfo/` → `lab2/step3-install`
(meshed) → `lab3/step2-ready` (drain-safe, reviews-v2 only) →
`lab4/step1-stateful` (ratings-v2 on MySQL). An overlay that adds resources
must set `namespace: bookinfo` itself — the base's `namespace:` does not
reach them (this once put lab 3's PDBs in `default`).

## Conventions

The same as F021 (`../f021/CLAUDE.md`, module READMEs), with what module 1
changes:

- **Labs run in nested kind clusters**, created by the trainees in their web
  console (the console pod's dind sidecar), not in a namespace of the shared
  cluster. Node names are `<cluster>-control-plane`, `<cluster>-worker`, …;
  "below the API" commands are `docker exec <node> …` (`crictl`,
  `journalctl -u kubelet`, `/etc/kubernetes/manifests`). Step files assume
  `cd module1 && source versions.env`.
- **Pairs, one cluster per pair at a time**: the server has 4 CPUs / 15 GiB
  for the room; `prod` with everything on it is ~3 GiB. Any new lab must fit
  the *Size* section of `module1/README.md`.
- **One cluster carries labs 2 → 5**: `prod` (1 control plane, untainted, + 1
  worker), created at `K8S_FROM` in lab 2, upgraded to `K8S_TO` in lab 3.
  Each lab's end state is the next one's start, and has a `make
  catch-up-labN` target; keep those in sync when a lab's end state changes.
- **Everything here was run** on kind v0.33.0 with the pinned versions (dry
  run 2026-10-17), except lab 4 step 6 (`green`). When changing a step, run
  it again rather than reasoning about it: most of the traps listed in
  `module1/README.md` ("What was learned") were found that way, not
  predicted.
- **kind-specific traps** to keep in mind: lose nodes with `docker pause`,
  never `docker stop` (IPs move); kind's multi-control-plane load balancer
  is Envoy, not HAProxy; `kubeadm upgrade` in a node needs
  `--ignore-preflight-errors=SystemVerification`; a console's Docker daemon
  is the dind sidecar, so bind-mounting console files into a container does
  not work (`docker cp` instead).
- **No tool the console lacks is assumed**: what the console image does not
  ship (`linkerd`, `step`, `velero`) is installed into `~/bin` by `lab0/`.
  `etcdctl`/`etcdutl` are run from the etcd container via `crictl exec`,
  because the API may be down when they are needed.
- Step tables in a lab README and on its *Lab N — goal* slide must stay in
  sync (names, order, durations). Measured results quoted in the step files
  ("on a dry run: …") are also in the slide notes.
