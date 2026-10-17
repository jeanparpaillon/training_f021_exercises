# Lab 5 — troubleshooting

**Slides:** *Troubleshooting*, then *Lab 5* · **~60 min**

Faults you did not inject, found with a method — **symptom, scope, layer** —
and the tool of each layer. `prod` at the end of lab 4 is the patient
(`make catch-up-lab4` in `module1/` if yours is gone).

```sh
cd ~/trainings_exercises/f021bis/module1
lab5/reset            # start from a healthy prod
lab5/break 1          # inject scenario 1; you are told only the symptom
lab5/check 1          # fixed yet?
```

- **Do not read [`scenarios/`](scenarios/) before you are done** with a
  scenario: the method is the exercise. Read it after, to compare your
  path with the cause.
- One scenario at a time, ~10 min each, **at least one per group**. Stuck
  for more than 10 min: the *Tools* column, then the trainer.
- Fix it the way you would in production — the object, the node — not with
  `lab5/reset`. `reset` is for starting over.
- For each command you run, write down **what it ruled out**.

| Group | # | What you are told | Tools that find it |
| --- | --- | --- | --- |
| Application, through the mesh | 1 | the stars are gone from the page | `linkerd viz edges`, `stat --to`, the app's logs |
| | 2 | the page has become slow | `linkerd viz stat` per deployment, then what ratings depends on, then the node |
| | 3 | the page does not answer at all | `describe svc`, `get endpointslices` |
| Kubernetes objects | 4 | a rollout of details never finishes | `rollout status`, the **ReplicaSet**'s events |
| Network / CNI | 5 | every box of the page says its service is unavailable | `kubectl debug` + `nslookup`, `get networkpolicy` |
| | 6 | some page loads fail or lose a box, others are fine | `-o wide` (which node?), pod IP to pod IP, `iptables-save` in the nodes |
| Storage | 7 | the ratings are unavailable since MySQL was restarted | `describe pod`, the PV's node affinity, `describe node` |
| Nodes | 8 | `kubectl get nodes` shows a node NotReady | `describe node`, `journalctl -u kubelet` in the node |

Fast pairs: 2 and 6 are the hardest.

## Tools you may not have used yet

```sh
# a shell with network tools next to a container that has none
kubectl -n bookinfo debug -it deploy/productpage-v1 --image=nicolaka/netshoot \
  --target=productpage -- bash
# the node itself
docker exec -it prod-worker bash        # crictl, journalctl, ip, iptables, tc
# the mesh's view
linkerd viz stat -n bookinfo deploy
linkerd viz edges -n bookinfo deploy
linkerd viz top -n bookinfo deploy/productpage-v1
```

## Debrief

For one scenario per pair: the first symptom, each command and what it
ruled out, the cause, the fix — and the shortest path in hindsight.

Two findings from writing this lab, to keep in mind while you look: a slow
or broken replica *behind the same Service as healthy ones* barely shows
under Linkerd, which balances on latency and sends it almost nothing; and
Bookinfo's productpage answers `200` with an apology when a dependency
fails — the status code alone says nothing.
