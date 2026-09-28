# Step 3 — graceful shutdown

**Slide:** Lab 1 — graceful shutdown · **~15 min**

## Measure first

Replay operation 3 of step 1, the rolling restart of `productpage` under
load, a couple of times. Readiness probes do not help here. They control
when a pod *enters* the endpoints, not what happens when it leaves.

```sh
kubectl -n "$NS" delete job k6 --ignore-not-found && kubectl -n "$NS" apply -f k6/constant-load.yaml
sleep 20; kubectl -n "$NS" rollout restart deploy/productpage-v1
kubectl -n "$NS" logs -f job/k6 -c k6
```

To see what the failures are, tap the pods while it happens:

```sh
linkerd -n "$NS" viz tap deploy/productpage-v1 --path /productpage | grep -v ":status=200"
```

`:status=502`, answered by the Linkerd proxy of the pod that is going away:
the request reached the pod, and the application behind the proxy had
already stopped listening.

## Why

When a pod is deleted, two things start **at the same time**:

```
           kubectl delete / rollout
                     |
        +------------+-------------+
        v                          v
  endpoints controller          kubelet
  removes the pod from          runs preStop, then
  the EndpointSlice             sends SIGTERM
        |                          |
        v                          v
  every client's view           gunicorn stops
  updates, when it gets         accepting
  round to it
```

Nothing makes the left side finish before the right side starts. The fix is
to delay the right side.

## The fix

[`shutdown.yaml`](shutdown.yaml), on every Bookinfo Deployment:

- `lifecycle.preStop.sleep.seconds: 5` keeps the pod serving while the
  endpoint removal propagates. This is Kubernetes' own sleep action, so it
  needs no `sleep` binary in the image.
- `terminationGracePeriodSeconds: 30` is the budget for the preStop plus
  the drain after SIGTERM. Past it, SIGKILL.
- `config.alpha.linkerd.io/proxy-wait-before-exit-seconds: "10"` keeps
  the proxy alive after the application.

```sh
kubectl -n "$NS" apply -k lab1/step3-shutdown
diff <(kubectl kustomize lab1/step2-probes) <(kubectl kustomize lab1/step3-shutdown)
```

Restart again under load. **The target is zero failed requests.**

## About that Linkerd annotation

Look at what the injector did with it:

```sh
kubectl -n "$NS" get pod -l app=productpage -o jsonpath=\
'{range .items[0].spec.initContainers[*]}{.name}{" "}{.restartPolicy}{" "}{.lifecycle}{"\n"}{end}'
```

The proxy runs as a **native sidecar** (`restartPolicy: Always`), and it
has no `preStop` of its own. The kubelet already stops native sidecars
*after* the application containers, which is exactly the ordering the
annotation used to fake with a sleep. So here it is a no-op. It stays in
the manifest because a cluster whose mesh runs with
`proxy.nativeSidecar=false` needs it: there, application and proxy get
SIGTERM together, and the proxy can die first.

## Questions

- Endpoint removal and SIGTERM happen at the same time, not one after the
  other. So what exactly was failing before the `preStop`?
- 5 s of sleep: what decides whether that is enough, and what does it cost
  on a Deployment with 50 replicas and `maxUnavailable: 1`?
- `k6` is in the mesh. A client that is not, and that keeps connections
  open through kube-proxy, stays pinned to the old pod after it has left
  the endpoints. Which side has to fix that, the server or the client?
- What would the application code still have to do that no manifest can do
  for it? (Hint: what does gunicorn do with requests in flight on SIGTERM,
  and what would a shell script as PID 1 do with the signal?)
