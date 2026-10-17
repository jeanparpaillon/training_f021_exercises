# Step 2 — lose one member

**Slide:** Lab 1 — your tools · **~10 min**

**Hypothesis first:** with one of three members gone, what do `kubectl` and
the writer see? For how long?

## Break

```sh
etcdctl ha-control-plane endpoint status --cluster -w table   # RAFT INDEX before
date +%T; docker pause ha-control-plane3
```

## Observe

```sh
for i in $(seq 10); do kubectl get ns --request-timeout=3s >/dev/null && echo ok || echo FAIL; sleep 1; done
etcdctl ha-control-plane endpoint status --cluster -w table
kubectl get endpointslices -n default -l kubernetes.io/service-name=kubernetes -w
```

- The writer's log: how many `000`, and when did they stop?
- Envoy's log: when did it take `ha-control-plane3` out?
- The `kubernetes` EndpointSlice: when did the paused API server leave it?

Measured on a dry run: `kubectl` failed 2 requests out of 10 (Envoy needs
two failed health checks before it ejects), the writer 3. The writer's
path has no health check: it keeps being sent to the dead API server until
the others remove it from the EndpointSlice, about 15 s after its lease
stops being renewed.

## Repair

```sh
docker unpause ha-control-plane3
etcdctl ha-control-plane endpoint status --cluster -w table   # RAFT INDEX catches up
```

## Questions

- Two members out of three still accept writes. Why is a majority enough,
  and why must it be a majority?
- How many members would you need to survive two failures?
- What would have been different for the writer with a client-side health
  check — or with the writer going through the load balancer?
