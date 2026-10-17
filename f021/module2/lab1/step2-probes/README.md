# Step 2 — probes done right

**Slide:** Lab 1 — probes done right · **~20 min**

Three probes, each answering one question and nothing more
([`probes.yaml`](probes.yaml)):

| Probe | Question | Failing means | Here |
| --- | --- | --- | --- |
| `startupProbe` | has it finished booting? | keep waiting (up to a limit) | `reviews` only: 60 × 2 s |
| `readinessProbe` | should it get traffic now? | removed from the EndpointSlice | every service, 2 misses × 5 s |
| `livenessProbe` | is it stuck beyond repair? | container restarted | every service, 3 misses × 10 s, 5 s timeout |

All three hit each service's own `/health`, which answers from the process
without calling anything else.

```sh
kubectl -n "$NS" apply -k lab1/step2-probes
kubectl -n "$NS" get pods -w                 # watch reviews go 1/2 -> 2/2
kubectl -n "$NS" get events --field-selector reason=Unhealthy
```

The `Startup probe failed … 502` events while `reviews` boots are expected.
The Linkerd proxy is up before the JVM and answers `502` for it until Open
Liberty listens. The startup probe exists to absorb exactly that.

## Did it help?

Replay operation 2 of step 1, restarting all three `reviews` versions under
load, and compare the degraded pages with your baseline. New pods now get
traffic only once they answer.

## The trap

A liveness probe that looks thorough: it fetches `/productpage`, the real
page, so it "checks everything"
([`trap-liveness.yaml`](trap-liveness.yaml)). It does, and that is the
problem. Under a steady load nothing happens, because the page answers in
20 ms. It takes a slow dependency to spring it.

**First, a slow dependency with the sane probes.** Replace `ratings` with
the black hole, a pod that accepts connections and never answers:

```sh
kubectl -n "$NS" apply -f faults/ratings-blackhole.yaml
kubectl -n "$NS" scale deploy/ratings-v1 --replicas=0
kubectl -n "$NS" delete job k6 --ignore-not-found && kubectl -n "$NS" apply -f k6/constant-load.yaml
```

Latency goes up and ratings disappear from the page, but look at
`http_req_failed` and at `RESTARTS`: the application is degraded, not down.

**Now spring the trap**, with the black hole still in place:

```sh
kubectl -n "$NS" patch deploy productpage-v1 --patch-file lab1/step2-probes/trap-liveness.yaml
kubectl -n "$NS" rollout status deploy/productpage-v1
kubectl -n "$NS" delete job k6 --ignore-not-found && kubectl -n "$NS" apply -f k6/constant-load.yaml
kubectl -n "$NS" get pods -l app=productpage -w          # RESTARTS
kubectl -n "$NS" get events --field-selector reason=Unhealthy
```

`Liveness probe failed: … context deadline exceeded`, then `Container
productpage failed liveness probe, will be restarted`. The same slow
dependency now produces failed requests, because every restart is a window
with no productpage at all.

**Undo both**:

```sh
kubectl -n "$NS" apply -k lab1/step2-probes     # sane liveness, and ratings-v1 back to 1
kubectl -n "$NS" delete -f faults/ratings-blackhole.yaml
```

Re-applying the step also scales `ratings-v1` back to 1, because the base
says `replicas: 1`. Delete the black hole anyway, or half the `ratings`
calls keep hanging.

## Questions

- Why did a healthy `productpage` get killed? What did restarting it fix?
- There is one `productpage` pod here. With five, all probing the same slow
  dependency, why would each restart make the remaining pods *more* likely
  to fail?
- A readiness probe on `reviews` that checks `ratings` would look
  reasonable. What happens to the whole `reviews` Service the moment
  `ratings` goes down?
- The `reviews` startup probe allows 120 s. What does the kubelet do if
  Open Liberty needs 121?
