# Step 3 — upgrade the control plane

**Slides:** You have to upgrade · The kubeadm upgrade, step by step · **~15 min**

Long load, and an API watcher in another tab: the two do not see the same
thing.

```sh
lab3/load > k6.log 2>&1 &              # 25 min: through step 4
while true; do echo "$(date +%T) $(kubectl get --raw /readyz --request-timeout=2s 2>&1 | head -1)"; sleep 1; done
```

## In the node

```sh
docker exec -it -e K8S_TO="$K8S_TO" prod-control-plane bash
```

kubeadm first — on a real node `apt-mark unhold kubeadm && apt-get install
kubeadm=…`; here the binary:

```sh
curl -fsSLo /tmp/kubeadm "https://dl.k8s.io/release/$K8S_TO/bin/linux/amd64/kubeadm"
install -m 0755 /tmp/kubeadm /usr/bin/kubeadm
kubeadm version -o short
kubeadm upgrade plan
```

`plan` proposes the latest patches — a newer patch than `K8S_TO`, and the
latest patch of the current minor. We go to `K8S_TO` on purpose: it is the
version of the kind node images, the one a new cluster would be created at
(lab 4 step 6). Note what `plan` says about etcd and CoreDNS.

```sh
kubeadm upgrade apply "$K8S_TO" -y --ignore-preflight-errors=SystemVerification
```

The ignored check reads the host kernel's configuration, which a container
cannot see; kind ignores it at creation too. Any other preflight error is
real: stop and read it.

While it runs (~5 min), from another tab:

```sh
docker exec prod-control-plane crictl ps --name 'kube-|etcd'     # CREATED changes one by one
docker exec prod-control-plane ls /etc/kubernetes/tmp/            # kubeadm's backups of the manifests
```

## What you should see

On a dry run: the API failed `/readyz` for ~60 s in total (a single
control plane: each restart is an outage of the API), the page answered
599 requests out of 599. Then:

```sh
kubectl get nodes                       # still K8S_FROM: kubelets are not upgraded yet
kubectl -n kube-system get pods -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[0].image
```

## Questions

- The API was down for a minute and no user noticed. Why? Who would have?
  (Anything that needs the API: a rollout, a scale-up, a crashed pod.)
- With three control planes: what runs on the second and third, and what is
  the skew between API servers during the upgrade?
- Where would you go back to if `apply` failed halfway?
