# Module 4 — security and advanced governance

Exercises for day 4 of **F021 — Advanced Kubernetes**. The slides are in
`../../training_f021/slides/pages/module4.md`; every step here names the slide
it belongs to.

| | | Slot |
| --- | --- | --- |
| `lab1/` | least privilege for people and pods | 2 (11h–12h30) |
| `lab2/` | Pod Security, network policies, secrets | 3 (14h–15h30) |
| `advanced/` | one exercise per attendee or pair: red / blue team, policy-as-code, compliance evidence | 4 (16h20–17h10) |

Still [Bookinfo](https://istio.io/latest/docs/examples/bookinfo/), as tuned on
day 3. Until now, every lab ran as cluster-admin in a wide-open namespace.
Today the namespace becomes a locked-down tenant — least-privilege RBAC,
Pod Security Standards, default-deny networking, secrets out of git, an audit
trail — and Bookinfo has to keep working in it.

## Conventions

Same as days 1 to 3:

- **One namespace per attendee.** Every command is `kubectl -n "$NS" ...`.
- **Steps are cumulative kustomize overlays.** `kubectl -n "$NS" apply -k
  lab2/step4-default-deny` lands you at the end of step 4 from anywhere.
- **Read the diff, not just the file**:
  `diff <(kubectl kustomize <prev>) <(kubectl kustomize <this>)`.

New today:

- **Two contexts.** From lab 1 on you work as `developer`. The `admin`
  context is the *platform team's* hat: use it only for steps marked
  **(admin)** — namespace labels, RBAC, cluster policies, playing the
  attacker. If you catch yourself switching to `admin` to get past an error,
  that is a finding: write it down for the debrief.
- **Every refusal has a reason somewhere.** Before fixing anything, find
  where the refusal is explained: `kubectl auth can-i`, the apply warning,
  the ReplicaSet events, the policy report, the proxy's authorization
  metrics, the audit log.

## Prerequisites

- everything from modules 1 to 3: `kubectl`, `linkerd` CLI, `helm`,
  `docker`, Linkerd + linkerd-viz, the day-3 add-ons
- `openssl`, `jq` and `yq`
- `kubectl` plugins through [krew](https://krew.sigs.k8s.io/):

  ```sh
  kubectl krew install who-can rbac-tool
  ```

- [`audit2rbac`](https://github.com/liggitt/audit2rbac) (lab 1 step 2),
  [`sops`](https://github.com/getsops/sops) and
  [`age`](https://github.com/FiloSottile/age) (lab 2 step 7),
  [`cosign`](https://docs.sigstore.dev/cosign/) and
  [`kyverno`](https://kyverno.io/docs/kyverno-cli/) CLI (slot 4) — single
  binaries from their release pages

### The cluster

On the **shared cluster** the trainer has prepared everything before the
session: API server audit logging, a CNI that enforces NetworkPolicy,
Linkerd running with its CNI plugin, Kyverno, External Secrets Operator, a
Vault dev server, the Bookinfo MySQL in the `bookinfo-db` namespace, and your
`developer` kubeconfig.

On **kind**, recreate the cluster with this module's config: the three
zone-labelled workers of module 2, plus an audit policy and an audit log
written to `/var/log/kubernetes/audit.log` on the control-plane node. The
audit log can only be turned on when the API server starts, hence the
recreation. kindnet, kind's default CNI, enforces NetworkPolicy since kind
0.24.

```sh
make delete
kind create cluster --name training --config module4/kind.yaml
make ingress
```

Then Linkerd, **with its CNI plugin** this time. The `linkerd-init` container
of days 1–3 needs `NET_ADMIN` and `NET_RAW` to set up iptables, which Pod
Security `baseline` refuses; with the CNI plugin the node does that work
instead (slide "The sidecar meets Pod Security"):

```sh
linkerd install-cni | kubectl apply -f -
linkerd check --pre --linkerd-cni-enabled
linkerd install --crds | kubectl apply -f -
linkerd install --linkerd-cni-enabled | kubectl apply -f -
linkerd viz install | kubectl apply -f -
linkerd check
```

The add-ons of the day:

```sh
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo add external-secrets https://charts.external-secrets.io
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

helm install kyverno kyverno/kyverno -n kyverno --create-namespace
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace
# dev mode: in memory, unsealed, root token "root" — never outside a lab
helm install vault hashicorp/vault -n vault --create-namespace \
  --set server.dev.enabled=true --set server.dev.devRootToken=root
```

Reinstall the module 3 add-ons (metrics-server, VPA, Prometheus Adapter) as
in the module 3 README, and `kind load` your day-3 images again.

## Starting state

Day 4 starts from the **end of module 3**: lab 2 step 8, right-sized, with its
autoscalers, the rebuilt `reviews` image and the topology-aware `reviews`
Service.

```sh
export NS=<your-namespace>
kubectl create namespace "$NS"                # kind: the cluster is new
kubectl -n "$NS" apply -k ../module3/lab2/step8-topology
linkerd -n "$NS" viz stat deploy              # every deployment meshed, 100 % success
kubectl -n "$NS" get pod -l app=productpage -o jsonpath='{.items[0].spec.initContainers[*].name}'
# linkerd-network-validator, not linkerd-init: the CNI plugin is in use
```

If you do not have the day-3 images, start from `../module3/lab1/step6-hpa-rps`
instead: it only uses the stock Bookinfo images.

Keep `linkerd viz dashboard` open in a second window, and the product page in
a browser: after every step, the page must still render with stars.

---

## Lab 1 — least privilege for people and pods

**Slot 2 (11h–12h30).** You lose cluster-admin, and Bookinfo still works.
Then the same question for the pods: what can each one do with the credential
it carries?

| | Step | Slide | ~ |
| --- | --- | --- | --- |
| 0 | `step0-identity` | Lab 1 — setup: a developer identity | 10 min |
| 1 | `step1-developer` | Lab 1 — lose cluster-admin | 15 min |
| 2 | `step2-extra-role` | Lab 1 — ask for the right role | 15 min |
| 3 | `step3-sa-tokens` | Lab 1 — what a pod's token can do | 15 min |
| 4 | `step4-short-lived` | Lab 1 — short-lived tokens | 10 min |
| 5 | `step5-escalation` | Lab 1 — escalation hunt | 10 min + 15 debrief |

### Step 0 — a developer identity

Shared cluster: the trainer gives you a kubeconfig with a `developer`
context. Skip to the check at the end of this step.

On kind, Kubernetes has no user objects — you *become* a user by presenting a
credential the API server trusts. Here, a client certificate signed by the
cluster CA through the CSR API: the common name is the user, the organisation
is the group. **(admin)**:

```sh
openssl genrsa -out dev.key 2048
openssl req -new -key dev.key -subj "/CN=dev-$NS/O=developers" -out dev.csr

cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: dev-$NS
spec:
  request: $(base64 -w0 dev.csr)
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400
  usages: [client auth]
EOF
kubectl certificate approve "dev-$NS"
kubectl get csr "dev-$NS" -o jsonpath='{.status.certificate}' | base64 -d > dev.crt

kubectl config set-credentials developer \
  --client-certificate=dev.crt --client-key=dev.key --embed-certs
kubectl config set-context developer --cluster=kind-training \
  --user=developer --namespace="$NS"
kubectl config rename-context kind-training admin
```

Check who you are, and what you can do:

```sh
kubectl --context developer auth whoami
kubectl --context developer auth can-i --list -n "$NS"
```

**Questions:** the certificate is valid 24 h — how would you revoke it before
that, if the laptop were stolen? Why is the group, not the user name, what
should appear in bindings?

### Step 1 — lose cluster-admin

**(admin)** apply the step: a `developer` Role in your namespace, bound to the
group `developers`.

```sh
kubectl --context admin -n "$NS" apply -k lab1/step1-developer
kubectl config use-context developer
kubectl auth can-i --list
```

The Role reads workloads, services, config maps and pod logs, and creates,
updates and deletes deployments, services, config maps and jobs. It does
**not** read secrets, exec into pods, port-forward, or add ephemeral
containers.

Now replay your day-3 workflow as `developer`, and note what fails and with
which message:

```sh
kubectl -n "$NS" rollout restart deploy/productpage
kubectl -n "$NS" apply -f ../module3/k6/ramp.yaml
kubectl -n "$NS" top pods --containers
kubectl -n "$NS" edit hpa productpage
kubectl -n "$NS" get httproute
linkerd -n "$NS" viz stat deploy
kubectl -n "$NS" port-forward svc/productpage 9080
kubectl -n "$NS" debug -it deploy/productpage --image=nicolaka/netshoot --target=productpage
kubectl -n "$NS" get secrets
```

**Questions:** which of these losses are fine, and which block a developer's
real work? `kubectl top` and `linkerd viz stat` do not read your namespace
directly — what do they call, and who must grant it? Why is `list secrets`
worse than it sounds?

### Step 2 — ask for the right role

Write, in `lab1/step2-extra-role/extra-role.yaml`, the **minimal** extra Role
for what step 1 showed you actually need — HPA, VPA, PDB, HTTPRoute, whatever
you found. One rule per API group, explicit resources and verbs, no `*`.

```sh
kubectl auth can-i patch horizontalpodautoscalers.autoscaling -n "$NS"   # no
```

Hand it to the platform team: **(admin)** review it — would you apply it as a
platform engineer? — then apply the step.

```sh
kubectl --context admin -n "$NS" apply -k lab1/step2-extra-role
```

Now compare with a role generated from what you really did. The audit log
records every request of your `developer` user since step 0. On kind, copy it
from the control-plane node; on the shared cluster, the trainer gives you your
extract:

```sh
docker cp training-control-plane:/var/log/kubernetes/audit.log .
audit2rbac -f audit.log --user "dev-$NS" --namespace "$NS" > generated-role.yaml
```

**Questions:** what did audit2rbac generate that you did not ask for, and why
(think of the failed requests in step 1)? What did you ask for that it did not
see? Would you ever apply its output as is?

### Step 3 — what a pod's token can do

Every Bookinfo pod has its own ServiceAccount since day 1, and every one of
them carries a token for the API server — which none of them ever calls.
Look:

```sh
kubectl -n "$NS" get pod -l app=ratings \
  -o jsonpath='{.items[0].spec.volumes[*].name}'   # kube-api-access-xxxxx
```

The step sets `automountServiceAccountToken: false` on the four
ServiceAccounts. Apply it, restart, and check the volume is gone.

Then the deliberate mistake. The step's `compromised/` overlay re-enables the
token on `bookinfo-ratings` and binds it to a Role that can `list` secrets —
the kind of binding someone adds "just for a debug session". **(admin)**
apply it, create a dummy secret, then play the attacker who has found a remote
code execution in `ratings`:

```sh
kubectl --context admin -n "$NS" apply -k lab1/step3-sa-tokens/compromised
kubectl --context admin -n "$NS" create secret generic db-password --from-literal=password=s3cr3t
POD=$(kubectl -n "$NS" get pod -l app=ratings -o jsonpath='{.items[0].metadata.name}')
kubectl --context admin -n "$NS" debug -it "$POD" --image=nicolaka/netshoot --target=ratings -- sh
# inside:
TOKEN=$(cat /proc/1/root/var/run/secrets/kubernetes.io/serviceaccount/token)
NS=$(cat /proc/1/root/var/run/secrets/kubernetes.io/serviceaccount/namespace)
curl -sk -H "Authorization: Bearer $TOKEN" \
  https://kubernetes.default.svc/api/v1/namespaces/$NS/secrets | jq '.items[].data'
```

Revert with `kubectl --context admin -n "$NS" apply -k lab1/step3-sa-tokens`,
then delete the leftover RoleBinding the overlay created.

**Questions:** what did the attacker need besides the RCE? What would the same
attack have given with the token disabled — and with the token enabled but no
binding? Which of *your* services actually need to talk to the API server?

### Step 4 — short-lived tokens

A token for a job or a test, valid ten minutes:

```sh
TOKEN=$(kubectl --context admin -n "$NS" create token bookinfo-ratings --duration=10m)
echo "$TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | jq '{sub, aud, exp: (.exp|todate)}'
```

Bind one to a pod instead, then delete the pod and try to use it:

```sh
TOKEN=$(kubectl --context admin -n "$NS" create token bookinfo-ratings \
  --bound-object-kind Pod --bound-object-name "$POD")
kubectl --token="$TOKEN" auth whoami                   # works
kubectl --context admin -n "$NS" delete pod "$POD"
kubectl --token="$TOKEN" auth whoami                   # rejected
```

Now the old way: a Secret of type `kubernetes.io/service-account-token`
(the step's `legacy-token.yaml`). **(admin)** apply it, read its token, decode
it: look for `exp`. Then find every such Secret in the cluster:

```sh
kubectl --context admin get secrets -A --field-selector type=kubernetes.io/service-account-token
```

**Questions:** a CI pipeline deploys to this namespace — which kind of token
should it hold, and who issues it? What does a leaked legacy token give, and
for how long?

### Step 5 — escalation hunt

**(admin)** apply the step. It creates five ServiceAccounts, each with a Role
that looks reasonable for its job: `ci-deployer`, `support`, `team-lead`,
`auditor`, `ops-helper`.

```sh
kubectl --context admin -n "$NS" apply -k lab1/step5-escalation
```

Find which of them can end up with **more** than they were given — and
how. Candidates: creating pods (with any SA of the namespace, or with a
`hostPath`), reading secrets, `bind`, `escalate`, `impersonate`, wildcards.

```sh
kubectl who-can list secrets -n "$NS"
kubectl who-can create pods -n "$NS"
kubectl rbac-tool policy-rules -e '^system:' | grep "$NS"
kubectl rbac-tool analysis
kubectl auth can-i --list -n "$NS" --as="system:serviceaccount:$NS:team-lead"
```

For each escalation you find, prove it with `--as`, and write the one-line
fix to its Role.

**Questions:** one of them can reach the node itself — what stops it today?
(Nothing yet: lab 2 Part A.) Which verbs would you forbid in every dev team's
Role, whatever they ask for?

**Debrief (15 min):** the RBAC request template a dev team sends to the
platform team — subject, namespace, resources and verbs, justification,
duration, approver.

---

## Lab 2 — Pod Security, network policies, secrets

**Slot 3 (14h–15h30).** Three parts of 30 minutes, cumulative. Starts from
the end of lab 1 step 3 — steps 4 and 5 leave nothing you want to keep:

```sh
kubectl --context admin -n "$NS" delete -k lab1/step5-escalation
kubectl --context admin -n "$NS" apply -k lab1/step3-sa-tokens
```

| | Step | Slide | ~ |
| --- | --- | --- | --- |
| 1 | `step1-pss-baseline` | Lab 2 — baseline, warn restricted | 10 min |
| 2 | `step2-restricted` | Lab 2 — enforce restricted | 10 min |
| 3 | `step3-kyverno` | Lab 2 — Kyverno | 10 min |
| 4 | `step4-default-deny` | Lab 2 — default deny | 15 min |
| 5 | `step5-prove` | Lab 2 — prove it | 5 min |
| 6 | `step6-authz` | Lab 2 — identity on top of network | 10 min |
| 7 | `step7-secrets` | Lab 2 — one credential, three ways | 20 min |
| 8 | `step8-rotation` | Lab 2 — rotation | 10 min + 15 debrief |

### Part A — Pod Security

#### Step 1 — baseline, warn restricted

**(admin)** label the namespace: `baseline` enforced, `restricted` in warn and
audit mode.

```sh
kubectl --context admin label ns "$NS" \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/warn=restricted \
  pod-security.kubernetes.io/audit=restricted
```

As `developer`, restart everything and read the warnings:

```sh
kubectl -n "$NS" rollout restart deploy
kubectl -n "$NS" apply -k lab2/step1-pss-baseline 2>&1 | grep -i warning
```

`enforce` only checks *pods*: a Deployment is always accepted, it is its
ReplicaSet that fails to create pods. If a pod does not come back, look there:

```sh
kubectl -n "$NS" get rs
kubectl -n "$NS" describe rs <name> | sed -n '/Events/,$p'
```

Build a table: for each container of each pod — **including the injected
ones** — which `restricted` rule it breaks.

**Questions:** what is the init container of a meshed pod now, and why would
the `linkerd-init` of days 1–3 have been refused under `baseline`? Why does
the platform team have to fix that, not you?

#### Step 2 — enforce restricted

The step adds a `securityContext` to every Deployment — at pod level
(`runAsNonRoot`, `seccompProfile: RuntimeDefault`) and container level
(`allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`,
`readOnlyRootFilesystem: true`) — and an `emptyDir` for each path the
application writes to. Before applying it, check which images run as root:

```sh
docker inspect registry.istio.io/release/examples-bookinfo-ratings-v1:1.20.3 \
  --format '{{.Config.User}}'           # empty = root
kubectl -n "$NS" logs deploy/reviews-v2 -c reviews | grep -i -E 'denied|read-only'
```

Where an image has no numeric user, the step sets `runAsUser`. Apply, fix what
does not start (logs, events), then **(admin)** switch to enforce:

```sh
kubectl -n "$NS" apply -k lab2/step2-restricted
kubectl --context admin label ns "$NS" --overwrite \
  pod-security.kubernetes.io/enforce=restricted
kubectl -n "$NS" rollout restart deploy
kubectl -n "$NS" get pods                  # all Ready, no warning
```

**Questions:** your rebuilt `reviews` image from day 3 — did it pass
`runAsNonRoot`, and why does `runAsNonRoot` refuse a user *name*? Which paths
did Liberty want to write to? The `team-lead` of lab 1 step 5 — can it still
reach the node?

#### Step 3 — Kyverno

Two namespaced Kyverno `Policy` objects, applied **(admin)**:

- `mutate-securitycontext` adds `seccompProfile: RuntimeDefault` and drops
  all capabilities on any container that says nothing
- `allowed-registries` rejects any image not from `registry.istio.io`,
  `cr.l5d.io` or the training registry

```sh
kubectl --context admin -n "$NS" apply -k lab2/step3-kyverno
kubectl -n "$NS" run bare --image=registry.istio.io/release/examples-bookinfo-details-v1:1.20.3 \
  --dry-run=server -o yaml | yq '.spec.containers[0].securityContext'
kubectl -n "$NS" run nginx --image=nginx       # read the denial
kubectl -n "$NS" get policyreport -o wide
```

**Questions:** the mutation made `bare` pass `restricted` — is that good? What
does the developer see in git, and what runs? What is already non-compliant in
the policy report?

### Part B — network policies

#### Step 4 — default deny

The step starts with one policy: every pod in the namespace, ingress and
egress, nothing allowed. Apply it and watch Bookinfo die — product page,
`linkerd viz stat`, the pods' readiness.

```sh
kubectl -n "$NS" apply -k lab2/step4-default-deny
```

The step then ships the policies that bring it back, in
`lab2/step4-default-deny/allow/`, **one file per flow**. Add them one at a
time, and for each one write down the symptom it fixed:

| File | Allows |
| --- | --- |
| `dns.yaml` | egress to `kube-dns` in `kube-system`, UDP and TCP 53 |
| `ingress-productpage.yaml` | `ingress-nginx` namespace → `productpage` |
| `productpage-out.yaml` | `productpage` → `details`, `reviews` |
| `reviews-ratings.yaml` | `reviews` → `ratings` |
| `linkerd.yaml` | proxies → `linkerd` control plane; `linkerd-viz` → proxies (4191); the proxy inbound port 4143 |

```sh
kubectl -n "$NS" apply -f lab2/step4-default-deny/allow/dns.yaml
# ...one by one
kubectl -n "$NS" get networkpolicy
```

**Questions:** which one did you need first, and why was it not a Bookinfo
flow? What broke when the mesh policy was missing, even with every app flow
open? What would a CNI that does not enforce NetworkPolicy have shown you?

#### Step 5 — prove it

A policy set is only as good as the test that shows it denies. **(admin)**
debug containers, since `developer` can't:

```sh
DETAILS=$(kubectl -n "$NS" get pod -l app=details -o jsonpath='{.items[0].metadata.name}')
kubectl --context admin -n "$NS" debug -it "$DETAILS" --image=nicolaka/netshoot \
  --target=details -- curl -m 3 -s http://ratings:9080/ratings/0     # must time out
```

Then from outside the namespace — a neighbour's namespace on the shared
cluster, or a scratch one on kind:

```sh
kubectl --context admin create ns scratch
kubectl --context admin -n scratch run curl --rm -it --image=nicolaka/netshoot -- \
  curl -m 3 -s http://productpage.$NS:9080/productpage        # must time out
```

And the positive test: the product page still renders, with stars.

**Questions:** `details` → `ratings` was refused — by the network policy or
by something else? How do you tell a timeout caused by a policy from one
caused by a dead pod? What tooling would show you the dropped flows directly
(Hubble, Calico flow logs)?

#### Step 6 — identity on top of network

Only `reviews` should call `ratings`. The step adds a Linkerd `Server` for
port 9080 of `ratings`, an `AuthorizationPolicy` on it, and a
`MeshTLSAuthentication` allowing a single identity — the `bookinfo-reviews`
ServiceAccount:

```sh
kubectl -n "$NS" apply -k lab2/step6-authz
linkerd -n "$NS" viz authz deploy/ratings-v1
```

Now the step's `open-network.yaml` makes a mistake on purpose: a
NetworkPolicy that opens `ratings` to the whole namespace. Apply it and call
`ratings` from `productpage` **(admin)**:

```sh
kubectl -n "$NS" apply -f lab2/step6-authz/open-network.yaml
kubectl --context admin -n "$NS" exec deploy/productpage -c productpage -- \
  python -c "import urllib.request as u; print(u.urlopen('http://ratings:9080/ratings/0').status)"
```

The network lets it through; the proxy of `ratings` answers 403. Look for the
denied requests in `linkerd viz authz`. Delete `open-network.yaml` afterwards.

**Questions:** what does the proxy know about the caller that the network
policy does not? Who can obtain the `bookinfo-reviews` identity — and how does
lab 1 constrain that? If you could keep only one of the two mechanisms, which?

### Part C — secrets

#### Step 7 — one credential, three ways

`ratings-v2` reads its ratings from MySQL. The database runs in the
`bookinfo-db` namespace — the trainer's on the shared cluster; on kind,
**(admin)** `kubectl apply -k lab2/step7-secrets/mysql`. The step deploys
`ratings-v2-mysql` in your namespace, with the egress policy to reach MySQL on
3306, and scales `ratings-v1` to 0. Its password, three ways:

**a. A plain Secret** — `lab2/step7-secrets/a-plain/`:

```sh
kubectl -n "$NS" apply -k lab2/step7-secrets/a-plain
cat lab2/step7-secrets/a-plain/secret.yaml                # in git, in clear
kubectl -n "$NS" get secret ratings-db -o yaml            # refused for developer
kubectl --context admin -n "$NS" get secret ratings-db -o jsonpath='{.data.password}' | base64 -d
```

**b. SOPS + age** — encrypted in the repo, decrypted at apply time:

```sh
age-keygen -o age.key
export SOPS_AGE_KEY_FILE=$PWD/age.key
cd lab2/step7-secrets/b-sops
sops --encrypt --age "$(grep -o 'age1.*' ../../../age.key)" \
  --encrypted-regex '^(data|stringData)$' secret.yaml > secret.enc.yaml
cat secret.enc.yaml                                        # what git would hold
sops --decrypt secret.enc.yaml | kubectl -n "$NS" apply -f -
cd -
```

**c. External Secrets Operator + Vault** — git holds only a reference. Put the
password in Vault (on kind; on the shared cluster the trainer has done it
under a path per namespace):

```sh
kubectl -n vault exec vault-0 -- vault kv put secret/$NS/ratings-db password=s3cr3t
kubectl -n "$NS" apply -k lab2/step7-secrets/c-eso
kubectl -n "$NS" get secretstore,externalsecret
kubectl -n "$NS" describe externalsecret ratings-db | sed -n '/Status/,$p'
```

The product page must show stars from `ratings-v2` after each variant.

**Questions:** in each variant, who can read the password — in git, in the
cluster, in the store? Where does the age private key live in a real team,
and who in the CI? What must be true about the `SecretStore`'s own credential
to Vault, and what did the ESO variant move rather than remove?

#### Step 8 — rotation

Change the password in Vault — and in MySQL, or the database will reject the
new one (the step ships the `ALTER USER` Job, **(admin)** on kind):

```sh
kubectl -n vault exec vault-0 -- vault kv put secret/$NS/ratings-db password=n3w-s3cr3t
kubectl --context admin -n bookinfo-db apply -f lab2/step8-rotation/alter-user-job.yaml
```

Watch the chain, link by link:

```sh
kubectl -n "$NS" get externalsecret ratings-db -w             # refreshInterval: 1m in this step
kubectl -n "$NS" get secret ratings-db -o jsonpath='{.metadata.resourceVersion}'
kubectl -n "$NS" logs deploy/ratings-v2-mysql -c ratings --tail=20
```

The Secret changes, the pod does not: it read the password from an env var at
startup. Restart it, and it works again. Then apply the step's variant that
mounts the secret as a file and adds a checksum annotation.

**Questions:** how long was `ratings` broken, and what would have shortened
it? Env var or mounted file — which one updates, and does the application
re-read it? What do dynamic database credentials (Vault's database engine)
change in this picture?

**Debrief (15 min):** which secret option fits which SGA team — git-centric
with no vault, or a central vault — and what each one changes in the pipeline.
Same question for PSS labels and NetworkPolicies: platform template, or next
to the application?

---

## Slot 4 — audit and advanced exercises

**16h–16h20: live demo** by the trainer — tailing the audit log while
attendees `exec` into a pod and read a secret, the same events in the log UI
with an alert rule, then kube-bench and kubescape reports read together.

On kind, you can follow along:

```sh
docker exec training-control-plane tail -f /var/log/kubernetes/audit.log \
  | jq -c 'select(.objectRef.namespace=="'"$NS"'") | {user: .user.username, verb, res: .objectRef.resource, sub: .objectRef.subresource, code: .responseStatus.code}'
```

**16h20–17h10: one exercise per attendee** (or pair), in `advanced/`. Each
pair shows **one finding** at 17h05.

### Exercise A — red team / blue team

In pairs, on the shared cluster (or two namespaces on one kind cluster).

- **Blue** keeps the tenant hardened in lab 2 and watches: the audit log,
  NetworkPolicy drops (Hubble or Calico flow logs on the shared cluster),
  `linkerd viz authz`, Kyverno reports.
- **Red** gets a `developer`-level kubeconfig on blue's namespace, and a
  shell in blue's `ratings` pod (the trainer sets both up). Goals, in any
  order: reach another tenant's `productpage`, read a secret, get more
  rights than `developer`.

Blue writes down what red did — from the traces only — before red tells.
Swap after 20 minutes.

**Questions:** what did red try that left no trace at all? Which layer
stopped each attempt? What would blue add to the alert rules after this?

### Exercise B — policy-as-code

Write Kyverno policies for the day-3 rules, all in audit mode
(`failureAction: Audit` on each rule):

- CPU and memory requests set on every container, memory limit set
- readiness and liveness probes present
- images from the allowed registries, never tagged `latest`
- an `owner` label on every Deployment

```sh
kubectl --context admin -n "$NS" apply -f advanced/exercise-b/
kubectl -n "$NS" get policyreport -o wide
```

Read the reports, then move one policy to `Enforce` and fix the manifests it
rejects. Bonus: run the same policies against the kustomize output **before**
the cluster, as a CI job would:

```sh
kubectl kustomize lab2/step8-rotation | kyverno apply advanced/exercise-b/ --resource -
```

**Questions:** which policy would you put in `Enforce` on day one on a real
cluster, and which would you leave in `Audit` for a month? Why check in CI when
admission already checks?

### Exercise C — compliance evidence

Write `advanced/exercise-c/evidence.sh`: for one namespace, it produces a
timestamped directory an internal auditor can read.

1. RBAC: every Role and RoleBinding, and who can read secrets or exec
   (`kubectl who-can`)
2. Pod Security labels of the namespace
3. NetworkPolicies, and Linkerd authorization policies
4. Kyverno policy reports
5. image signatures: `cosign verify` on each image running in the namespace
   (keyless or the trainer's public key) — record what fails, too
6. one day of the audit log for the namespace: `exec`, secret reads, RBAC
   changes

**Questions:** which item was the hardest to produce, and why? What would make
this evidence come for free — the same answer as day 5's?

## Cleanup

Keep the namespace as it is — labels, policies, secrets and all. Tomorrow it
goes through a GitOps pipeline, and nobody should need the `admin` context
anymore.

```sh
kubectl --context admin delete ns scratch --ignore-not-found
kubectl --context admin delete csr "dev-$NS"
```
