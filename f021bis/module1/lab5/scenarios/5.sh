symptom="every box of the page says its service is unavailable"

break_it() {
  # Looks like a sensible egress lockdown: anything in the cluster except
  # the system namespace. The cluster DNS lives there.
  cat <<YAML | $K -n $NS apply -f - >/dev/null
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: egress-in-cluster-only
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
    - to:
        - namespaceSelector:
            matchExpressions:
              - { key: kubernetes.io/metadata.name, operator: NotIn, values: [kube-system] }
YAML
}

check_it() {
  $K -n $NS exec deploy/productpage-v1 -c productpage -- \
    python -c 'import socket; socket.gethostbyname("details")' >/dev/null 2>&1 \
    && page_ok 5
}

fix_it() { $K -n $NS delete networkpolicy egress-in-cluster-only --ignore-not-found >/dev/null; }
