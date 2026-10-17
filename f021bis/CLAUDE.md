# f021bis exercises

Exercises for **F021bis — Kubernetes in production**. The slides are in
`../../trainings/f021bis/slides/` (one `moduleN.md` per module); each module
README here names the slides each lab belongs to, and the slides point back
with `📖 moduleN/README.md — Lab N`.

## Layout

```
shared-cluster/            the f021bis dev cluster (kind `training-f021bis` on the
                           server): trainee consoles with a dind sidecar. Its README
                           is the reference for consoles, sizes, trainer runbook
module1/                   cluster administration (HA, upgrades, backup, troubleshooting)
  README.md                the labs: goal, cluster, steps table, questions
  versions.env             pinned versions, sourced by every Makefile / step file
  lab0/                    tools into ~/bin, image pre-pull, etcdctl.sh helper
  labN/                    one directory per lab
    README.md              lab intro
    stepM-<name>/          one directory per step, with its README.md (the step
                           file) and, when it ships manifests, a kustomization
    Makefile               when the lab has a catch-up / setup target
module2/ … module4/        Ansible, Zabbix, Ansible certification (not written yet)
```

**Status:** `module1/README.md` describes the labs; `versions.env`, `lab0/`
and the `labN/` directories it refers to do not exist yet. Write them to
match the README, or update the README with them.

## Conventions

The same as F021 (`../f021/CLAUDE.md`, module READMEs), with what module 1
changes:

- **Labs run in nested kind clusters**, created by the trainees in their web
  console (the console pod's dind sidecar), not in a namespace of the shared
  cluster. Node names are `<cluster>-control-plane`, `<cluster>-worker`, …;
  "below the API" commands are `docker exec <node> …` (`crictl`,
  `journalctl -u kubelet`, `/etc/kubernetes/manifests`).
- **Pairs, one cluster per pair at a time**: the server has 4 CPUs / 15 GiB
  for the room. Any new lab must fit the budget in the *Size* section of
  `module1/README.md`.
- **One cluster carries labs 2 → 5 of module 1**: `prod` (1 control plane,
  untainted, + 1 worker), created at `$K8S_FROM` in lab 2, upgraded to
  `$K8S_TO` in lab 3. Each lab's end state is the next one's start; a lab
  that needs a fresh start gets a `catch-up` target rather than assuming the
  previous lab went well. Lab 1's `ha` cluster is throwaway.
- **Bookinfo is reused from F021**, by relative kustomize path
  (`../../f021/module1/lab1/base`), not copied; it runs in namespace
  `bookinfo` of the trainee's own cluster, so manifests may hardcode it.
- **No tool the console lacks is assumed**: what the console image does not
  ship (`linkerd`, `step`, `velero`) is installed into `~/bin` by `lab0/`.
  `etcdctl`/`etcdutl` are run from the etcd container via `crictl exec`,
  because the API may be down when they are needed.
- Step tables in a module README and on its *Lab N — goal* slide must stay in
  sync (names, order, durations).
