# Module 1 — tools and images, in your console.
#
#   make -C lab0 tools        linkerd (LINKERD_CLI_FROM), step, velero into ~/bin
#   make -C lab0 linkerd-to   switch the linkerd CLI to LINKERD_CLI_TO (lab 2 step 4)
#   make -C lab0 pull         pre-pull both kindest/node images into your Docker
#   make -C lab0 check        what is installed / pulled
#   make -C lab0 charts       the Linkerd charts as local .tgz (slow helm.linkerd.io)
#
# Trainer, from module1/ on the trainer's machine, before slot 1:
#
#   make -C lab0 pull-consoles   `docker pull` both node images in every console
#
# Binaries are installed versioned (~/bin/linkerd-edge-26.8.4) and `linkerd`
# is a symlink to one of them: switching is instant and both stay around.

include ../versions.env

BIN ?= $(HOME)/bin
TMP := $(shell mktemp -d -u /tmp/lab0.XXXXXX)
GH  := https://github.com

# Trainer side: the f021bis dev cluster's kubeconfig (shared-cluster/Makefile,
# `make kubeconfig`).
CONSOLES_KUBECONFIG ?= ../../shared-cluster/kubeconfig
CONSOLES_KUBECTL := kubectl --kubeconfig=$(CONSOLES_KUBECONFIG) --context=training-f021bis -n consoles

tools: linkerd-from $(BIN)/step $(BIN)/velero

$(BIN):
	mkdir -p $@

# No checksum file is published for edge CLI builds.
$(BIN)/linkerd-%: | $(BIN)
	curl -fsSLo $@.part $(GH)/linkerd/linkerd2/releases/download/$*/linkerd2-cli-$*-linux-amd64
	chmod 0755 $@.part && mv $@.part $@

linkerd-from: $(BIN)/linkerd-$(LINKERD_CLI_FROM)
	ln -sfn linkerd-$(LINKERD_CLI_FROM) $(BIN)/linkerd
	$(BIN)/linkerd version --client --short

linkerd-to: $(BIN)/linkerd-$(LINKERD_CLI_TO)
	ln -sfn linkerd-$(LINKERD_CLI_TO) $(BIN)/linkerd
	$(BIN)/linkerd version --client --short

$(BIN)/step: | $(BIN)
	mkdir -p $(TMP) && cd $(TMP) \
	 && f=step_linux_$(STEP_VERSION)_amd64.tar.gz \
	 && curl -fsSLO $(GH)/smallstep/cli/releases/download/v$(STEP_VERSION)/$$f \
	 && curl -fsSL $(GH)/smallstep/cli/releases/download/v$(STEP_VERSION)/checksums.txt | grep " $$f\$$" | sha256sum -c - \
	 && tar -xzf $$f step_$(STEP_VERSION)/bin/step \
	 && install -m 0755 step_$(STEP_VERSION)/bin/step $@
	rm -rf $(TMP)

$(BIN)/velero: | $(BIN)
	mkdir -p $(TMP) && cd $(TMP) \
	 && f=velero-$(VELERO_VERSION)-linux-amd64.tar.gz \
	 && curl -fsSLO $(GH)/velero-io/velero/releases/download/$(VELERO_VERSION)/$$f \
	 && curl -fsSL $(GH)/velero-io/velero/releases/download/$(VELERO_VERSION)/CHECKSUM | grep " $$f\$$" | sha256sum -c - \
	 && tar -xzf $$f velero-$(VELERO_VERSION)-linux-amd64/velero \
	 && install -m 0755 velero-$(VELERO_VERSION)-linux-amd64/velero $@
	rm -rf $(TMP)

# ~1 GB each. kind finds them by digest in the local store and does not pull
# again at `kind create cluster`.
pull:
	docker pull $(KIND_NODE_FROM)
	docker pull $(KIND_NODE_TO)

pull-consoles:
	for d in $$($(CONSOLES_KUBECTL) get deploy -o name); do \
	  echo "== $$d"; \
	  $(CONSOLES_KUBECTL) exec $$d -c console -- docker pull -q $(KIND_NODE_FROM) & \
	  $(CONSOLES_KUBECTL) exec $$d -c console -- docker pull -q $(KIND_NODE_TO) & \
	done; wait

check:
	@for t in linkerd step velero kind kubectl helm docker; do \
	  printf '  %-8s ' $$t; command -v $$t >/dev/null 2>&1 && echo ok || echo MISSING; done
	@for i in $(KIND_NODE_FROM) $(KIND_NODE_TO); do \
	  if docker image inspect $$i >/dev/null 2>&1; then echo "  ok      $${i%@*}"; \
	  else echo "  MISSING $${i%@*}"; fi; done

.PHONY: tools linkerd-from linkerd-to pull pull-consoles check

# Every Linkerd chart of the module as a local .tgz, for when helm.linkerd.io
# is slow or unreachable: then pass CHARTS=~/charts to the module Makefile,
# and use ~/charts/<chart>-<version>.tgz instead of linkerd-edge/<chart>
# --version <version> in the step files.
CHARTS_DIR ?= $(HOME)/charts
charts:
	helm repo add linkerd-edge https://helm.linkerd.io/edge --force-update >/dev/null
	mkdir -p $(CHARTS_DIR)
	for c in linkerd-crds linkerd-control-plane linkerd-viz; do \
	  for v in $(LINKERD_FROM) $(LINKERD_TO); do \
	    [ -f $(CHARTS_DIR)/$$c-$$v.tgz ] || helm pull linkerd-edge/$$c --version $$v -d $(CHARTS_DIR); \
	  done; done
	ls $(CHARTS_DIR)

.PHONY: charts
