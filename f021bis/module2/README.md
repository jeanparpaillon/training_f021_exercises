# Module 2 — Infrastructure as code with Ansible

Exercises for module 2 of **F021bis — Kubernetes in production**. The slides
are in `../../../trainings/f021bis/slides/module2.md`, one sub-deck per
session (`ansible_basics.md`, `ansible_k8s.md`, `iac_workflows.md`,
`kubespray.md`, `iac_wrapup.md`) plus one per lab; every lab here names the
slides it belongs to, and the slides point back with
`📖 module2/README.md — Lab N`.

> **Status: specification.** This README describes what each lab must
> contain and check; the step files, `lab0/` and the solutions are not
> written yet and nothing here has been run. Items marked **(to validate)**
> are assumptions to confirm on the first dry run. The biggest one is
> Kubespray on container nodes (see [Nodes](#nodes--requirements-for-lab0)):
> settle it first, before any step file is written.

| | Lab | Session | ~ |
| --- | --- | --- | --- |
| [lab1/](lab1/) | Ansible refresher: inventory, facts, a role, idempotence, Vault | 1 | 60 min |
| [lab2/](lab2/) | `kubernetes.core`: manifests, Helm, drain, then hand over to Flux | 3 | 70 min |
| [lab3/](lab3/) | Kubespray: deploy (3a), day 2 operations (3b), upgrade (3c) | 4, 5 | 75 + 35 + 50 min |
| [lab0/](lab0/) | nodes, venv, Kubespray checkout, downloads; once before session 1 | — | — |

The trainees already did formation-prod (Day 3: inventories, `group_vars`,
playbooks, roles, handlers, idempotence, Galaxy, Molecule; Day 4: Kubernetes
basics, microk8s) and module 1 (kubeadm, upgrades by hand, drain, etcd). Lab
1 is a **refresher**, not a course: it re-activates what lab 3 needs. What is
new in this module is Ansible **driving Kubernetes**, from the outside (the
API, lab 2) and from the inside (the nodes, lab 3).

## Thread of the module

One project, `~/m2/`, in the driver's console, a Git repo from lab 1 on:

- **lab 1** writes the inventory of three nodes `node1`…`node3` with
  **Kubespray's group names** from the start, and a role on them;
- **lab 2** is a detour on a throwaway kind cluster `iac`: Ansible against
  the API, ending with Flux taking over the application;
- **lab 3** turns the same inventory into a Kubernetes cluster, `spray`,
  with Kubespray: create (2 nodes), add `node3`, remove `node2`, upgrade —
  and ends by running lab 2's Flux playbook against it: the whole chain,
  from bare nodes to GitOps, is code.

| Cluster | What | Nodes | Used by | Lifetime |
| --- | --- | --- | --- | --- |
| `iac` | kind | 1 control plane + 1 worker | lab 2 | deleted at the end of session 3 |
| `spray` | Kubespray on `node1`…`node3` | `node1` control plane + etcd, `node2` worker; `node3` added, `node2` removed in 3b | lab 3 | until the end of the module |

## Where the labs run

In the trainee's **web console** on the f021bis dev cluster (see
[`../shared-cluster/README.md`](../shared-cluster/README.md)):

| Role | What | Name |
| --- | --- | --- |
| control node | the console itself: Ansible from the module's venv, `kubectl`, `helm`, `kind`, `git`, `ssh` | — |
| managed nodes | 3 containers in the console's Docker (dind sidecar), Ubuntu 24.04, `systemd` + `sshd`, fixed IPs on network `m2` | `node1`, `node2`, `node3` |
| lab 2 cluster | kind, in the same Docker | `iac` |

**In pairs, the whole module in the driver's console**: the nodes of lab 1
are the cluster of lab 3, so the pair keeps the same console from session 1
to session 5 (see [Size](#size-trainer)). Swap the keyboard, not the
console.

## Nodes — requirements for `lab0/`

`lab0/` must provide, from `module2/`:

| Target | Does |
| --- | --- |
| `make -C lab0 venv` | `~/.venvs/m2`: Kubespray's `requirements.txt` at `KUBESPRAY_VERSION` (it pins `ansible-core`), `kubernetes==PYTHON_KUBERNETES_VERSION`; then `kubernetes.core` and `ansible.posix` at their pinned versions into `~/.ansible/collections` |
| `make -C lab0 kubespray` | `~/kubespray`, a clone of `kubernetes-sigs/kubespray` at `KUBESPRAY_VERSION` (detached tag, read-only reference: never edited) |
| `make -C lab0 image` | builds `m2-node:latest` (Dockerfile in `lab0/node/`) |
| `make -C lab0 up` | network `m2` (`NODE_SUBNET`), `node1`…`node3` at **fixed IPs** `.11`–`.13`, their names in the console's `/etc/hosts`, `~/.ssh/id_ed25519` created if missing and authorized for user `ansible` |
| `make -C lab0 down` / `reset` | delete the nodes (and their volumes) / delete and recreate them blank |
| `make -C lab0 predownload` | trainer, the day before: runs Kubespray's `cluster.yml --tags download` on the nodes so that binaries and images are already there **(to validate: that the cache survives and that cluster.yml then skips the downloads)** |
| `make -C lab0 check` | venv, collections, Kubespray tag, nodes up, `ssh ansible@node1 true` |
| `make -C lab0 pull-consoles` | trainer, from their machine: `image up` in every console before session 1 |

Fixed IPs are deliberate: module 1 learned that restarted containers can
swap IPs, and Kubespray writes node IPs into certificates and kubeconfigs.

The node image is a **kind-like node without Kubernetes**: Kubespray
installs containerd, kubelet, etcd itself. Base `ubuntu:24.04` (a Kubespray
supported OS), with:

- `systemd` as PID 1, and kind's entrypoint logic (Apache-2.0,
  `kind/images/base/files/usr/local/bin/entrypoint`) for what a node in a
  container needs: `mount --make-rshared /`, cgroup v2 setup, `/dev/kmsg`;
- `openssh-server`, `python3`, `sudo`, `iproute2`, `iptables`, `kmod`,
  `ca-certificates`, `curl`; user `ansible` with passwordless sudo and no
  password (keys only) — bootstrapping that user is module 4's subject, not
  this one;
- run like kind runs its nodes: `--privileged`,
  `--security-opt seccomp=unconfined`, `--tmpfs /run --tmpfs /tmp`,
  `-v /lib/modules:/lib/modules:ro` (the dind sidecar mounts the server's),
  and **an anonymous volume on `/var`**, or containerd's overlayfs
  snapshotter fails on the dind overlay.

### What runs on the server, not in the node (trainer)

The nodes are privileged containers sharing the **server's kernel**. What
Kubespray does to the kernel, it does to the server, for the whole room:

- **swap**: Kubespray runs `swapoff -a` when it sees swap
  (`ansible_swaptotal_mb`, which is the host's). The server must have **no
  swap** before session 4 **(to validate: `swapon --show` on the server)**;
- **modules**: `modprobe` loads into the server kernel (`br_netfilter`,
  `overlay`, the CNI's). Harmless, but load them on the server beforehand so
  nothing depends on it;
- **sysctls**: `net.*` are per network namespace (the node's own);
  `vm.*`, `kernel.*`, `fs.*` that Kubespray sets are **global**. List them on
  the dry run and record them here **(to validate)**;
- **conntrack**: kube-proxy sets `nf_conntrack_max` unless told not to; kind
  sets `conntrack.maxPerCore: 0` for that reason. Find Kubespray's
  equivalent **(to validate)**.

Lab 1 step 2 is built on exactly this: what a container shares with its
host is a question for the trainees before Kubespray makes it a problem.

### If Kubespray does not run in containers

Fallback, decided at the dry run: the same labs on the trainees' machines
with VMs (Kubespray ships a `Vagrantfile`; 3 × 2 GiB), the inventory
pointing at their IPs. Nothing else in the module depends on the console.
Last resort: lab 3 demonstrated by the trainer on VMs, lab 3c's
`upgrade-cluster.yml` run live.

## Conventions

- **Run everything from `~/m2/`**, the trainee's project, with the venv
  active: `source ~/.venvs/m2/bin/activate`. The exercises repo is read-only
  reference: step files, given files and solutions are copied from it, never
  edited in place. `module2/versions.env` is sourced for the versions
  (`source ~/trainings_exercises/f021bis/module2/versions.env`).
- **Steps are directories**, `labN/stepM-<name>/README.md`, as in modules 1
  and 4: goal, what to write (not the whole solution), commands to check,
  questions to answer before moving on. Files the trainee is *given* sit next
  to the step file. The reference solution is `labN/solution/`, a complete
  `~/m2` at the end of that lab.
- **One repo**: `git init` in lab 1, at least one commit per step that
  changes code, a tag at the end of each lab (`lab1`, `lab2`, `lab3a`,
  `lab3b`, `lab3c`).
- **The test of a step is the second run**: every step that changes nodes or
  a cluster ends with "run it again, `changed=0`" and a check on the target
  (`ssh`, `kubectl`), not just the recap. Kubespray's playbooks are the
  exception (a full re-run is ~as long as the first); lab 3 says what to
  check instead.
- **FQCN** everywhere (`ansible.builtin.template`,
  `kubernetes.core.k8s`), as module 4 will require.
- **No secret in clear in Git**: Vault from lab 1 on, password file
  `~/.vault_pass` (mode 600), outside the repo, `vault_password_file` in
  `ansible.cfg`.
- **Kubespray is never edited**: `~/kubespray` stays at its tag; everything
  that is ours — inventory, `group_vars`, overrides — lives in `~/m2/inventory`.
  Playbooks are run as `ansible-playbook -i inventory ~/kubespray/cluster.yml`.
- **Contexts**: lab 2 uses kind's `kind-iac`; lab 3 uses Kubespray's
  `~/m2/inventory/artifacts/admin.conf` through `KUBECONFIG`. Check
  `kubectl config current-context` before anything destructive.

**Catch-up** (from `module2/`): `make catch-up-lab1` copies `lab1/solution/`
into `~/m2` (moving the existing one aside) and runs it;
`make catch-up-lab3a` does the same with `lab3/solution-3a/` and runs
`cluster.yml` (~ the lab's duration, **to validate**). Lab 2 needs no
catch-up: `iac` is rebuilt in step 1 in 2 minutes. Keep these in sync when
an end state changes.

## Prerequisites

| Tool | Where |
| --- | --- |
| `ansible-core` at Kubespray's pin, `kubernetes` Python client | `~/.venvs/m2` (`lab0 venv`). **Not** the console's Ubuntu `ansible` (2.16): Kubespray refuses versions outside its range |
| `kubernetes.core`, `ansible.posix` | `~/.ansible/collections` (`lab0 venv`) |
| `kubectl`, `helm` (v4), `kind`, `docker`, `git`, `ssh` | console image |
| `python3-venv` | console image (already there) |

`kubernetes.core.helm` drives the `helm` binary of the console: check that
the pinned collection supports Helm v4 **(to validate)**; if not, lab 0
installs a Helm v3 into `~/bin/helm3` and lab 2 step 4 sets `binary_path`.

## Lab 1 — Ansible refresher (session 1)

Slides: *Session 1* (`ansible_basics.md`), *Lab 1* (`lab_ansible_basics.md`).
60 min.

| | Step | ~ |
| --- | --- | --- |
| 1 | project, `ansible.cfg`, inventory with Kubespray's groups | 10 min |
| 2 | facts: what a container node shares with its host | 10 min |
| 3 | role `k8s_node_prereqs` | 25 min |
| 4 | idempotence: second run, `--check --diff` | 10 min |
| 5 | a secret in Vault | 5 min |

Start: `make -C lab0 check` green (the trainer ran `pull-consoles`).

1. **step1-project** — `~/m2`, `git init`, `.gitignore` (`.vault_pass`,
   `inventory/artifacts/`); `ansible.cfg`: `inventory = ./inventory`,
   `remote_user = ansible`, `become = true`, `roles_path = ./roles`,
   `vault_password_file = ~/.vault_pass`, `host_key_checking = False` (lab
   nodes are recreated). `inventory/hosts.yml` in YAML, the groups of
   Kubespray's sample inventory at `KUBESPRAY_VERSION` **(to validate the
   exact names in that release)**: `kube_control_plane: node1`, `etcd:
   node1`, `kube_node: node2`, `k8s_cluster` = children of the first ones;
   `node3` in a group `spare`. Each host has `ansible_host` = its fixed IP.
   Check: `ansible-inventory --graph`, `ansible all -m ansible.builtin.ping`.
   Question: why does `node3` exist but sit outside `k8s_cluster`?
2. **step2-facts** — ad-hoc `ansible.builtin.setup` with filters:
   `ansible_kernel`, `ansible_memtotal_mb`, `ansible_processor_vcpus`,
   `ansible_swaptotal_mb`, `ansible_virtualization_type`. Compare the
   kernel and memory of the three nodes with `uname -r` / `free -m` in the
   console. Questions (written down, answered in the debrief): what do the
   nodes share with each other and with the server? which of Kubespray's
   prerequisites (swap, modules, sysctls) are then really per node? This is
   the "what runs on the server" list above, found by the trainees.
3. **step3-role** — `ansible-galaxy role init roles/k8s_node_prereqs`,
   played by `site.yml` on `k8s_cluster`. Given: the list of modules and
   sysctls in a `defaults/main.yml` to complete. Tasks:
   - packages (`conntrack`, `socat`, `ipset`, `ebtables`) with
     `ansible.builtin.apt`, `cache_valid_time`;
   - `/etc/modules-load.d/k8s.conf` from a template looping over
     `k8s_modules`; handler: restart `systemd-modules-load`;
   - `ansible.posix.sysctl` for the **`net.*` keys only**, into
     `/etc/sysctl.d/99-k8s.conf` (a comment in the defaults says why: the
     others are global, step 2);
   - an `/etc/hosts` block (`ansible.builtin.blockinfile`) listing every host
     of the inventory from `hostvars` — Jinja over `groups['all']`;
   - `ansible.builtin.assert` that `ansible_swaptotal_mb == 0`, with a
     `fail_msg` that says why the role checks rather than fixes.
   No containerd, no `swapoff`: the role prepares, Kubespray installs; and a
   `swapoff` in these nodes would hit the server. The step file says so.
   Check: `ssh node2 cat /etc/hosts`, `lsmod | grep br_netfilter`.
4. **step4-idempotence** — run `site.yml` twice: second recap `changed=0`.
   Change one default (add a sysctl), run with `--check --diff`, read the
   diff, then apply. Then break it on purpose: replace the `blockinfile` by
   `ansible.builtin.shell: echo … >> /etc/hosts`, run twice, look at
   `/etc/hosts`; revert. Question: which of the role's tasks report
   `changed` in check mode but would not change anything, and why
   (handlers, `shell`)?
5. **step5-vault** — `group_vars/all/vault.yml` encrypted with
   `ansible-vault create`, holding `vault_ops_password`; `group_vars/all/main.yml`
   maps `ops_password: "{{ vault_ops_password }}"`; the role creates user
   `ops` with `password: "{{ ops_password | password_hash('sha512', 'm2salt') }}"`
   (fixed salt: or every run is `changed`). `git diff --staged` must show
   only ciphertext. Commit, tag `lab1`.

**End state** (start of lab 2 and lab 3): `~/m2` with `ansible.cfg`,
`inventory/hosts.yml`, `group_vars/all/{main,vault}.yml`, role
`k8s_node_prereqs`, `site.yml`; nodes prepared.

## Lab 2 — `kubernetes.core`, then Flux (session 3)

Slides: *Session 2* (`ansible_k8s.md`), *Session 3* (`iac_workflows.md`),
*Lab 2* (`lab_iac.md`). 70 min.

| | Step | ~ |
| --- | --- | --- |
| 1 | cluster `iac`, the collection, `localhost` | 10 min |
| 2 | an application from templates, a Secret from Vault | 15 min |
| 3 | read back, wait, re-run, and what Ansible does not delete | 10 min |
| 4 | a Helm release | 10 min |
| 5 | an operation: cordon, drain, uncordon | 10 min |
| 6 | hand over to Flux, then drift | 15 min |

Everything goes in `~/m2/k8s/` (its own `ansible.cfg`-less subdirectory,
playbooks run from `~/m2`), so lab 3 can reuse it against `spray`.

1. **step1-cluster** — given `lab2/kind.yaml` (1 control plane + 1 worker,
   `KIND_NODE`, NodePort 30081 on 127.0.0.1); `kind create cluster --name
   iac --config …`. Inventory addition: host `localhost` with
   `ansible_connection: local`,
   `ansible_python_interpreter: "{{ ansible_playbook_python }}"` (the venv's
   Python, which has the `kubernetes` client) in a group `k8s_api`.
   Group var `k8s_kubeconfig` (default `~/.kube/config`) and `k8s_context`
   (`kind-iac`), passed to every module through `module_defaults` for the
   group `group/kubernetes.core.k8s` **(to validate: the action group name in
   the pinned collection)**. Check: a playbook with `kubernetes.core.k8s_info`
   on `kind: Node`, `debug` of the names. Question: where does this task
   run, and what does it need on `node1`? (nothing — the API).
2. **step2-app** — playbook `k8s/app.yml`, vars per environment in
   `k8s/vars/{dev,prod}.yml` (`app_env`, `app_replicas`, `app_message`),
   loaded with `vars_files: "vars/{{ app_env | default('dev') }}.yml"`.
   Tasks, all `kubernetes.core.k8s`:
   - Namespace `web` (inline `definition`);
   - ConfigMap `web-page` with an `index.html` from a Jinja template
     (`template:` parameter of the module);
   - Secret `web-credentials` from a Vault-encrypted var in
     `k8s/vars/vault.yml` (`stringData`, `no_log: true`);
   - Deployment `web` (nginx, `app_replicas`, page mounted, an env var
     from the Secret) and Service NodePort 30081, from templates in
     `k8s/templates/`, `wait: true`.
   Check: `curl 127.0.0.1:30081` shows `app_message`. Then
   `-e app_env=prod`: replicas and message change.
3. **step3-state** — `kubernetes.core.k8s_info` on the Deployment with
   `wait: true` and `wait_condition` `Available`, then `assert` on
   `status.readyReplicas`; the same through
   `lookup('kubernetes.core.k8s', …)`. Run `app.yml` twice: `changed=0`.
   `--check --diff` after changing `app_replicas`. Then rename the
   ConfigMap in the template, run: **the old ConfigMap is still there**.
   Questions: who deletes it? what would `state: absent` for it look like,
   and when can you remove that task again? (this is the *prune* row of the
   comparison table, session 3).
4. **step4-helm** — `kubernetes.core.helm_repository` (podinfo's
   repo), `kubernetes.core.helm` release `podinfo` in namespace `podinfo`,
   `chart_version: PODINFO_CHART_VERSION`, `values` from a YAML dict in
   `k8s/vars/`, `wait: true`, `create_namespace: true`. Change
   `replicaCount`, run: a new revision (`helm history podinfo -n podinfo`).
   `kubernetes.core.helm_info` to read it back. Question: what does the
   module compare to decide `changed`?
5. **step5-drain** — playbook `k8s/maintenance.yml -e node=iac-worker`:
   `kubernetes.core.k8s_drain` `state: drain` with `delete_options`
   (`ignore_daemonsets`, `delete_emptydir_data`, `wait_timeout`), a
   `pause` standing for the maintenance, `state: uncordon`, then wait for
   `web` to be `Available` again. Before running it: add a PDB to `app.yml`
   (`minAvailable: 1`) and `app_replicas: 2`. Watch `kubectl get pods -o
   wide -w` in another tab. Question: compare with module 1 lab 3 — what
   did this playbook not do that you did by hand there?
6. **step6-flux** — playbook `k8s/flux.yml`: `ansible.builtin.get_url` of
   Flux's `install.yaml` at `FLUX_VERSION` (pinned URL, checksum), applied
   with `kubernetes.core.k8s src:`, wait for the controllers' Deployments
   in `flux-system`; then a `GitRepository` on
   `https://github.com/jeanparpaillon/trainings_exercises`, branch `main`,
   and a `Kustomization` on `./f021bis/module2/lab2/fleet` with
   `prune: true`, `interval: 1m`, both from templates. Given:
   `lab2/fleet/` — namespace `gitops`, podinfo Deployment + Service
   (plain manifests + `kustomization.yaml`). Then the drift test, written
   down before trying:
   - `kubectl -n gitops delete deploy podinfo` → back within the interval;
   - `kubectl -n web delete deploy web` → gone until `app.yml` runs again;
   - `kubectl -n gitops scale deploy podinfo --replicas=5` → ?
   The trainer pushes a commit to `lab2/fleet/` (replicas 2 → 3) during the
   step: every pair's `iac` follows it, nobody runs anything.
   Commit, tag `lab2`, then `kind delete cluster --name iac` (the room's
   memory goes to lab 3).

**End state**: `~/m2/k8s/` with `app.yml`, `maintenance.yml`, `flux.yml`,
`vars/`, `templates/`; no cluster.

## Lab 3 — Kubespray (sessions 4 and 5)

Slides: *Session 2* (`ansible_k8s.md`, Kubespray part), *Session 4*
(`kubespray.md`), *Lab 3* (`lab_kubespray_init.md`, `lab_kubespray_ops.md`,
`lab_kubespray_upgrade.md`).

| | Part | Step | ~ |
| --- | --- | --- | --- |
| 3a | deploy | 1 Kubespray's layout, our inventory | 10 min |
| | | 2 `group_vars`: the decisions | 15 min |
| | | 3 `cluster.yml` | 35 min |
| | | 4 kubeconfig, smoke tests, where things run | 15 min |
| 3b | day 2 | 5 add `node3`: `scale.yml` | 15 min |
| | | 6 remove `node2`: `remove-node.yml` | 20 min |
| 3c | upgrade | 7 baseline under load | 10 min |
| | | 8 `upgrade-cluster.yml`, `KUBE_FROM` → `KUBE_TO` | 30 min |
| | | 9 the whole chain: lab 2's `flux.yml` on `spray` | 10 min |

Durations of steps 3 and 8 are **(to validate)**: the dry run measures them
with `predownload` done, and the slides quote that number.

### 3a — deploy (session 4)

1. **step1-layout** — read `~/kubespray`: `cluster.yml` and what it
   imports (`playbooks/`), `roles/`, `inventory/sample/`. Copy
   `inventory/sample/group_vars/` into `~/m2/inventory/group_vars/`
   **merging** with lab 1's `group_vars/all/` (the step file says which
   files collide). Lab 1's `hosts.yml` is the inventory. Questions: which
   group gets etcd? what is `k8s_cluster` for?
2. **step2-vars** — edit `group_vars/k8s_cluster/k8s-cluster.yml` and
   `addons.yml`, each choice explained in the step file and on the slide:

   | Variable | Value | Why here |
   | --- | --- | --- |
   | `kube_version` | `KUBE_FROM` | lab 3c upgrades it |
   | `container_manager` | `containerd` | the default; the only one module 1 used |
   | `kube_network_plugin` | `flannel` **(to validate: VXLAN in nested containers; else `calico` in VXLAN mode)** | lightest; no BGP |
   | `kube_proxy_mode` | `iptables` | `ipvs` (default) needs IPVS modules in the server kernel |
   | `enable_nodelocaldns` | `false` | a dummy interface + link-local IP per node: one more kernel dependency, and memory |
   | `etcd_deployment_type` | `host` (default) | etcd as a systemd unit — contrast with kind/kubeadm's static pod |
   | `kubeconfig_localhost` | `true` | `admin.conf` into `inventory/artifacts/` |
   | `cluster_name` | `spray.local` | |

   Given: `lab3/group_vars/k8s_cluster/zz-containers.yml`, the overrides
   that only exist because nodes are containers (preflight errors to ignore,
   conntrack, …, **filled at the dry run**), each with a comment. Commit
   *before* running: the cluster's definition is the commit.
3. **step3-cluster** — `ansible-playbook -i inventory ~/kubespray/cluster.yml`
   (become comes from `ansible.cfg`), `time` in front of it. While it runs:
   the step file has a reading list — the role names scrolling by vs
   `cluster.yml`'s plays, which plays target `etcd`, `kube_control_plane`,
   `kube_node`, where kubeadm is called — and questions. If it fails: read
   the failed task, fix the var, re-run (it resumes nothing: it re-checks
   everything, faster the second time).
4. **step4-smoke** — `export KUBECONFIG=~/m2/inventory/artifacts/admin.conf`;
   `kubectl get nodes -o wide`, `get pods -A`; `ssh node1 systemctl status
   etcd`, `ssh node1 ls /etc/kubernetes/manifests` (no etcd there);
   `crictl ps` on `node2`; a test Deployment + `nslookup kubernetes` from a
   pod. Compare with a kind cluster: what is the same (kubeadm, static
   pods), what is not (etcd, CNI, how the node got its binaries). Commit,
   tag `lab3a`.

**End state 3a**: `spray` at `KUBE_FROM`, `node1` control plane + etcd,
`node2` worker; `~/m2/inventory` complete.

### 3b — day 2 (end of session 4)

5. **step5-scale** — move `node3` from `spare` to `kube_node`, commit.
   `ansible-playbook -i inventory ~/kubespray/playbooks/facts.yml` then
   `~/kubespray/scale.yml --limit=node3` **(to validate: the facts-first
   procedure of the pinned release's `docs/operations/nodes.md`)**.
   Questions: why `--limit`? why must facts be gathered on all nodes first?
   Check: 3 nodes `Ready`, `node3` has a flannel pod.
6. **step6-remove** — a Deployment with 3 replicas and a PDB
   (`minAvailable: 2`) on the cluster first. Then
   `~/kubespray/remove-node.yml -e node=node2` (it asks for confirmation,
   then drains, resets the node, deletes it from the API). Watch the pods
   move. Then remove `node2` from `kube_node` in `hosts.yml` (back to
   `spare`) and commit. Questions: what if the inventory is not updated and
   someone runs `cluster.yml`? What did `reset` leave on `node2` (`ssh node2
   ls /etc/kubernetes`)? Tag `lab3b`.

**End state 3b**: `node1` + `node3`; `node2` reset, in `spare`.

### 3c — upgrade (session 5)

7. **step7-baseline** — the test Deployment from step 6 (2 replicas, PDB
   `minAvailable: 1`, readiness probe) behind a NodePort; given
   `lab3/load`: a `curl` loop in the console, one request every 0.2 s,
   printing failures with timestamps (module 1 used k6; a loop is enough
   here and needs nothing). Record the current versions
   (`kubectl version`, `kubectl get nodes`).
8. **step8-upgrade** — `kube_version: KUBE_TO` in `k8s-cluster.yml`,
   commit, then `~/kubespray/upgrade-cluster.yml`. Watch, in other tabs:
   `kubectl get nodes -w`, the load loop. Questions, compared with module
   1 lab 3: in which order did nodes go? who drained? what controls how
   many at a time (`serial`), how long a drain may take (`drain_timeout`),
   what happens to a PDB that blocks (`drain_grace_period`, failure)? Count
   the failed requests. Tag `lab3c`.
9. **step9-chain** — `ansible-playbook k8s/flux.yml -e
   k8s_kubeconfig=~/m2/inventory/artifacts/admin.conf -e
   k8s_context=<Kubespray's context name>`: the same `fleet/` now runs on
   `spray`. Write down the chain as commands, from empty nodes:
   `lab0 up` → `site.yml` → `cluster.yml` → `flux.yml` — that list is the
   slide *IaC end to end*, filled by the room.

**End state**: `spray` at `KUBE_TO`, Flux on it reconciling `lab2/fleet`.
Delete it at the end of the module (`make -C lab0 down`).

## Size (trainer)

Nothing measured yet; estimates to replace on the dry run **(to validate)**:

| What | Per pair | 4 pairs |
| --- | --- | --- |
| lab 1: 3 nodes, no Kubernetes | ~150 MiB | ~0.6 GiB |
| lab 2: kind `iac`, 2 nodes, nginx, podinfo, Flux | ~1.5 GiB | ~6 GiB |
| lab 3: `spray`, 2–3 nodes, flannel, CoreDNS | ~2 GiB | ~8 GiB |
| console: `ansible-playbook` of Kubespray | ~300 MiB, in the console's 2 GiB limit | |

`iac` must be deleted before lab 3 starts, and lab 1's nodes stay up through
lab 2 (small). CPU is the other limit: `cluster.yml` with 4 pairs starting
together loads the server's 4 CPUs; stagger the starts by a few minutes if
the dry run shows timeouts. Disk: Kubespray's binaries and images, ~1.5 GiB
per node **(to validate)**, on the console's 30 GiB Docker PVC.

## Files to write

```
module2/
  README.md            this file
  versions.env         pinned versions (TODO values to fill)
  Makefile             catch-up-lab1, catch-up-lab3a
  lab0/                Makefile, node/{Dockerfile,entrypoint}
  lab1/                README.md, step1…5/, solution/
  lab2/                README.md, kind.yaml, fleet/, step1…6/, solution/
  lab3/                README.md, group_vars/k8s_cluster/zz-containers.yml,
                       load, step1…9/, solution-3a/, solution/
```
