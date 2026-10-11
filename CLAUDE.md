# training_f021_exercises

This repo hosts the exercises for **training_f021** (Advanced Kubernetes training).
The training material itself lives in the sibling repo `../training_f021`.

Each module contains exercises for corresponding module in `training_f021/slides/pages`

Exercises rely on a Kubernetes cluster, either the **shared cluster** of the session
(see `shared-cluster/README.md`: `srv2052563.hstgr.cloud`, one namespace per attendee,
driven from a local `kubectl`, services published by path through Traefik) or one
deployed locally with `kind` (https://kind.sigs.k8s.io/) (or `k3s` if machine allows it).

Anything an attendee exposes over HTTP must work on both: on the shared cluster an
Ingress uses `ingressClassName: traefik`, host `srv2052563.hstgr.cloud`, paths
`/<ns>/<app>/...` and the annotation
`traefik.ingress.kubernetes.io/router.middlewares: traefik-strip-ns-app@kubernetescrd`.
Attendees cannot create Traefik Middlewares themselves. Files that carry the namespace
are rendered from a `.tmpl` with `sed "s/CHANGEME/$NS/g"` and git-ignored.