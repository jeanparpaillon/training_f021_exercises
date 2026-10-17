# Module 1 — pre-pull the container images used by lab1, lab2 and the
# advanced exercises, so a room of attendees does not stall on the
# registries at the start of a slot.
#
#   make pull            # everything (tools + bookinfo + emojivoto + meshes)
#   make pull-bookinfo   # lab1 only
#   make -j4 pull        # in parallel
#   make load            # push what was pulled into a kind cluster
#
# Versions are overridable: make pull ISTIO_VERSION=1.30.0
# So is the client, for a user outside the docker group, or for podman:
#   make pull DOCKER="sudo docker"


BOOKINFO_VERSION ?= 1.20.3
ISTIO_VERSION ?= 1.31.1
EMOJIVOTO_VERSION ?= v11
BUSYBOX_VERSION ?= 1.36
LINKERD_VERSION ?= edge-26.9.3
LINKERD_EXTENSION_INIT_VERSION ?= v0.1.12
LINKERD_PROMETHEUS_VERSION ?= v2.55.1

KIND_CLUSTER ?= kind

DOCKERIO_REGISTRY ?= docker.io
ISTIO_REGISTRY ?= registry.istio.io/release
LINKERD_REGISTRY ?= cr.l5d.io/linkerd

# lab1 + lab2 — toolbox, load generator, init container and log-shipper sidecar
TOOLS_IMAGES := \
	busybox:$(BUSYBOX_VERSION)

# lab1 — the multi-service application, deployed without a mesh
BOOKINFO_IMAGES := \
	$(ISTIO_REGISTRY)/examples-bookinfo-productpage-v1:$(BOOKINFO_VERSION) \
	$(ISTIO_REGISTRY)/examples-bookinfo-details-v1:$(BOOKINFO_VERSION) \
	$(ISTIO_REGISTRY)/examples-bookinfo-ratings-v1:$(BOOKINFO_VERSION) \
	$(ISTIO_REGISTRY)/examples-bookinfo-reviews-v1:$(BOOKINFO_VERSION) \
	$(ISTIO_REGISTRY)/examples-bookinfo-reviews-v2:$(BOOKINFO_VERSION) \
	$(ISTIO_REGISTRY)/examples-bookinfo-reviews-v3:$(BOOKINFO_VERSION)

# lab2 — Linkerd demo application
EMOJIVOTO_IMAGES := \
	ghcr.io/buoyantio/emojivoto-web:$(EMOJIVOTO_VERSION) \
	ghcr.io/buoyantio/emojivoto-emoji-svc:$(EMOJIVOTO_VERSION) \
	ghcr.io/buoyantio/emojivoto-voting-svc:$(EMOJIVOTO_VERSION)

# lab2 — Linkerd control plane, then the linkerd-viz extension
LINKERD_IMAGES := \
	$(LINKERD_REGISTRY)/controller:$(LINKERD_VERSION) \
	$(LINKERD_REGISTRY)/proxy:$(LINKERD_VERSION) \
	$(LINKERD_REGISTRY)/debug:$(LINKERD_VERSION) \
	$(LINKERD_REGISTRY)/metrics-api:$(LINKERD_VERSION) \
	$(LINKERD_REGISTRY)/tap:$(LINKERD_VERSION) \
	$(LINKERD_REGISTRY)/web:$(LINKERD_VERSION) \
	$(LINKERD_REGISTRY)/extension-init:$(LINKERD_EXTENSION_INIT_VERSION) \
	prom/prometheus:$(LINKERD_PROMETHEUS_VERSION)

# lab2 — Istio demo (the one that needs ~4 GB free)
ISTIO_IMAGES := \
	$(DOCKERIO_REGISTRY)/istio/pilot:$(ISTIO_VERSION) \
	$(DOCKERIO_REGISTRY)/istio/proxyv2:$(ISTIO_VERSION)

IMAGES := $(TOOLS_IMAGES) $(BOOKINFO_IMAGES) $(EMOJIVOTO_IMAGES) $(LINKERD_IMAGES) $(ISTIO_IMAGES)

DOCKER ?= docker
KIND ?= kind

# One target per image, so `make -j` pulls several at a time. A target name
# cannot contain `:`, so the tag separator is encoded as `+` and decoded again
# in the recipe. These per-image targets are deliberately *not* .PHONY: make
# does not apply implicit rules to phony targets, and the pattern rule is what
# gives them their recipe. They match no file on disk, so they always run.
target = $(subst :,+,$(1:%=$(2)/%))

pull: pull-tools pull-bookinfo pull-emojivoto pull-linkerd pull-istio

pull-tools: $(call target,$(TOOLS_IMAGES),pull)
pull-bookinfo: $(call target,$(BOOKINFO_IMAGES),pull)
pull-emojivoto: $(call target,$(EMOJIVOTO_IMAGES),pull)
pull-linkerd: $(call target,$(LINKERD_IMAGES),pull)
pull-istio: $(call target,$(ISTIO_IMAGES),pull)

pull/%:
	$(DOCKER) pull $(subst +,:,$*)

# kind nodes have their own image store: pulling on the host is not enough.
load: pull $(call target,$(IMAGES),load)

load/%:
	$(KIND) load docker-image --name $(KIND_CLUSTER) $(subst +,:,$*)

# What is already in the local store, and what is still missing.
check:
	@for img in $(IMAGES); do \
		if $(DOCKER) image inspect "$$img" >/dev/null 2>&1; then \
			echo "  ok      $$img"; \
		else \
			echo "  MISSING $$img"; \
		fi; \
	done

list:
	@for img in $(IMAGES); do echo "$$img"; done

help:
	@echo "pull            pull every image below (add -j4 to parallelise)"
	@echo "pull-tools      lab1+2: busybox, for the toolbox, loadgen and sidecars"
	@echo "pull-bookinfo   lab1: Bookinfo, the multi-service application"
	@echo "pull-emojivoto  lab2: emojivoto, the Linkerd demo application"
	@echo "pull-linkerd    lab2: Linkerd control plane and linkerd-viz"
	@echo "pull-istio      lab2: Istio control plane and sidecar"
	@echo "load            pull, then load into kind cluster '$(KIND_CLUSTER)'"
	@echo "check           report which images are already in the local store"
	@echo "list            print the image list"

.PHONY: pull pull-tools pull-bookinfo pull-emojivoto pull-linkerd pull-istio load check list help