# Lab 1 — break and repair an HA control plane

**Slides:** *Kubernetes High Availability Architectures*, then *Lab 1* · **~60 min**

The theory's failure table, measured on a real stacked-etcd control plane:
three kind nodes, each running an API server and an etcd member, behind
kind's load balancer.

| Step | | ~ |
| --- | --- | --- |
| [step1-build](step1-build/) | create `ha`, find every component | 10 min |
| [step2-lose-one](step2-lose-one/) | lose one member | 10 min |
| [step3-lose-quorum](step3-lose-quorum/) | lose two: no quorum | 10 min |
| [step4-leader](step4-leader/) | the leaders: etcd's, the controllers' | 5 min |
| [step5-partition](step5-partition/) | cut a member off its peers | 10 min |
| [step6-lost-member](step6-lost-member/) | a member loses its disk; repair it | 15 min |

## Before you start

```sh
cd ~/trainings_exercises/f021bis/module1
source versions.env
source lab0/etcdctl.sh
```

Open a second terminal (a second browser tab on your console) for the
writer's log: it runs for the whole lab.

## Rules for breaking nodes

- **Lose a node with `docker pause`, bring it back with `docker unpause`.**
  A paused node is frozen — no CPU, no answers — like a hung machine, and
  its network stays as it was.
- **Never `docker stop` two nodes and start them again.** Docker does not
  keep a stopped container's address: started in the wrong order, two
  nodes swap IPs, and every etcd peer URL and certificate SAN now points at
  the wrong member. The cluster does not recover. (`docker stop` of a
  single node usually gets its address back, but nothing promises it.)
- `ha-control-plane` runs the writer: never pause it.

## Fill this table as you go

| Failure | `kubectl` (through the LB) | writer (through the `kubernetes` Service) | running pods | back to normal after |
| --- | --- | --- | --- | --- |
| 1 member paused | | | | |
| 2 members paused | | | | |
| etcd leader moved / killed | | | | |
| 1 member partitioned | | | | |
| 1 member's disk lost | | | | |

## Clean up

```sh
kind delete cluster --name ha
```

The next labs need the memory. Nothing from this lab is reused.
