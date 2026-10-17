# Step 6 — trainer demo: the same thing on Istio

**Slide:** Lab 2 — trainer demo: the same on Istio · **~15 min**, demo only

Run by the trainer, on a separate cluster or namespace — **do not point this
at a namespace Linkerd already meshes.** The point is not to install Istio;
it is to put the two configuration models side by side on an application
everyone in the room now knows by heart.

## Setup (trainer)

Nothing from lab 1 or lab 2 needs resetting: the overlay builds from
`lab1/step3-balancing` into a **fresh namespace**, so it starts from zero by
construction. Istio and Linkerd can share the cluster — Istio only injects
into namespaces labelled `istio-injection=enabled`, Linkerd only into
workloads or namespaces annotated for it.

Get `istioctl` at the version `../Makefile` pre-pulls, then install:

```sh
curl -sSL https://istio.io/downloadIstio | ISTIO_VERSION=1.31.1 sh -
export PATH="$PWD/istio-1.31.1/bin:$PATH"
istioctl x precheck
istioctl install --set profile=demo -y
```

Deploy the same Bookinfo, meshed by Istio:

```sh
kubectl create namespace bookinfo-istio
kubectl label namespace bookinfo-istio istio-injection=enabled
kubectl -n bookinfo-istio apply -k lab2/step6-istio-demo
kubectl -n bookinfo-istio get pods      # 2/2, the sidecar is Envoy
istioctl -n bookinfo-istio analyze      # no validation issues
```

Reach it through the ingress gateway. On kind its `LoadBalancer` Service stays
`<pending>` (no cloud load balancer, and host port 80 already belongs to
ingress-nginx), so port-forward it:

```sh
kubectl -n istio-system port-forward svc/istio-ingressgateway 8081:80 &
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8081/productpage   # 200
for i in $(seq 1 60); do curl -s http://localhost:8081/productpage \
  | grep -o "reviews-v[0-9]" | head -1; done | sort | uniq -c           # ~90/10
```

Kiali, for the equivalent of `linkerd viz dashboard`. It is **not** part of
`istioctl install`: apply the addons shipped in the release first (Kiali needs
Prometheus for its graph):

```sh
kubectl apply -f istio-1.31.1/samples/addons/prometheus.yaml \
              -f istio-1.31.1/samples/addons/kiali.yaml
kubectl -n istio-system rollout status deploy/kiali
istioctl dashboard kiali
```

Cleanup, end of day:

```sh
kubectl delete namespace bookinfo-istio
kubectl delete -f istio-1.31.1/samples/addons/kiali.yaml \
               -f istio-1.31.1/samples/addons/prometheus.yaml
istioctl uninstall --purge -y && kubectl delete namespace istio-system
```

## The comparison, object by object

| Job | Linkerd (step 5) | Istio (here) |
| --- | --- | --- |
| Entry point | Kubernetes `Ingress` | `Gateway` + `VirtualService` |
| Name a version | one extra `Service` per version | `subsets` in a `DestinationRule` |
| Split traffic | `HTTPRoute`, `backendRefs[].weight` | `VirtualService`, `route[].weight` |
| Retries | annotation `retry.linkerd.io/http` | `retries:` field |
| Timeout | annotation `timeout.linkerd.io/request` | `timeout:` field |
| Sidecar | `linkerd2-proxy` (Rust, purpose-built) | Envoy (C++, general-purpose) |
| Dashboard | `linkerd viz` | Kiali + Prometheus + Grafana + Jaeger |

Two honest readings of that table, and the room should hear both:

- Istio's routing is one object with named fields, versus Linkerd's Gateway-API
  object plus annotations plus extra Services. For anything beyond a weighted
  split — header matching, mirroring, fault injection, per-subset TLS — Istio
  expresses it directly and Linkerd may not express it at all.
- Every row on the Istio side is a CRD to learn, a control plane to operate
  and a sidecar with a much larger footprint. Compare the memory of an Envoy
  sidecar with the `linkerd-proxy` numbers from step 2.

`istioctl` has no real Linkerd counterpart either: `istioctl analyze` and
`istioctl proxy-config` exist because the configuration surface is big enough
to need them.

## Also mention

**Ambient mode.** Istio can now run without per-pod sidecars: a per-node ztunnel
for L4 and mTLS, and an optional waypoint proxy for L7. It changes the
footprint argument above substantially, and it is the thing to re-evaluate
before committing either way.

## Debrief — mesh, library, or neither

**Slide:** Lab 2 — debrief · **15 min**

A decision grid, not a recommendation:

| | No mesh | Library (Resilience4j, gRPC interceptors) | Mesh |
| --- | --- | --- | --- |
| Languages | any | one per implementation | any |
| Touches app code | — | yes | no |
| mTLS between services | do it yourself | do it yourself | automatic |
| L7 metrics per route | instrument each service | per library | automatic |
| Retries, timeouts | per call site | per library | per route |
| Cost | none | dev time, drift between services | latency per hop, RAM per pod, a control plane |
| Who operates it | nobody | the dev teams | the platform team |

Questions worth landing on for the SGA context:

- How many services, in how many languages? A mesh earns its cost across a
  polyglot estate and rarely across three Java services.
- Is mTLS between services a compliance requirement, or a nice-to-have?
- Who runs the control plane at 3am, and have they upgraded one before?
- What does the latency budget from slot 1 have left for one more hop each way?
