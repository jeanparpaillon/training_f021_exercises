# Step 4 — init container and sidecar

**Slide:** Lab 1 — init container and sidecar · **~15 min**

Two of the pod-level patterns from slot 1, on the running application.

```sh
kubectl -n "$NS" apply -k lab1/step4-patterns
kubectl -n "$NS" rollout status deploy/productpage-v1
kubectl -n "$NS" rollout status deploy/reviews-v1
```

## Init container — `wait-for-details` on productpage

Runs to completion *before* the app container starts, and blocks the pod until
`details` answers on `/health`.

```sh
kubectl -n "$NS" logs deploy/productpage-v1 -c wait-for-details
kubectl -n "$NS" get pod -l app=productpage -o wide
```

To see it actually block, scale `details` down and restart productpage:

```sh
kubectl -n "$NS" scale deploy/details-v1 --replicas=0
kubectl -n "$NS" rollout restart deploy/productpage-v1
kubectl -n "$NS" get pods -l app=productpage    # STATUS: Init:0/1
kubectl -n "$NS" scale deploy/details-v1 --replicas=1
```

The pod unblocks on its own once `details` is back.

## Sidecar — `log-shipper` on reviews

A second container in the same pod, sharing the pod's volumes. `reviews` runs
on Open Liberty with `LOG_DIR=/tmp/logs`, so it writes to a **file** that
`kubectl logs` would never show. The sidecar mounts the same emptyDir and
re-emits it on stdout.

```sh
kubectl -n "$NS" get pod -l app=reviews,version=v1   # READY 2/2, not 1/1
kubectl -n "$NS" logs deploy/reviews-v1 -c log-shipper
```

If nothing appears, look at what is actually on the volume — the pattern is
the shared volume and the shared lifecycle, not the specific file:

```sh
kubectl -n "$NS" exec deploy/reviews-v1 -c log-shipper -- ls -la /tmp/logs
```

In production this container is Fluent Bit or Vector reading the same path.

## What the patterns do and do not buy you

- An init container fixes a dependency that is missing **at startup**. It does
  nothing when `details` disappears an hour later — step 6 shows exactly that.
- A sidecar shares the pod's lifecycle: it is scheduled, scaled, and killed
  with the app, and it can see the app's volumes and localhost. That is also
  how a service mesh gets its proxy in, which is lab 2.
- Kubernetes 1.29+ has **native sidecars**: an `initContainers` entry with
  `restartPolicy: Always`. It starts before the app, keeps running alongside
  it, and is torn down after it — which fixes the old problem of a sidecar
  outliving a Job.

## Questions to answer before moving on

- The pod is now `2/2`. What does a readiness probe on the app container say
  about the sidecar's health? (Nothing — check the manifest.)
- The init container polls `details` every 2 seconds with no upper bound. What
  breaks if `details` is never coming back?
