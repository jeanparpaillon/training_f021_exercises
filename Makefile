NAME := training

all:

create:
	kind create cluster --name $(NAME) --config=kind.yaml

delete:
	kind delete cluster --name $(NAME)

config:
	kubectl config use-context kind-$(NAME)

prereqs:
	go install sigs.k8s.io/kind@v0.33.0

help:
	@echo "Available targets:"
	@echo "  all       - Default target"
	@echo "  create    - Create the kind cluster"
	@echo "  delete    - Delete the kind cluster"
	@echo "  config    - Set kubectl context to the kind cluster"
	@echo "  prereqs   - Install prerequisites"
	@echo "  help      - Show this help message"

.PHONY: all create delete config prereqs help
