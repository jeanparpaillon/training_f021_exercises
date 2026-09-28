# Module 3 — performance and optimisation

Exercises for day 3 of **F021 — Advanced Kubernetes**. The slides are in
`../../training_f021/slides/pages/module3.md`; every step here names the slide
it belongs to.

| | | Slot |
| --- | --- | --- |
| `lab1/` | measure, right-size, autoscale | 2 (11h–12h30) |
| `lab2/` | images and startup, then network latency | 3 (14h–15h30) |
| `advanced/` | one exercise per attendee: bottleneck, KEDA, cost | 4 (16h20–17h10) |

Still [Bookinfo](https://istio.io/latest/docs/examples/bookinfo/), as hardened
on day 2. Its replicas, sidecars and retries all cost CPU, memory and
latency. Today you measure that cost and pay only for what is needed.

## Conventions

Same as days 1 and 2:

- **One namespace per attendee.** Every command is `kubectl -n "$NS" ...`.
- **Steps are cumulative kustomize overlays.** `kubectl -n "$NS" apply -k
  lab1/step4-vpa` lands you at the end of step 4 from anywhere.
- **Read the diff, not just the file**:
  `diff <(kubectl kustomize <prev>) <(kubectl kustomize <this>)`.
- **Before / after, same load.** Every change is measured with the same k6
  profile as the baseline. Keep one table per lab — step, p50, p99, error
  rate, pods, CPU / memory — and fill a row after each step. An optimisation
  that did not move a number did not happen.

## Prerequisites

- everything from modules 1 and 2: `kubectl`, `linkerd` CLI, Linkerd +
  linkerd-viz, the multi-node kind from `module2/kind.yaml` (lab 2 step 8
  needs its zone labels) or the shared cluster
- `helm`, for what the cluster does not already have (below)
- `docker` (or `podman`) to rebuild images in lab 2, and either a registry
  the cluster can pull from or `kind load docker-image`
- a clone of the Bookinfo sources, for the rebuilds:

  ```sh
  git clone --depth 1 --branch 1.20.3 https://github.com/istio/istio.git
  ls istio/samples/bookinfo/src     # productpage, reviews, ratings, details
  ```

### Cluster add-ons

On the shared cluster the trainer has installed everything: metrics-server,
kube-prometheus-stack, Prometheus Adapter, VPA, KEDA, Pyroscope and OpenCost.
You only create HPA, VPA and ScaledObject objects in your namespace.

On kind, install the two that lab 1 cannot do without:

```sh
# metrics-server: kind's kubelets have self-signed certificates
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm install metrics-server metrics-server/metrics-server -n kube-system \
  --set 'args={--kubelet-insecure-tls}'
kubectl top nodes                       # works after ~1 min

# VPA, recommender only — we never let it modify pods
helm repo add fairwinds-stable https://charts.fairwinds.com/stable
helm install vpa fairwinds-stable/vpa -n vpa --create-namespace \
  --set updater.enabled=false --set admissionController.enabled=false
```

Prometheus Adapter (lab 1 step 6) and the slot 4 tools are installed in the
steps that need them.

## Starting state

Day 3 starts from the **end of module 2 lab 2 step 1**: probes, graceful
shutdown, spread, PDBs, and the mesh timeouts and retries. The faulty
`ratings` replica of lab 2 step 2 is left out — it answers 500 on purpose
and would skew every measurement today.

```sh
export NS=<your-namespace>
kubectl -n "$NS" delete podchaos,networkchaos,stresschaos,dnschaos --all
kubectl -n "$NS" apply -k ../module2/lab2/step1-routes
kubectl -n "$NS" get deploy -l app=ratings  # only ratings-v1: delete the faulty one if still there
linkerd -n "$NS" viz stat deploy          # every deployment meshed, 100 % success
```

## The load profiles

Two k6 Jobs, both against `productpage`:

- `k6/constant-load.yaml` — from day 2: constant arrival rate, used where a
  step needs steady traffic (lab 2, slot 4)
- `k6/ramp.yaml` — new: 0 → 200 virtual users over 3 minutes, then 1 minute
  at 200. This is the **benchmark** of the day; every before / after number
  comes from it.

```sh
kubectl -n "$NS" delete job k6 --ignore-not-found
kubectl -n "$NS" apply -f k6/ramp.yaml
kubectl -n "$NS" logs -f job/k6          # p50, p95, p99, failed ratio at the end
```

On the shared cluster the ramps are **staggered by team**: 13 × 200 virtual
users at once measures the cluster, not your service. Wait for the trainer
to call your slot.

---

## Lab 1 — measure, right-size, autoscale

**Slot 2 (11h–12h30).** Give every Bookinfo service correct requests and
limits, and an HPA that reacts to load, with before / after numbers.

| | Step | Slide | ~ |
| --- | --- | --- | --- |
| 1 | `step1-baseline` | Lab 1 — baseline | 10 min |
| 2 | `step2-throttling` | Lab 1 — find the throttling | 15 min |
| 3 | `step3-memory` | Lab 1 — find the OOM | 15 min |
| 4 | `step4-vpa` | Lab 1 — right-size with VPA | 10 min |
| 5 | `step5-hpa-cpu` | Lab 1 — HPA on CPU | 15 min |
| 6 | `step6-hpa-rps` | Lab 1 — HPA on request rate | 10 min + 15 debrief |

### Step 1 — baseline

Run the ramp against the application as it is. Record:

- p50, p99 and failed ratio from the k6 summary
- `kubectl -n "$NS" top pods --containers` near the peak of the ramp
- the QoS class of every pod:

  ```sh
  kubectl -n "$NS" get pods \
    -o custom-columns=NAME:.metadata.name,QOS:.status.qosClass
  ```

- the requests and limits actually set, container by container:

  ```sh
  kubectl -n "$NS" get pods -o json | jq -r '.items[] | .metadata.name as $p
    | .spec.containers[] | [$p, .name, (.resources|tostring)] | @tsv'
  ```

This is the first row of your table.

**Questions:** which containers have requests, and who set them? Which pods
would the kubelet evict first if the node ran out of memory? On what basis
did the scheduler place these pods?

### Step 2 — find the throttling

The step gives `reviews` a CPU request of `250m` and a tight **limit** of
`500m`. Run the ramp again, and read the throttling counters for the
`reviews` containers. With Prometheus (shared cluster):

```promql
sum by (pod) (rate(container_cpu_cfs_throttled_periods_total{namespace="$NS", container="reviews"}[1m]))
/
sum by (pod) (rate(container_cpu_cfs_periods_total{namespace="$NS", container="reviews"}[1m]))
```

Without Prometheus (kind), straight from the kubelet of the node that runs
the pod — run it twice, a minute apart, and compare:

```sh
NODE=$(kubectl -n "$NS" get pod -l app=reviews -o jsonpath='{.items[0].spec.nodeName}')
kubectl get --raw "/api/v1/nodes/$NODE/proxy/metrics/cadvisor" \
  | grep -E 'container_cpu_cfs_(throttled_)?periods_total' | grep 'container="reviews"'
```

Compare p99 with the baseline, and look at `kubectl top` at the same moment.

Then apply the second half of the step: the CPU **limit removed**, the
request kept. Rerun and compare.

**Questions:** `kubectl top` showed `reviews` below its limit — so why was it
throttled? How long did a `reviews` pod take to become ready with `500m`, and
what does that mean for the startup probe you wrote on day 2? Once the limit
is gone, what still stops `reviews` from taking the whole node?

### Step 3 — find the OOM

Part 1 — `ratings` (Node.js). The step sets a memory limit that is too small
for it under load. Run the ramp and watch:

```sh
kubectl -n "$NS" get pods -l app=ratings -w
kubectl -n "$NS" describe pod -l app=ratings | grep -A4 'Last State'
```

Find the exit code, the reason, the restart count. Raise the limit to a
value you can justify from what you measured.

Part 2 — `reviews` (Java, Liberty on OpenJ9). It now has a memory limit, but
the JVM sizes its heap by default at a quarter of it. Check what it chose:

```sh
kubectl -n "$NS" exec deploy/reviews-v2 -c reviews -- \
  java -verbose:sizes -version 2>&1 | grep -i 'java heap'    # OpenJ9 syntax
```

The step sets `JAVA_TOOL_OPTIONS=-XX:MaxRAMPercentage=75` instead of guessing
a bigger limit. Rerun the ramp.

**Questions:** why is setting `-Xmx` equal to the container limit a guaranteed
OOMKill? What else in a JVM uses memory outside the heap? Why does the step
make the memory request equal to the memory limit, when it deliberately did
not do that for CPU?

### Step 4 — right-size with VPA

The step adds one `VerticalPodAutoscaler` per deployment, with
`updateMode: "Off"`: it recommends, it never touches a pod. Run the ramp,
then read the recommendations:

```sh
kubectl -n "$NS" get vpa
kubectl -n "$NS" describe vpa reviews-v2 | sed -n '/Recommendation/,$p'
```

Copy the `Target` values into the manifests as requests — edit this step's
patch, commit it, re-apply. That is the whole workflow: VPA suggests, git
decides.

**Questions:** what are `Lower Bound` and `Upper Bound` for? How much traffic
history would you want before trusting these numbers for a real service? Why
not simply switch `updateMode` to `Auto`?

### Step 5 — HPA on CPU

The step adds an `autoscaling/v2` HPA on `productpage`: 2 to 8 replicas,
target 60 % CPU utilisation, `type: Resource`. Apply it and look at it
**before** any load:

```sh
kubectl -n "$NS" describe hpa productpage
```

It does not work. Read the condition message, find out which container it
complains about, and why that container is there. Apply the fix the step
ships in `fix/`: a `type: ContainerResource` metric that targets the
`productpage` container only.

Now run the ramp and watch it scale:

```sh
kubectl -n "$NS" get hpa productpage -w
```

At the end of the ramp, watch the scale-down. Then apply the step's
`behavior` patch — faster scale-up, a stabilisation window and a
percentage-based policy for scale-down — and run the ramp once more.

**Questions:** the HPA computes utilisation against what — usage, the limit,
the request? What would a `type: Resource` HPA measure on a pod whose sidecar
has a request but is nearly idle? How long between the load arriving and a
new pod actually serving traffic, and which parts of that delay can you
shrink?

### Step 6 — HPA on request rate

Scale `reviews` on what its users do — requests per second — instead of
CPU. On kind, install the adapter first, pointed at linkerd-viz's
Prometheus, with the rule this step ships:

```sh
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus-adapter prometheus-community/prometheus-adapter \
  -n linkerd-viz -f lab1/step6-hpa-rps/adapter-values.yaml
```

The rule turns Linkerd's `request_total{direction="inbound"}` into a per-pod
metric named `requests_per_second`. Check it exists before writing an HPA
against it:

```sh
kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1/namespaces/$NS/pods/*/requests_per_second" | jq .
```

Then apply the step: one HPA per `reviews` version with a `Pods` metric at
20 requests per second per pod. Run the ramp and compare with step 5:
reaction time, pod count at peak, p99.

**Questions:** why is RPS a better signal than CPU for `reviews`? What would
go wrong if you scaled on p99 latency instead? The VPA from step 4 is still
there in `Off` mode — would it be safe to switch it to `Auto` now?

**Debrief (15 min):** a cheat sheet per runtime — JVM, Go, Python, Node — on
CPU request / limit, memory request = limit, runtime flags, and the metric to
scale on.

---

## Lab 2 — images, startup and latency

**Slot 3 (14h–15h30).** Part A makes `reviews` pull and start faster: the
HPA from this morning is only as fast as a pod starts. Part B follows one
request through the network and removes what it does not need. Starts from
the end of lab 1.

| | Step | Slide | ~ |
| --- | --- | --- | --- |
| 1 | `step1-measure` | Lab 2 — measure the reviews image | 5 min |
| 2 | `step2-rebuild` | Lab 2 — rebuild reviews | 15 min |
| 3 | `step3-jvm-flags` | Lab 2 — JVM flags for containers | 10 min |
| 4 | `step4-productpage` | Lab 2 — productpage, quickly | 10 min |
| 5 | `step5-dns` | Lab 2 — DNS lookups | 10 min |
| 6 | `step6-sidecar` | Lab 2 — the sidecar tax | 10 min |
| 7 | `step7-connections` | Lab 2 — connection reuse | 10 min |
| 8 | `step8-topology` | Lab 2 — topology-aware routing | 5 min + 15 debrief |

### Part A — images and startup

#### Step 1 — measure the reviews image

Three numbers for `reviews-v2`, first row of the Part A table:

1. **size**: `docker image ls` after pulling it, or the registry UI
2. **pull time** on a node that does not have it yet. On kind:

   ```sh
   IMG=registry.istio.io/release/examples-bookinfo-reviews-v2:1.20.3
   docker exec training-worker crictl rmi "$IMG"
   time docker exec training-worker crictl pull "$IMG"
   ```

3. **time to ready** after a restart:

   ```sh
   kubectl -n "$NS" rollout restart deploy/reviews-v2
   kubectl -n "$NS" get pods -l app=reviews,version=v2 -w
   ```

   or, more precisely, the gap between a new pod's `creationTimestamp` and its
   `Ready` condition's `lastTransitionTime`.

#### Step 2 — rebuild reviews

Look at `istio/samples/bookinfo/src/reviews/reviews-wlpcfg/Dockerfile`: which
base image, which Liberty edition, what gets copied? The step ships a new
Dockerfile to compare with it:

- a **multi-stage** build: gradle compiles the WAR in a build stage that never
  reaches the final image
- **Liberty kernel-slim** plus only the features `server.xml` asks for,
  instead of the "full" image with every feature
- the **shared class cache** populated at build time, so the first start
  reuses the classes already loaded once

```sh
cd istio/samples/bookinfo/src/reviews
docker build -f <exercises>/module3/lab2/step2-rebuild/Dockerfile \
  --build-arg service_version=v2 --build-arg enable_ratings=true \
  -t reviews-v2:slim .
kind load docker-image reviews-v2:slim --name training   # or push to the registry
kubectl -n "$NS" apply -k lab2/step2-rebuild
```

Measure the three numbers of step 1 again. `dive reviews-v2:slim` shows what
each layer adds, if you have it.

**Questions:** which change bought the most — the base, the features or the
class cache? Where did gradle and the JDK go? What is the price of the slim
image the day you need one more Liberty feature?

#### Step 3 — JVM flags for containers

The step adds JVM options through `JAVA_TOOL_OPTIONS`: `MaxRAMPercentage`
from lab 1, then startup-oriented options for OpenJ9 (`-Xquickstart`,
`-Xtune:virtualized`). Measure **both** time to ready and the k6 p99 once the
service is warm.

**Questions:** a JVM that starts faster but runs slower — when is that the
right trade? Which of these flags would you keep for a service that scales
out and in many times a day, and which for one that runs for weeks?

#### Step 4 — productpage, quickly

`productpage` is Python, served by gunicorn. Find how many workers the image
starts:

```sh
docker inspect registry.istio.io/release/examples-bookinfo-productpage-v1:1.20.3 \
  --format '{{json .Config.Cmd}}'
```

Compare with the CPU request you gave it in lab 1. The step overrides the
command with a worker count derived from the request. Rerun the constant load
and compare p99.

**Questions:** what happens to eight Python processes that share a quarter
of a CPU? Why does the right worker count depend on the request and not on
the node size?

### Part B — network latency

For Part B, run the **constant** load (`k6/constant-load.yaml`), not the
ramp: you are comparing latency, not scaling.

#### Step 5 — DNS lookups

Attach a debug container with network tools to a `productpage` pod and
watch its DNS traffic while you reload the page:

```sh
POD=$(kubectl -n "$NS" get pod -l app=productpage -o jsonpath='{.items[0].metadata.name}')
kubectl -n "$NS" debug -it "$POD" --image=nicolaka/netshoot --target=productpage \
  -- tcpdump -ni any port 53
kubectl -n "$NS" exec "$POD" -c productpage -- cat /etc/resolv.conf
```

Count the queries per page load for `details`, `reviews` and `ratings`.

Then apply the step's first patch: it sets `SERVICES_DOMAIN` to
`<ns>.svc.cluster.local`, so `productpage` now calls
`details.<ns>.svc.cluster.local` — the "fully qualified" name. Count again.

Finally, the step's second patch adds a `dnsConfig` with `ndots: 2`. Count
again, and compare p50 for the three variants.

**Questions:** why did the longer name cause *more* queries? What exactly
would a trailing dot change? Which names in a real service — a partner API,
a database in another namespace — hit the worst case with the default
`ndots: 5`?

#### Step 6 — the sidecar tax

The step removes the Linkerd proxy from `details` only
(`linkerd.io/inject: disabled` on its pod template). Run the constant load
and compare with the previous row: p50 and p99 of `productpage`, CPU and
memory of the `details` pods.

```sh
kubectl -n "$NS" top pods -l app=details --containers
linkerd -n "$NS" viz stat deploy
```

Re-inject `details` at the end (the next step does it for you).

**Questions:** how much latency and how much memory did the proxy cost, per
pod and across the namespace? What did you lose when it was gone — look at
`details` in `linkerd viz` and in the mTLS column of `linkerd viz edges`.
Would you trade that for what you measured?

#### Step 7 — connection reuse

`productpage` makes each call with a fresh `requests.get()`, without a
session. Under constant load, look at the connections from the application
to its local proxy:

```sh
kubectl -n "$NS" debug -it "$POD" --image=nicolaka/netshoot --target=productpage \
  -- sh -c 'ss -s; ss -tan state time-wait | wc -l'
```

Then at the connections the proxy keeps to the other services:

```sh
linkerd -n "$NS" diagnostics proxy-metrics po/"$POD" \
  | grep -E '^tcp_open_(total|connections)\{direction="outbound"'
```

**Questions:** how many connections does the application open per second,
and how many does its proxy actually keep open to `reviews`? What would the
application's connection churn cost *without* the mesh, on every call, with
TLS? Optional: patch `productpage.py` to use one `requests.Session`, rebuild,
and compare.

#### Step 8 — topology-aware routing

Needs zone-labelled nodes: the multi-node kind from module 2, or the shared
cluster. The step spreads `reviews` across zones and sets
`trafficDistribution: PreferClose` on the `reviews` Service.

Check that the EndpointSlice controller added zone hints:

```sh
kubectl -n "$NS" get endpointslice -l kubernetes.io/service-name=reviews -o yaml \
  | grep -A3 hints
```

Then check where the calls actually go — which `productpage` pod calls which
`reviews` pod, and on which nodes they run:

```sh
linkerd -n "$NS" viz edges po
kubectl -n "$NS" get pods -o wide -L topology.kubernetes.io/zone
```

**Questions:** do calls stay within the zone? Who honours the hints here —
kube-proxy or the Linkerd proxy? What happens to a zone that has one
`reviews` pod while the others have three?

**Debrief (15 min):** the latency budget of one `productpage` request, line
by line — DNS, connections, proxy hops, time in each service, fan-out —
before today and after.

---

## Slot 4 — profiling and advanced exercises

**16h–16h20: live demo** by the trainer — async-profiler on `reviews` through
an ephemeral debug container, `py-spy` on `productpage`, `pprof` on the
Linkerd control plane, and a Pyroscope diff between this morning's ramp and
this afternoon's.

**16h20–17h10: one exercise per attendee** (or pair), in `advanced/`. Each
ends with **one number** to report at the wrap-up.

### Exercise A — find the bottleneck

The trainer replaces your `reviews-v2` with an image that has a performance
bug somewhere in its request path. You get only the symptom: p99 is bad.

1. Run the constant load and confirm the symptom with numbers.
2. Profile the running pod without rebuilding it:

   ```sh
   kubectl -n "$NS" debug -it <reviews-pod> --profile=sysadmin \
     --image=<async-profiler image given by the trainer> --target=reviews
   ```

   Take a CPU profile, then a **wall-clock** profile, 30 s each, under load.
   Open the flame graphs.
3. Find the bug in `istio/samples/bookinfo/src/reviews`, fix it, rebuild,
   redeploy.
4. Prove the gain with k6.

**Questions:** did the CPU profile show it, or only the wall-clock one — why?
Would adding replicas have fixed it? Would adding CPU?

### Exercise B — KEDA and scale to zero

Replace the lab 1 HPA of `ratings` (and write one if there was none) with a
KEDA `ScaledObject`, Prometheus trigger, `minReplicaCount: 0`.

1. Scale on `ratings`' own inbound request rate first. Stop the load, let it
   scale to zero, restart the load. What happens, and why does it never come
   back?
2. Scale on the rate of requests the **callers** send to `ratings` instead
   (Linkerd outbound metrics of `reviews`, by destination).
3. Measure the cold start: how long, and how many requests fail, between
   the first request and a ready `ratings` pod? KEDA does not hold requests
   while it scales.
4. Mitigate: the startup work from lab 2, the fallback from day 2, and a
   `cron` trigger that keeps one replica during business hours.

**Questions:** for which of SGA's services would scale to zero be
acceptable? What would you need in front of `ratings` to make the first
request wait instead of fail?

### Exercise C — cost per service

OpenCost is installed cluster-wide (on kind: `helm install opencost
opencost/opencost` with the linkerd-viz or kube-prometheus Prometheus).

```sh
kubectl -n opencost port-forward svc/opencost 9090:9090
```

1. Read the cost of your namespace per deployment; split it into *used* and
   *idle* (requested but not used).
2. Compare what the morning's baseline requests would cost with the
   right-sized ones from lab 1 step 4.
3. Extrapolate to 100 services for a month.

**Questions:** who pays for requested-but-idle CPU? Which service in
Bookinfo has the worst used / requested ratio, and is that the right one to
optimise first?

## Cleanup

```sh
kubectl -n "$NS" delete hpa,vpa,scaledobject --all
kubectl -n "$NS" delete job k6
```

Keep Bookinfo running. Tomorrow, the same application — without
cluster-admin.
