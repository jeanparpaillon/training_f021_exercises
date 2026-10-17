# Image of the trainees' web consoles (templates/trainee.yaml.tmpl).
# Built on the server and loaded into the kind node (make image): no
# registry involved. Bump CONSOLE_IMAGE in the Makefile on every change.
FROM ubuntu:24.04

ARG TTYD_VERSION=1.7.7
ARG KUBERNETES_MINOR=v1.37
ARG KIND_VERSION=v0.33.0
ARG HELM_VERSION=v4.3.0
# etcdctl / etcdutl only (no server): kubeadm's etcd for KUBERNETES_MINOR, so
# the same minor as the clusters lab 3 upgrades to. The labs still go through
# the etcd container (module1/lab0/etcdctl.sh), which has the certificates.
ARG ETCD_VERSION=v3.7.0

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg tini \
      bash-completion less vim nano jq git make openssh-client \
      iproute2 iputils-ping dnsutils netcat-openbsd \
      python3 python3-pip python3-venv ansible \
 && rm -rf /var/lib/apt/lists/*

# docker CLI (the daemon is the pod's dind sidecar) and kubectl, from their
# apt repositories: kubectl follows the cluster's minor version.
RUN install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
 && echo "deb [signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable" \
      > /etc/apt/sources.list.d/docker.list \
 && curl -fsSL "https://pkgs.k8s.io/core:/stable:/${KUBERNETES_MINOR}/deb/Release.key" \
      | gpg --dearmor -o /etc/apt/keyrings/kubernetes.gpg \
 && echo "deb [signed-by=/etc/apt/keyrings/kubernetes.gpg] https://pkgs.k8s.io/core:/stable:/${KUBERNETES_MINOR}/deb/ /" \
      > /etc/apt/sources.list.d/kubernetes.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends docker-ce-cli docker-buildx-plugin kubectl \
 && rm -rf /var/lib/apt/lists/*

RUN set -eu; cd /tmp \
 && curl -fsSLO "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.x86_64" \
 && curl -fsSL "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/SHA256SUMS" \
      | grep ' ttyd.x86_64$' | sha256sum -c - \
 && install -m 0755 ttyd.x86_64 /usr/local/bin/ttyd \
 && curl -fsSLo kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64" \
 && echo "$(curl -fsSL "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64.sha256sum" | cut -d' ' -f1)  kind" \
      | sha256sum -c - \
 && install -m 0755 kind /usr/local/bin/kind \
 && f="helm-${HELM_VERSION}-linux-amd64.tar.gz" \
 && curl -fsSLO "https://get.helm.sh/$f" \
 && curl -fsSLO "https://get.helm.sh/$f.sha256sum" \
 && sha256sum -c "$f.sha256sum" \
 && tar -xzf "$f" linux-amd64/helm \
 && install -m 0755 linux-amd64/helm /usr/local/bin/helm \
 && f="etcd-${ETCD_VERSION}-linux-amd64.tar.gz" \
 && curl -fsSLO "https://github.com/etcd-io/etcd/releases/download/${ETCD_VERSION}/$f" \
 && curl -fsSL "https://github.com/etcd-io/etcd/releases/download/${ETCD_VERSION}/SHA256SUMS" \
      | grep " $f\$" | sha256sum -c - \
 && tar -xzf "$f" --strip-components=1 "etcd-${ETCD_VERSION}-linux-amd64/etcdctl" "etcd-${ETCD_VERSION}-linux-amd64/etcdutl" \
 && install -m 0755 etcdctl etcdutl /usr/local/bin/ \
 && rm -rf /tmp/*

COPY console-init /usr/local/bin/console-init

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/console-init"]
