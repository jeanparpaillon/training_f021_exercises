SRV = https://srv2052563.hstgr.cloud/

# Everything runs from the trainer's machine: commands that need the server
# (kind, docker, helm, the users file) go through ssh, kubectl uses the
# kubeconfig fetched by `make kubeconfig`.
HOST    := $(patsubst https://%/,%,$(SRV))
S       := root@$(HOST)
NAME    := training-f021bis
# Where the server keeps this directory's files that it needs (kind.yaml,
# traefik-values.yaml).
REMOTE  := /root/f021bis

KUBECONFIG_FILE := kubeconfig
KUBECTL := kubectl --kubeconfig=$(KUBECONFIG_FILE) --context=$(NAME)

# Bump the tag on every change to console/: kind-loaded images are never
# re-pulled, a new tag is what rolls the consoles.
CONSOLE_IMAGE   := f021bis-console:1
TRAEFIK_VERSION := 41.7.1

export HOST CONSOLE_IMAGE

all:
	@echo "First install: make sysctl create kubeconfig edge image render secrets apply"
	@echo "make help for the list of targets"

# Nested kind clusters (one or more per trainee, inside the dind sidecars)
# all share the server's kernel: the defaults run out of inotify instances
# after a few clusters ("too many open files" from kubelet / kube-proxy).
sysctl:
	ssh $(S) "printf '%s\n' fs.inotify.max_user_instances=8192 fs.inotify.max_user_watches=1048576 \
	  > /etc/sysctl.d/99-f021bis-kind.conf && sysctl -q --system"

create:
	ssh $(S) mkdir -p $(REMOTE)
	scp kind.yaml $(S):$(REMOTE)/kind.yaml
	ssh $(S) kind create cluster --name $(NAME) --config $(REMOTE)/kind.yaml

delete:
	ssh $(S) kind delete cluster --name $(NAME)

# Cluster-admin kubeconfig for this machine, context $(NAME), API on the
# public host name (in the certificate SANs, see kind.yaml). Git-ignored.
kubeconfig:
	ssh $(S) kind get kubeconfig --name $(NAME) \
	  | sed -e 's|https://0.0.0.0:6443|https://$(HOST):6443|' -e 's/kind-$(NAME)/$(NAME)/g' \
	  > $(KUBECONFIG_FILE)
	chmod 600 $(KUBECONFIG_FILE)
	$(KUBECTL) get nodes

# Traefik, the only HTTP layer (TLS, Let's Encrypt): see traefik-values.yaml.
edge:
	ssh $(S) mkdir -p $(REMOTE)
	scp traefik-values.yaml $(S):$(REMOTE)/traefik-values.yaml
	ssh $(S) "helm repo add traefik https://traefik.github.io/charts --force-update >/dev/null && \
	  helm upgrade --install traefik traefik/traefik --kube-context kind-$(NAME) \
	    -n traefik --create-namespace --version $(TRAEFIK_VERSION) \
	    -f $(REMOTE)/traefik-values.yaml --wait"

# Builds the console image on the server (context streamed over ssh) and
# loads it into the kind node.
image:
	tar -C console -c . | ssh $(S) docker build -t $(CONSOLE_IMAGE) -
	ssh $(S) kind load docker-image $(CONSOLE_IMAGE) --name $(NAME)

# trainees/ from the names of /root/users/consoles.txt (names only).
render:
	ssh $(S) "awk '{print \$$1}' /root/users/consoles.txt" | bin/render

# Console passwords, from /root/users/consoles.txt, on the server.
secrets:
	ssh $(S) 'bash -s' < bin/secrets

apply: render
	$(KUBECTL) apply -k .
	$(KUBECTL) -n consoles wait deploy --all --for=condition=Available --timeout=300s

# Restart every console (new image, stuck terminal…). Homes and Docker data
# are kept; trainees' kind clusters come back stopped.
restart:
	$(KUBECTL) -n consoles rollout restart deploy

check:
	$(KUBECTL) get nodes
	$(KUBECTL) -n consoles get deploy,pods,ingress
	@for n in $$(ls trainees/*.yaml | xargs -n1 basename | sed -n 's/\.yaml$$//p' | grep -vx kustomization); do \
	  printf '%-12s %s  ' $$n "$$(curl -s -o /dev/null -w '%{http_code}' $(SRV)$$n/)"; \
	  $(KUBECTL) -n consoles exec deploy/console-$$n -c console -- docker info --format '{{.ServerVersion}}' 2>&1 | tail -1; \
	done

help:
	@echo "Available targets:"
	@echo "  sysctl      - Raise the server's inotify limits for nested kind clusters"
	@echo "  create      - Create the kind cluster $(NAME) on the server"
	@echo "  delete      - Delete it (and every console home with it)"
	@echo "  kubeconfig  - Fetch a cluster-admin kubeconfig into ./$(KUBECONFIG_FILE)"
	@echo "  edge        - Install / upgrade Traefik"
	@echo "  image       - Build the console image on the server and load it into kind"
	@echo "  render      - Generate trainees/ from the server's users file"
	@echo "  secrets     - Create / update the console passwords from the users file"
	@echo "  apply       - render, then apply everything"
	@echo "  restart     - Restart every console"
	@echo "  check       - Consoles answer (401 = up, behind basic auth), dind is up"
	@echo "  help        - Show this help message"

.PHONY: all sysctl create delete kubeconfig edge image render secrets apply restart check help
