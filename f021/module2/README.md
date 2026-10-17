# Module 2 — chaos engineering and resilience

Exercises for day 2 of **F021 — Advanced Kubernetes**. The slides are in
`../../training_f021/slides/pages/module2.md`; every step here names the slide
it belongs to.

| | | Slot |
| --- | --- | --- |
| `lab1/` | harden the application — platform and client settings | 2 (11h–12h30) |
| `lab2/` | resilience in the mesh, then the first chaos experiments | 3 (14h–15h30) |
| `gameday/` | escalating failures under load, in teams, then a post-mortem | 4 (16h–17h30) |

The application is still [Bookinfo](https://istio.io/latest/docs/examples/bookinfo/),
meshed with Linkerd on day 1. Yesterday you built it; today you break it on
purpose, make it survive, and prove that it does. Every change is measured
with the golden metrics from day 1 (`linkerd viz`), so you see what each
setting actually buys.

## Conventions

Same as day 1:

- **One namespace per attendee** (one per team for the game day). Every
  command is `kubectl -n "$NS" ...`.
- **Steps are cumulative kustomize overlays.** `kubectl -n "$NS" apply -k
  lab1/step4-spread` lands you at the end of step 4 from anywhere.
- **Read the diff, not just the file**:
  `diff <(kubectl kustomize <prev>) <(kubectl kustomize <this>)`.
- **Hypothesis first.** Before any failure is injected, write down what you
  expect to happen, in numbers. A failure you did not predict is a finding; a
  failure you did not write a prediction for is just noise.

## Prerequisites

- everything from module 1: `kubectl`, `linkerd` CLI, Linkerd + linkerd-viz
  installed in the cluster
- **more than one worker node.** Draining a node on a single-node cluster
  drains the whole application. Use the shared cluster, or recreate kind with
  the multi-node config of this module (one control plane, three workers,
  each labelled with a `topology.kubernetes.io/zone`):

  ```sh
  make delete
  kind create cluster --name training --config module2/kind.yaml
  make ingress
  ```

- `helm` to install Chaos Mesh (lab 2 step 4) — on the shared cluster the
  trainer has already done it
- images pre-pulled: Bookinfo and Linkerd as on day 1, plus `grafana/k6` and
  the Chaos Mesh images

## Starting state

Day 2 starts from **Bookinfo meshed, with no routes**: the end of module 1
lab 2 step 4. The step 5 HTTPRoute is deliberately left out — its retries and
timeouts are what lab 2 builds properly, and having them active this morning
would hide the failures lab 1 needs you to see.

```sh
export NS=<your-namespace>
kubectl -n "$NS" apply -k ../module1/lab2/step4-metrics
linkerd -n "$NS" viz stat deploy          # every deployment meshed, 100 % success
```

## The load generator

The day-1 `loadgen` sends one request per second and reports nothing but
failures. Today we need latency percentiles under real load, so every lab
runs a **k6** Job against `productpage`: constant arrival rate, a fixed
duration, and a summary with the failed-request ratio and p95/p99 at the end.

```sh
kubectl -n "$NS" apply -f k6/constant-load.yaml        # one run
kubectl -n "$NS" logs -f job/k6 -c k6                  # the summary at the end
```

k6 runs **inside the mesh**, as a client like any other. Lab 1 step 1 scales
the day-1 `loadgen` to 0.

Keep `linkerd viz dashboard` open in a second window for the whole day.

---

## Lab 1 — harden the application

**Slot 2 (11h–12h30).** Make Bookinfo survive the failures from the slot 1
theory using only what Kubernetes and the client code offer. The mesh stays
injected — it is how we measure — but none of its resilience features are
used yet.

| | Step | Slide | ~ |
| --- | --- | --- | --- |
| 1 | `step1-baseline` | Lab 1 — baseline under load | 10 min |
| 2 | `step2-probes` | Lab 1 — probes done right | 20 min |
| 3 | `step3-shutdown` | Lab 1 — graceful shutdown | 15 min |
| 4 | `step4-spread` | Lab 1 — spread and budgets | 15 min |
| 5 | `step5-timeouts` | Lab 1 — timeouts in the client | 10 min |
| 6 | `step6-fallback` | Lab 1 — fallback | 5 min + 15 debrief |

### Step 1 — baseline

Run k6 against the application as it is and record, from `linkerd viz stat`
and the k6 summary:

- success rate and p99 of `productpage`
- failed requests **and degraded pages** (the k6 checks) during a
  `kubectl rollout restart` of `reviews`, then of `productpage`
- the same while you `kubectl delete pod` the `productpage` pod

Write these numbers down. Every later step is compared to them.

**Questions:** a rolling restart is the most routine operation there is. How
many requests did it cost, and which ones did nobody count? Why is a single `productpage` pod a problem that no
restart policy fixes?

### Step 2 — probes done right

Add the three probes, each doing only its own job:

- a **startupProbe** on `reviews`. It is a Java service (Open Liberty) and
  takes tens of seconds to start; the startup probe keeps liveness from
  killing it while it boots.
- a **readinessProbe** on each service's own health endpoint, so a pod gets
  traffic only once it can serve it.
- a cheap **livenessProbe** that checks the process, not its dependencies.

Then apply the **trap** the step ships as a separate patch: a liveness probe
on `productpage` that hits `/productpage` — the page that calls every other
service — with `timeoutSeconds: 1`. It only bites when a dependency is slow,
so replace `ratings` with the black hole (`faults/ratings-blackhole.yaml`)
first. Run k6 with the sane probes, then with the trap, and watch `RESTARTS`
climb and the success rate collapse. Remove both.

**Questions:** why did healthy pods get killed? Why did each restart make the
remaining pods *more* likely to fail? A readiness probe that checks `ratings`
would look reasonable on `reviews` — what happens to the whole `reviews`
service the moment `ratings` goes down?

### Step 3 — graceful shutdown

Repeat the rolling restart of `productpage` from step 1 under load and count
failed requests.
Then add:

- a `preStop` hook that sleeps a few seconds, so the pod is removed from the
  endpoints before it stops accepting connections
- a `terminationGracePeriodSeconds` longer than that sleep plus the time to
  drain in-flight requests
- `config.alpha.linkerd.io/proxy-wait-before-exit-seconds`, so the Linkerd
  proxy outlives the application container instead of dying first — and
  find out why, with native sidecars, it changes nothing

Restart again. The target is **zero** failed requests.

**Questions:** endpoint removal and SIGTERM happen at the same time, not one
after the other — so what was failing before the `preStop`? What would the
application code still have to do that no manifest can do for it?

### Step 4 — spread and budgets

- two or more replicas for `productpage` and each `reviews` version
- `topologySpreadConstraints` on `kubernetes.io/hostname`, then on
  `topology.kubernetes.io/zone`
- a `PodDisruptionBudget` with `minAvailable: 1` on each of them

Check where the pods landed (`kubectl get pods -o wide`), then drain a worker
under load:

```sh
kubectl drain <worker> --ignore-daemonsets --delete-emptydir-data
```

Watch the drain wait on the PDBs, and the k6 numbers stay flat. Uncordon the
node at the end.

**Questions:** what happens if you drain two workers at once? What does a
`minAvailable: 1` PDB do on a deployment with a single replica, and what will
the ops team do about it at 3 a.m.? What does a PDB **not** protect against?

### Step 5 — timeouts in the client

The Bookinfo images hardcode their timeouts: `productpage` gives `reviews`
3 s plus one retry, and `reviews` v2 gives `ratings` 10 s. They cannot be
changed from the manifest, so this step **observes** them:

1. Scale `reviews` to 0 replicas. Outside the mesh a Service with no
   endpoints fails at once; inside it, the proxy holds the request up to
   3 s before failing fast. Time both.
2. Replace `ratings` with the **black hole** (`faults/ratings-blackhole.yaml`),
   a pod that accepts connections and never answers. Reload the page and
   time it.

**Questions:** why is a slow dependency worse than a dead one? `productpage`
gives up after 3 s (6 s with its retry), while `reviews` v2 waits 10 s for
`ratings` — which
of these timeouts is useless, and what should the values be for a 2 s
page budget? Where would you set them in a Java service (Resilience4j) and in
the Python one (`requests`)? Lab 2 fixes this without touching the code.

Put `ratings` back before moving on.

### Step 6 — fallback

Scale `ratings` to 0. The page still renders, with *"Ratings service is
currently unavailable"*. Bookinfo already has this fallback: find it in the
`reviews` source.

**Questions:** the page survives without `ratings` and without `details`,
but not without `reviews`. Who made that decision, and should it have been a
developer?

**Debrief (15 min):** which of today's fixes were pure manifests, and which
needed code? What is still unprotected?

---

## Lab 2 — resilience in the mesh, then chaos

**Slot 3 (14h–15h30).** Part A moves timeouts, retries and circuit breaking
into the mesh — no code changes. Part B proves the result with Chaos Mesh,
one written hypothesis per experiment. Starts from the end of lab 1.

| | Step | Slide | ~ |
| --- | --- | --- | --- |
| 1 | `step1-routes` | Lab 2 — timeouts and retries per route | 15 min |
| 2 | `step2-failure-accrual` | Lab 2 — circuit breaking with failure accrual | 15 min |
| 3 | `step3-istio-demo` | Lab 2 — trainer demo: Istio | 10 min |
| 4 | `step4-chaos-mesh` | Lab 2 — install Chaos Mesh | 5 min |
| 5 | `step5-pod-kill` | Lab 2 — first experiment: pod kill | 10 min |
| 6 | `step6-delay` | Lab 2 — network delay | 10 min |
| 7 | `step7-partition` | Lab 2 — network partition | 10 min + 15 debrief |

### Part A — resilience in the mesh

#### Step 1 — timeouts and retries per route

Add Linkerd `HTTPRoute`s on `reviews` and `ratings`:

- a request timeout **shorter** than the caller's: `ratings` must now give up
  well before the 10 s hardcoded in `reviews` v2
- retries on 5xx for GET only, with a small limit

Replay lab 1 step 5 (the `ratings` black hole). The page should now come back
within the budget, without ratings.

Then look at the retries across layers: `productpage` already retries
`reviews` once in its code. Count how many attempts one user request can
cause if the mesh also retries, and remove one of the layers.

```sh
lab2/route-stats.sh productpage-v1 reviews     # requests vs attempts, per route
```

`linkerd viz routes` only reads ServiceProfiles; for HTTPRoutes the same
numbers come from the proxy metrics, which the script sums.

**Questions:** what is the difference between the requests the application
made and the attempts the proxy sent (`EFFECTIVE_SUCCESS` and
`ACTUAL_SUCCESS` in `viz routes` terms), and why do you want to see both?
Add an ingress that also retries, three attempts per layer: how many
requests reach a `reviews` that is already failing?

#### Step 2 — circuit breaking with failure accrual

Linkerd's circuit breaker ejects one bad **endpoint**, not the whole service.
To see it, `ratings` needs more than one endpoint and one of them must be bad:
`faults/ratings-faulty.yaml` adds a `ratings` replica that passes its probes
and answers 500, behind the same Service. The step enables failure accrual
on the Service:

```yaml
metadata:
  annotations:
    balancer.linkerd.io/failure-accrual: consecutive
```

Watch the faulty endpoint get ejected, the traffic move to the healthy one,
then the periodic probe requests that let it back in once it recovers.

**Questions:** what happens when the *only* endpoint is ejected? How is this
different from a retry?

#### Step 3 — trainer demo: Istio

Watch the same features on Istio, in the day-1 Istio namespace:
`DestinationRule` outlier detection and `connectionPool` limits (a bulkhead),
and `VirtualService` fault injection (abort a percentage of `ratings` calls,
delay others). Compare the amount of YAML and the number of knobs with what
you just did on Linkerd.

### Part B — first chaos experiments

For every experiment below, **write the hypothesis before you apply
anything**, using the template from the slides:

```
Hypothesis:  <steady state that should hold, in numbers>
Injection:   <fault, target, size>
Observe:     <where: linkerd viz, k6 summary>
Abort if:    <threshold at which you stop the experiment>
Result:      confirmed / refuted -> action
```

#### Step 4 — install Chaos Mesh

On the shared cluster it is already installed; you only have rights on Chaos
objects in your own namespace. On kind:

```sh
helm repo add chaos-mesh https://charts.chaos-mesh.org
helm install chaos-mesh chaos-mesh/chaos-mesh -n chaos-mesh --create-namespace \
  --version 2.8.4 \
  --set chaosDaemon.runtime=containerd \
  --set chaosDaemon.socketPath=/run/containerd/containerd.sock \
  --set controllerManager.replicaCount=1 \
  --set dashboard.securityMode=false
kubectl -n chaos-mesh port-forward svc/chaos-dashboard 2333:2333
```

If the controller crash-loops with `too many open files`, raise the host's
inotify limits (see `lab2/step4-chaos-mesh/`).

Look at the CRDs it installed (`kubectl api-resources | grep chaos-mesh`).

#### Step 5 — pod kill

Hypothesis to test: *killing one `reviews` pod does not change the success
rate, and p99 stays under 500 ms.*

Apply a `PodChaos` `pod-kill` on one `reviews` pod while k6 runs. Confirmed or
refuted? If refuted, which lab 1 setting was missing?

#### Step 6 — network delay

A `NetworkChaos` `delay` of 300 ms ± 100 ms from `productpage` to `reviews`.
Does the step 1 timeout fire? What does p99 do, and what does the user see?
Try once with the delay below the route timeout and once above it.

#### Step 7 — network partition

A `NetworkChaos` `partition` that isolates `ratings`. Does failure accrual
kick in? Does the page degrade or hang? Compare with the black hole of lab 1
step 5.

**Debrief (15 min):** your experiments are YAML files — where should they
live, and how would you run them every night (Chaos Mesh `Schedule`)? What
would a pass/fail criterion look like in CI?

---

## Game day

**Slot 4 (16h–17h30).** Four teams of 3–4, one Bookinfo namespace per team,
starting from the end of lab 2. The trainer injects failures; your team
detects, diagnoses and fixes them.

**Steady state to defend**, under constant k6 load, as shown on the trainer's
dashboard:

- success rate **≥ 99 %**
- p99 **< 1 s**

**Roles** inside the team: an incident commander who decides, investigators
who dig, and a scribe who keeps the timeline — time of detection, diagnosis,
fix, recovery. The scribe's notes are the input of the post-mortem.

**Rules:**

- any fix is allowed: manifests, mesh configuration, scaling
- every fix is committed to the team's repository — nothing left as an
  undocumented `kubectl edit`
- a team that is stuck can ask the trainer for a reset of its namespace

The scenarios are not listed here on purpose. They arrive roughly every
eight minutes and get harder as they go; some should be invisible if the
morning's work was done right.

Fast teams can run the same pod-delete experiment with **Litmus** instead of
Chaos Mesh, with a probe, and compare the resilience score it gives.

### Post-mortem

Blameless, one scenario per team, 5 minutes each:

1. timeline — from the scribe's notes
2. detection time — how long before anyone noticed, and how
3. root cause, and contributing factors
4. the fix
5. one follow-up action, with an owner

Commit the post-mortem to the team repository next to the fix.

## Cleanup

```sh
kubectl -n "$NS" delete podchaos,networkchaos,stresschaos,dnschaos,schedule --all
kubectl -n "$NS" delete job k6
```

Keep Bookinfo running: day 3 measures what today's resilience costs in CPU
and memory.
