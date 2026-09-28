# Module 5 — CI/CD, the SGA use-case

Exercises for day 5 of **F021 — Advanced Kubernetes**. The slides are in
`../../training_f021/slides/pages/module5.md`; every step here names the slide
it belongs to.

| | | Slot |
| --- | --- | --- |
| `lab1/` | the whole week through a pipeline | 2 (11h–12h30) |

The afternoon (slots 3 and 4) is open questions on your own applications,
with no prepared lab — see [Afternoon](#afternoon) at the end.

Still [Bookinfo](https://istio.io/latest/docs/examples/bookinfo/), as locked
down on day 4. Four days of manifests, mesh config, autoscalers, policies and
secrets have been applied by hand, with `kubectl apply`. Today they move to
git, and a GitOps agent — Flux — applies them. The new `reviews` image is
built, scanned and signed by GitHub Actions, promoted through a reviewed pull
request, and rolled out by Flagger as a canary that promotes or rolls back on
its own.

## Conventions

Same as days 1 to 4 — one namespace per attendee, `kubectl -n "$NS" ...`,
two contexts — with one big change:

- **Git is the only way in.** From step 1 on, nothing in your namespace is
  applied with `kubectl apply`: you commit, you push, Flux reconciles. The
  `developer` context is for *reading* (`get`, `describe`, `logs`) and for the
  deliberate drift of step 2. The `admin` context is still the platform team's
  hat, for steps marked **(admin)** — on the shared cluster those changes go
  to the trainer's fleet repo instead.
- **Two repos.** *Your config repo* on GitHub, created in step 0, which holds
  your application and its manifests; the *fleet repo*, owned by the platform
  team (the trainer), which holds your tenant: namespace, labels, RBAC, and
  the Flux objects pointing at your repo.
- **Steps are cumulative**, but what they ship is now *files to copy into
  your config repo*, not overlays to apply. Each step directory has a
  `README` listing what goes where.
- **Pairs.** Your config repo requires one review on `main`; your neighbour
  is your reviewer, and you are theirs.
- **Where commands run.** From this `module5/` directory, with your config
  repo cloned *outside* the exercises repo, in `$REPO`:

  ```sh
  export REPO=~/f021-$NS
  ```

## Prerequisites

- everything from modules 1 to 4: `kubectl` with both contexts, `linkerd`
  CLI, `helm`, `docker`, `sops` and `age`, `cosign`, `kyverno` CLI
- a **GitHub account**, `git`, and the [`gh`](https://cli.github.com/) CLI
  logged in (`gh auth status`)
- the [`flux`](https://fluxcd.io/flux/installation/#install-the-flux-cli)
  CLI:

  ```sh
  curl -s https://fluxcd.io/install.sh | bash
  flux version --client
  ```

- the Bookinfo sources from day 3 (`istio/samples/bookinfo/src`) and the day-3
  `reviews` Dockerfile (`../module3/lab2/step2-rebuild/Dockerfile`)

### The cluster

On the **shared cluster** the trainer has installed everything before the
session: Flux with the multi-tenancy lockdown (below), Flagger for Linkerd,
kube-prometheus-stack with Grafana and the Flagger dashboard, and a webhook
receiver in the `webhook` namespace. Your GitHub repo exists, with a deploy
key already registered for Flux, and Actions secrets for Artifactory.

On **kind**, keep the module 4 cluster (audit logging, linkerd-cni, Kyverno,
ESO, Vault). Add Flux and Flagger **(admin)**:

```sh
flux install --components-extra=image-reflector-controller,image-automation-controller
flux check

helm repo add flagger https://flagger.app
helm repo update
kubectl apply -f https://raw.githubusercontent.com/fluxcd/flagger/main/artifacts/flagger/crd.yaml
helm install flagger flagger/flagger -n flagger-system --create-namespace \
  --set crd.create=false \
  --set meshProvider=gatewayapi:v1 \
  --set metricsServer=http://prometheus.linkerd-viz:9090
```

And a webhook receiver for step 6, in a namespace of its own — Kyverno's
registry policy from day 4 only covers your namespace:

```sh
kubectl create ns webhook
kubectl -n webhook create deploy echo --image=mendhak/http-https-echo:31 --port=8080
kubectl -n webhook expose deploy echo --port=80 --target-port=8080
```

The cluster now runs Linkerd, Kyverno, ESO, Vault, Flux and Flagger on one
laptop: close what you do not need (the Chaos Mesh of day 2, the KEDA and
OpenCost of day 3 if still there).

The shared cluster runs kustomize-controller with the lockdown flags, which
kind does not have unless you add them:

- `--default-service-account=default`: a Kustomization that names no
  ServiceAccount runs as `default` in its namespace — which can do nothing,
  instead of running as Flux itself, which can do everything
- `--no-cross-namespace-refs=true`: your Kustomization cannot use a source or
  a secret in another tenant's namespace

## Starting state

Day 5 starts from the **end of module 4**: lab 2 step 8, ESO variant —
restricted Pod Security, default-deny network policies with the minimal
allow set, Linkerd authorization on `ratings`, `ratings-v2` reading its
password from Vault through ESO.

```sh
export NS=<your-namespace>
kubectl --context developer -n "$NS" get pods              # all Ready
kubectl --context developer -n "$NS" get externalsecret    # SecretSynced
linkerd -n "$NS" viz stat deploy                           # 100 % success
```

If your namespace is broken, re-apply the day-4 end state **(admin)**:

```sh
kubectl --context admin -n "$NS" apply -k ../module4/lab2/step8-rotation
```

Keep `linkerd viz dashboard` open, and the product page in a browser.

---

## Lab 1 — the whole week through a pipeline

**Slot 2 (11h–12h30).** Nobody runs `kubectl apply` any more. Bookinfo is
reconciled from your repo, a new `reviews` goes through CI and a reviewed PR,
Flagger rolls it out as a canary — and rolls back the bad one.

| | Step | Slide | ~ |
| --- | --- | --- | --- |
| 0 | `step0-repo` | Lab — setup: your config repo | 10 min |
| 1 | `step1-tenant` | Lab — the tenant | 10 min |
| 2 | `step2-drift` | Lab — drift | 5 min |
| 3 | `step3-secrets` | Lab — secrets | 10 min |
| 4 | `step4-pipeline` | Lab — the pipeline | 20 min |
| 5 | `step5-canary` | Lab — canary with Flagger | 15 min |
| 6 | `step6-alerts` | Lab — alerts and notifications | 5 min + 15 debrief |

### Step 0 — your config repo

Shared cluster: the repo exists, `gh repo clone <org>/f021-$NS "$REPO"` and
skip to the check at the end of this step.

On kind, create it from the step's skeleton, and fill it with the day-4 end
state rendered to plain YAML:

```sh
gh repo create f021-$NS --private
gh repo clone f021-$NS "$REPO"
cp -r lab1/step0-repo/. "$REPO"/
kubectl kustomize ../module4/lab2/step8-rotation > "$REPO"/deploy/bookinfo.yaml
cp -r <path-to>/istio/samples/bookinfo/src/reviews/. "$REPO"/app/reviews/
cp ../module3/lab2/step2-rebuild/Dockerfile "$REPO"/app/reviews/
```

The skeleton:

```text
f021-<ns>/
├── app/reviews/           the reviews sources + the day-3 Dockerfile
├── deploy/
│   ├── kustomization.yaml bookinfo.yaml + an `images:` entry for reviews
│   └── bookinfo.yaml      the day-4 end state, rendered
└── .github/workflows/     empty until step 4
```

Open `deploy/bookinfo.yaml` and remove what is *not* yours to deploy: the
day-4 objects the platform team applied — namespace, labels, RBAC, Kyverno
policies — belong to the fleet repo (step 1). Also remove `replicas:` from
every Deployment that has an HPA.

Commit, push, then protect `main`: one approving review, and your neighbour
as a collaborator.

```sh
git -C "$REPO" add . && git -C "$REPO" commit -m "day 4 end state" && git -C "$REPO" push
gh api -X PUT "repos/<you>/f021-$NS/branches/main/protection" --input lab1/step0-repo/protection.json
gh api -X PUT "repos/<you>/f021-$NS/collaborators/<neighbour>"     # or: Settings > Collaborators
kubectl kustomize "$REPO"/deploy | kubectl --context developer -n "$NS" diff -f -   # no diff
```

**Questions:** what did you remove from `bookinfo.yaml`, and who deploys it
now? Why must `replicas` go when an HPA exists — who would win otherwise?
Monorepo (code and manifests together) or a separate config repo: what does
each give the reviewer, and the auditor?

### Step 1 — the tenant

The tenant is what the platform team gives you — on the shared cluster it is
already in the trainer's fleet repo, commented out; the trainer uncomments it
now. On kind, **(admin)** play the fleet repo.

`lab1/step1-tenant/` holds the RBAC part: a `flux` ServiceAccount in your
namespace, and RoleBindings giving it the **same Roles as your `developer`
group** from day 4 — `developer`, and the extra Role you wrote in lab 1
step 2 (edit `rolebinding-extra.yaml` if you named it differently). It also
gives your `developers` group read access to the Flux objects of the
namespace — and, for step 5, to Flagger's `Canary` — so you can follow the
reconciles without the `admin` context.

```sh
kubectl --context admin -n "$NS" apply -k lab1/step1-tenant
```

Then the Flux objects, created **(admin)** with the CLI — in a real fleet
repo they would be committed with `--export` instead. The deploy key is how
Flux reads your private repo: register the public half on GitHub, read-only.

```sh
flux --context admin create secret git f021-repo -n "$NS" \
  --url=ssh://git@github.com/<you>/f021-$NS
kubectl --context admin -n "$NS" get secret f021-repo -o jsonpath='{.data.identity\.pub}' \
  | base64 -d > flux.pub
gh repo deploy-key add flux.pub -R <you>/f021-$NS -t flux

flux --context admin create source git f021 -n "$NS" \
  --url=ssh://git@github.com/<you>/f021-$NS --branch=main \
  --secret-ref=f021-repo --interval=1m
flux --context admin create kustomization bookinfo -n "$NS" \
  --source=GitRepository/f021 --path=./deploy --prune=true \
  --service-account=flux --interval=1m
```

Watch the first reconcile:

```sh
flux get kustomizations -n "$NS" --watch
flux events -n "$NS" --for Kustomization/bookinfo
```

It will probably fail. Read why: the `flux` SA has exactly your developer
rights, and applying *everything* needs more than you used day to day —
PDBs, NetworkPolicies, the Linkerd `Server` and `AuthorizationPolicy`,
ServiceAccounts... Complete your extra Role until the Kustomization is
`Ready`, **(admin)** each time, in the tenant — never by giving `flux` a
wider role.

```sh
kubectl -n "$NS" get kustomization bookinfo -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}'
kubectl -n "$NS" get deploy productpage -o jsonpath='{.metadata.labels}' | jq   # kustomize.toolkit.fluxcd.io/name
```

**Questions:** what was missing from your day-4 Role, and why did you never
notice as a developer? What would the Kustomization have been able to do
without `--service-account` on the shared cluster — and on kind? Who reviews
a change to the tenant, and who reviews a change to your repo?

### Step 2 — drift

Change the cluster behind Flux's back, as `developer`:

```sh
kubectl -n "$NS" edit deploy details                       # change the memory limit
kubectl -n "$NS" delete networkpolicy reviews-ratings
kubectl -n "$NS" create configmap scratch --from-literal=a=b
```

Wait one interval (or `flux reconcile kustomization bookinfo -n "$NS"`), then
look again: which changes are gone, which one stays?

Now the other direction — delete from git. Remove a Deployment you no
longer need from `deploy/bookinfo.yaml` — `loadgen` from day 1 if it is still
there, or the scaled-to-zero `ratings-v1` of day 4 — commit, push:

```sh
kubectl -n "$NS" get deploy -w                              # pruned at the next reconcile
```

For an emergency fix that must not be reverted while you work:

```sh
flux --context admin suspend kustomization bookinfo -n "$NS"
# ...fix, commit the fix...
flux --context admin resume kustomization bookinfo -n "$NS"
```

**Questions:** why was `scratch` left alone? Why is `kubectl scale` a bad
drift test in this namespace? Which of the day-2 game-day fixes did you
commit to the day-2 overlay — and where are the others now?

### Step 3 — secrets

Your Kustomization already reconciles the ESO variant of day 4: the
`ExternalSecret` is in `deploy/`, and the operator writes the `Secret`. The
`flux` SA never touches the Secret — check:

```sh
kubectl --context admin -n "$NS" auth can-i get secrets --as=system:serviceaccount:$NS:flux   # no
kubectl -n "$NS" get externalsecret ratings-db                                          # SecretSynced
```

Now try the SOPS variant. Put day 4's encrypted `secret.enc.yaml` in
`deploy/` instead of the `ExternalSecret`, and give Flux the age private key
**(admin)** — it decrypts at reconcile time:

```sh
cp ../module4/lab2/step7-secrets/b-sops/secret.enc.yaml "$REPO"/deploy/
# deploy/: replace the ExternalSecret by secret.enc.yaml, commit, push
kubectl --context admin -n "$NS" create secret generic sops-age \
  --from-file=age.agekey=../module4/age.key
kubectl --context admin -n "$NS" patch kustomization bookinfo --type merge \
  -p '{"spec":{"decryption":{"provider":"sops","secretRef":{"name":"sops-age"}}}}'
flux events -n "$NS" --for Kustomization/bookinfo
```

Read the refusal. Then decide: grant `flux` the rights on Secrets it asks
for, or go back to the ESO variant. Either way, write down what you chose and
why — the debrief uses it. Leave the repo on the ESO variant for the next
steps.

**Questions:** with SOPS, who can read the password — in git, in the
cluster, in the fleet repo? What does granting `flux` `create` and `patch` on
Secrets let a malicious commit to your repo do? Which variant keeps both the
CI and the agent out of the secrets?

### Step 4 — the pipeline

Copy the step's workflow into your repo:

```sh
mkdir -p "$REPO"/.github/workflows
cp lab1/step4-pipeline/reviews.yaml "$REPO"/.github/workflows/
```

Read it before pushing. On a push to `main` that touches `app/reviews/**`:

1. **build** the day-3 multi-stage image, tagged with the commit SHA
2. **scan** it with Trivy — fail on fixable critical CVEs
3. **push** it: Artifactory on the shared cluster (secrets
   `ARTIFACTORY_URL`, `ARTIFACTORY_USER`, `ARTIFACTORY_TOKEN` are set); GHCR
   on kind (`ghcr.io/<you>/reviews`, with the job's `GITHUB_TOKEN`)
4. **sign** it with cosign, keyless: the signature carries the identity of
   this workflow
5. **render** `deploy/` with the new tag (`kustomize edit set image`), then
   `kyverno apply` the day-4 exercise B policies to the output
6. **open a PR** that bumps the tag in `deploy/kustomization.yaml`, with the
   scan summary and the rendered diff in its description

On kind, make the GHCR package public after the first push (the cluster has
no pull secret for it), and allow Actions to create PRs: *Settings > Actions >
General > Allow GitHub Actions to create and approve pull requests*.

Trigger it with a visible change — `reviews` v2 with a different star colour
is in `app/reviews/reviews-application/src/main/java/application/rest/LibertyRestEndpoint.java`:

```sh
# in $REPO: star_color "black" -> "blue"
git -C "$REPO" commit -am "reviews: blue stars" && git -C "$REPO" push
gh run watch -R <you>/f021-$NS
```

The gradle build takes a few minutes: read the workflow while it runs. Then
review your neighbour's PR — rendered diff, scan result, policy check — and
approve it. Merge yours when approved, and watch Flux deploy it:

```sh
flux get kustomizations -n "$NS" --watch
kubectl -n "$NS" get pods -l app=reviews -o jsonpath='{.items[*].spec.containers[?(@.name=="reviews")].image}'
```

The first time, the new pods probably do not appear. Look at the ReplicaSet
events: day 4's `allowed-registries` policy does not know the registry the
pipeline pushes to. **(admin)** add it — that is a platform change, in the
fleet repo.

Bonus: add a Kyverno `verifyImages` rule that only admits `reviews` images
signed by *your* workflow.

**Questions:** what does the pipeline hold credentials for — and what does it
*not*? What did the reviewer look at before approving, and what would they
need to trust the PR more? Where is the rollback of this change?

### Step 5 — canary with Flagger

Flagger needs one Deployment per service it manages: the step collapses
`reviews` to a single Deployment named `reviews`, running your pipeline's
image, and adds a `Canary`:

- Gateway API provider: Flagger generates the `reviews` HTTPRoute and its
  weights — **the day-2 HTTPRoute for `reviews` is removed**, with its
  timeout and retries
- analysis every minute, `stepWeight: 20` up to `maxWeight: 80`, then
  promotion
- two metric checks on the linkerd-viz Prometheus: success rate ≥ 99 %, p99
  latency < 500 ms; `threshold: 2` failed checks means rollback

One trap before applying: Flagger creates `reviews-primary` from your
Deployment, and gives its pods the label `app: reviews-primary`. Every
selector on `app: reviews` — in the `reviews-ratings` and `productpage-out`
NetworkPolicies — would stop matching, and `reviews` could no longer reach
`ratings`. The step switches those selectors to a `component: reviews` label
that Flagger copies unchanged. The Linkerd authorization on `ratings` is not
affected: it matches the ServiceAccount, which both Deployments share.

```sh
cp lab1/step5-canary/*.yaml "$REPO"/deploy/
# deploy/: add canary.yaml and metric-templates.yaml to kustomization.yaml,
# drop the reviews-v1 / reviews-v3 Deployments and the reviews HTTPRoute,
# relabel as above (the step's README lists every edit)
git -C "$REPO" switch -c canary && git -C "$REPO" add . \
  && git -C "$REPO" commit -m "reviews canary" && git -C "$REPO" push -u origin canary
gh pr create -R <you>/f021-$NS --head canary --fill     # your neighbour approves
```

Once merged, Flagger initialises: `reviews-primary` takes the traffic,
`reviews` scales to zero.

```sh
kubectl -n "$NS" get canary reviews -w             # Initialized
kubectl -n "$NS" get deploy,httproute
```

Start the constant load from day 2 — without traffic there is nothing to
analyse:

```sh
kubectl -n "$NS" apply -f ../module3/k6/constant-load.yaml    # (admin) if Kyverno or RBAC refuses
```

**A good version:** push another visible change through the pipeline (step
4), approve, merge. Watch the canary progress, one step per minute:

```sh
kubectl -n "$NS" get canary reviews -w             # Progressing 20 → 40 → 60 → 80 → Promoting → Succeeded
kubectl -n "$NS" get httproute reviews -o yaml | yq '.spec.rules[0].backendRefs'
```

Grafana's Flagger dashboard on the shared cluster; `linkerd viz dashboard` on
kind, deployments `reviews` and `reviews-primary` side by side.

**A bad version:** the trainer's "hot spot" `reviews` — the performance bug
of day 3 exercise A. Open the tag-bump PR by hand, with the tag given by the
trainer (on kind: apply `lab1/step5-canary/hotspot.patch` under `app/reviews`
and push — the pipeline builds it):

```sh
kubectl -n "$NS" get canary reviews -w             # Progressing 20 → Failed after 2 checks
kubectl -n "$NS" describe canary reviews | sed -n '/Events/,$p'
```

**Questions:** how many users saw the bad version, and for how long? What is
in git now, and what is running — are they the same? What did removing the
day-2 route cost, and where would you put its timeout back? Why is the
constant load needed, and what would happen with the real traffic of a
quiet service?

### Step 6 — alerts and notifications

Three alerts, from three layers. Add to your repo:

- `prometheusrule.yaml` — Bookinfo error rate above 1 % over 2 minutes, from
  the Linkerd metrics (shared cluster only: kind has no kube-prometheus-stack;
  read it anyway)
- `flux-alert.yaml` — a Flux `Provider` (type `generic`, the webhook receiver)
  and an `Alert` on errors of your Kustomization and GitRepository
- `flagger-alert.yaml` — an `AlertProvider` on the same webhook, referenced by
  the `Canary`'s `analysis.alerts`

```sh
cp lab1/step6-alerts/*.yaml "$REPO"/deploy/
# PR, review, merge
kubectl -n webhook logs deploy/echo -f             # kind; shared cluster: the channel the trainer shows
```

Replay the bad version of step 5. Then break the repo on purpose — a YAML
typo on `main`, pushed by an admin bypassing the review:

```sh
flux get kustomizations -n "$NS"                   # Ready False, with the parse error
```

The pipeline is green, the reconcile is not: only the notification tells
you. Revert.

**Questions:** in which order did the three alerts arrive during the
rollback, and which one would you page on? Who receives a reconcile failure
at SGA — the dev team or the platform team?

**Debrief (15 min):** what your team would need to do this at SGA. Fill the
decision grid sheet from this morning with what you now know:

- repo split: config repo per team or per environment, and who owns the fleet
  repo
- the agent's identity per tenant; the CI's credentials (only git and the
  registry?)
- the approval flow for the tag-bump PR in production — CODEOWNERS, GitHub
  Environments
- secrets: SOPS or ESO, given step 3
- what the auditor gets for free now — day 4 exercise C, revisited

---

## Afternoon

No prepared lab: **your applications and questions**. The parking-lot board
from the week is voted at 14h.

- **Bring a service** — anonymised: its architecture, its dependencies, its
  deployment. The review walks it through days 1 to 5 and ends with a list of
  concrete changes.
- **Free lab** (16h–16h45), if the parking lot is empty: finish an advanced
  exercise from any day — through your pipeline this time.
- **CKAD / CKA**: the curriculum is at
  <https://github.com/cncf/curriculum>. For CKA practice, you need VMs, not
  kind: kubespray or kubeadm on three machines.

## Cleanup and export

Keep what you built. Before the cluster is torn down:

```sh
# your config repo is on GitHub: keep it, or fork it to your own account
gh repo fork <org>/f021-$NS --clone=false      # shared cluster repos only

# a manifest export of the namespace, as it runs
mkdir -p export && for k in deploy svc sa cm networkpolicy pdb hpa httproute \
  server authorizationpolicy meshtlsauthentication externalsecret canary; do
  kubectl -n "$NS" get "$k" -o yaml > "export/$k.yaml"
done
```

On kind, stop Flux first, or it will keep reconciling while you delete:

```sh
flux --context admin suspend kustomization bookinfo -n "$NS"
make -C .. delete
```

Remove the deploy key from your GitHub repo if the repo stays: it gave a
cluster that no longer exists read access to your code.
