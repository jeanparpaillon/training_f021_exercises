all:

create:
	kind create cluster

prereqs:
	go install sigs.k8s.io/kind@v0.33.0

.PHONY: all kind prereqs