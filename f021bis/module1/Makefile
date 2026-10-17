# Module 1 — catch-up targets: rebuild `prod` at the end of a lab, from
# nothing, when yours is lost or hopelessly broken. Run from module1/, in
# your console. Each one starts with `make prod-cluster`, which does nothing
# if `prod` already exists.
#
#   make catch-up-lab2   prod at K8S_FROM, Linkerd LINKERD_TO + viz, Bookinfo meshed
#   make catch-up-lab3   prod at K8S_TO (created at that version, not upgraded),
#                        Linkerd HA, Bookinfo drain-safe
#   make catch-up-lab4   + ratings on MySQL, the S3 store, Velero
#
# The pieces are targets too (certs, linkerd, …): the step files show the
# commands they run, this is only for getting back on track.
#
# If helm.linkerd.io times out, `make -C lab0 charts` once, then add
# CHARTS=~/charts to any target here.

include versions.env

# Another cluster than prod (lab 4 step 6): CLUSTER=green KIND_CONFIG=…
CLUSTER     ?= prod
KIND_CONFIG ?= lab2/kind.yaml
KUBECTL  = kubectl --context kind-$(CLUSTER)
HELM     = helm --kube-context kind-$(CLUSTER)
CERTS   := lab2/certs
CHARTS  ?=
# $(call chart,<name>,<version>): from the repo, or from a local .tgz.
chart = $(if $(CHARTS),$(CHARTS)/$(1)-$(2).tgz,linkerd-edge/$(1) --version $(2))

LINKERD ?= $(LINKERD_TO)
CP_VALUES := -f lab2/values/control-plane.yaml
CERT_FLAGS := --set-file identityTrustAnchorsPEM=$(CERTS)/ca.crt \
  --set-file identity.issuer.tls.crtPEM=$(CERTS)/issuer.crt \
  --set-file identity.issuer.tls.keyPEM=$(CERTS)/issuer.key

catch-up-lab2: prod-cluster gateway-api certs linkerd bookinfo-meshed
catch-up-lab3: NODE_IMAGE = $(KIND_NODE_TO)
catch-up-lab3: CP_VALUES += -f lab3/step2-ready/linkerd-ha.yaml
catch-up-lab3: prod-cluster gateway-api certs linkerd bookinfo-ready
catch-up-lab4: NODE_IMAGE = $(KIND_NODE_TO)
catch-up-lab4: CP_VALUES += -f lab3/step2-ready/linkerd-ha.yaml
catch-up-lab4: prod-cluster gateway-api certs linkerd bookinfo-stateful velero

# Lab 4 step 6: `green`, at K8S_TO, with Linkerd (same certificates) and
# Velero on the same bucket — no Bookinfo: it comes from the backup.
green: CLUSTER = green
green: KIND_CONFIG = lab4/step6-migrate/kind.yaml
green: NODE_IMAGE = $(KIND_NODE_TO)
green: prod-cluster gateway-api certs linkerd velero

NODE_IMAGE ?= $(KIND_NODE_FROM)

prod-cluster:
	kind get clusters 2>/dev/null | grep -qx $(CLUSTER) \
	  || kind create cluster --name $(CLUSTER) --config $(KIND_CONFIG) --image $(NODE_IMAGE)
	$(KUBECTL) taint nodes $(CLUSTER)-control-plane node-role.kubernetes.io/control-plane:NoSchedule- 2>/dev/null || true

gateway-api:
	$(KUBECTL) apply --server-side -f \
	  https://github.com/kubernetes-sigs/gateway-api/releases/download/$(GATEWAY_API_VERSION)/standard-install.yaml

certs: $(CERTS)/issuer.crt

$(CERTS)/ca.crt:
	mkdir -p $(CERTS)
	step certificate create root.linkerd.cluster.local $(CERTS)/ca.crt $(CERTS)/ca.key \
	  --profile root-ca --no-password --insecure

$(CERTS)/issuer.crt: $(CERTS)/ca.crt
	step certificate create identity.linkerd.cluster.local $(CERTS)/issuer.crt $(CERTS)/issuer.key \
	  --profile intermediate-ca --not-after 8760h --no-password --insecure \
	  --ca $(CERTS)/ca.crt --ca-key $(CERTS)/ca.key

linkerd: certs
	helm repo add linkerd-edge https://helm.linkerd.io/edge --force-update >/dev/null
	$(HELM) upgrade --install linkerd-crds $(call chart,linkerd-crds,$(LINKERD)) \
	  -n linkerd --create-namespace
	$(HELM) upgrade --install linkerd-control-plane $(call chart,linkerd-control-plane,$(LINKERD)) \
	  -n linkerd $(CP_VALUES) $(CERT_FLAGS) --wait --timeout 10m
	$(HELM) upgrade --install linkerd-viz $(call chart,linkerd-viz,$(LINKERD)) \
	  -n linkerd-viz --create-namespace -f lab2/values/viz.yaml --wait --timeout 10m

bookinfo-meshed:
	$(KUBECTL) apply -k lab2/step3-install
	$(KUBECTL) -n bookinfo rollout status deploy --timeout=10m

bookinfo-ready:
	$(KUBECTL) apply -k lab3/step2-ready
	$(KUBECTL) -n bookinfo delete deploy reviews-v1 reviews-v3 --ignore-not-found
	$(KUBECTL) -n bookinfo rollout status deploy --timeout=10m

bookinfo-stateful:
	$(KUBECTL) apply -k lab4/step1-stateful
	$(KUBECTL) -n bookinfo delete deploy reviews-v1 reviews-v3 ratings-v1 --ignore-not-found
	$(KUBECTL) -n bookinfo delete pdb ratings-v1 --ignore-not-found
	$(KUBECTL) -n bookinfo rollout status deploy --timeout=10m

velero:
	url=$$(lab4/s3/start) && velero install --kubecontext kind-$(CLUSTER) \
	  --provider aws --plugins velero/velero-plugin-for-aws:$(VELERO_AWS_PLUGIN_VERSION) \
	  --image velero/velero:$(VELERO_VERSION) \
	  --bucket velero --secret-file lab4/s3/credentials-velero \
	  --backup-location-config region=us-east-1,s3ForcePathStyle=true,s3Url=$$url \
	  --use-node-agent --use-volume-snapshots=false --wait

.PHONY: catch-up-lab2 catch-up-lab3 catch-up-lab4 green prod-cluster gateway-api certs \
  linkerd bookinfo-meshed bookinfo-ready bookinfo-stateful velero
