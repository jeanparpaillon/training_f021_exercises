NAME := training

# kind-specific build of ingress-nginx: hostPort 80/443, nodeSelector
# ingress-ready=true (see kind.yaml).
INGRESS_NGINX_MANIFEST ?= https://kind.sigs.k8s.io/examples/ingress/deploy-ingress-nginx.yaml

all:

create:
	kind create cluster --name $(NAME) --config=kind.yaml

delete:
	kind delete cluster --name $(NAME)

config:
	kubectl config use-context kind-$(NAME)

ingress:
	kubectl --context kind-$(NAME) apply -f $(INGRESS_NGINX_MANIFEST)
	kubectl --context kind-$(NAME) -n ingress-nginx wait --for=condition=ready pod \
	  -l app.kubernetes.io/component=controller --timeout=180s

prereqs:
	go install sigs.k8s.io/kind@v0.33.0

help:
	@echo "Available targets:"
	@echo "  all       - Default target"
	@echo "  create    - Create the kind cluster"
	@echo "  delete    - Delete the kind cluster"
	@echo "  config    - Set kubectl context to the kind cluster"
	@echo "  ingress   - Install ingress-nginx in the kind cluster"
	@echo "  prereqs   - Install prerequisites"
	@echo "  help      - Show this help message"

.PHONY: all create delete config ingress prereqs help
