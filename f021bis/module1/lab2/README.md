# Lab 2 — add and upgrade a component: Linkerd with Helm

**Slides:** *Upgrading what runs on Kubernetes*, then *Lab 2* · **~75 min**

`prod` is born here and carries labs 2 to 5. Linkerd goes on it the way it
will be maintained — Helm, pinned versions, values in files — and is
upgraded the way it has to be: CRDs, control plane, data plane, clients.

| Step | | ~ |
| --- | --- | --- |
| [step1-cluster](step1-cluster/) | `prod` + Bookinfo | 10 min |
| [step2-apis](step2-apis/) | API versions, a legacy manifest | 15 min |
| [step3-install](step3-install/) | Linkerd `LINKERD_FROM` with Helm, mesh Bookinfo | 20 min |
| [step4-upgrade](step4-upgrade/) | to `LINKERD_TO`, in order | 20 min |
| [step5-rollback](step5-rollback/) | `helm rollback`, and what it does to CRDs | 10 min |

| File | What it is |
| --- | --- |
| [`kind.yaml`](kind.yaml) | `prod`: 1 control plane (NodePort 30080 on 127.0.0.1) + 1 worker |
| [`values/`](values/) | Helm values of the control plane and viz releases |
| `certs/` | trust anchor and issuer, made in step 3 (git-ignored) |

**End state** (start of lab 3): `prod` at `K8S_FROM`, Linkerd `LINKERD_TO`
with viz, Bookinfo meshed in namespace `bookinfo`. From nothing:
`make catch-up-lab2` in `module1/`.

```sh
cd ~/trainings_exercises/f021bis/module1
source versions.env
```
