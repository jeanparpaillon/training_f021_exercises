# etcdctl and etcdutl without installing them, and without the API.
#
#   source lab0/etcdctl.sh
#   etcdctl <node> <etcdctl args…>     e.g. etcdctl ha-control-plane member list -w table
#   etcdutl <node> <etcdutl args…>     e.g. etcdutl prod-control-plane snapshot status /var/lib/etcd/snap.db
#   etcdlogs <node> [crictl logs args…] logs of the node's latest etcd container,
#                                       running or not
#
# What it does, and what you will type by hand in lab 4:
#
#   docker exec <node>                  into the kind node (a container of
#                                       your console's Docker daemon)
#     crictl ps -q --name '^etcd$'      the etcd container of that node, from
#                                       the node's container runtime: works
#                                       when the API server is down, unlike
#                                       `kubectl exec`
#     crictl exec <id> etcdctl          etcdctl and etcdutl ship in the etcd
#                                       image, same version as the server
#       --endpoints https://127.0.0.1:2379
#                                       the local member only; --cluster on
#                                       a subcommand reaches the others
#       --cacert/--cert/--key           etcd only talks mTLS. kubeadm's
#                                       healthcheck-client certificate is
#                                       signed by the etcd CA, which is all
#                                       etcd checks (no etcd RBAC here)
#
# Paths are inside the etcd container: /etc/kubernetes/pki/etcd and
# /var/lib/etcd are hostPath mounts of the same paths on the node.

_etcd_in_node() {
  local node=$1; shift
  # $@ is passed to the inner shell as positional parameters, so arguments
  # with spaces or quotes survive the two hops.
  docker exec "$node" sh -c '
    id=$(crictl ps -q --name "^etcd$" --state running | head -n1)
    if [ -z "$id" ]; then
      echo "no running etcd container on $(hostname): see etcdlogs $(hostname)" >&2
      exit 1
    fi
    exec crictl exec "$id" "$@"' etcd-in-node "$@"
}

etcdctl() {
  local node=${1:?usage: etcdctl <node> <args…>}; shift
  _etcd_in_node "$node" etcdctl \
    --endpoints https://127.0.0.1:2379 \
    --cacert /etc/kubernetes/pki/etcd/ca.crt \
    --cert /etc/kubernetes/pki/etcd/healthcheck-client.crt \
    --key /etc/kubernetes/pki/etcd/healthcheck-client.key \
    "$@"
}

etcdutl() {
  local node=${1:?usage: etcdutl <node> <args…>}; shift
  _etcd_in_node "$node" etcdutl "$@"
}

etcdlogs() {
  local node=${1:?usage: etcdlogs <node> [crictl logs args…]}; shift
  docker exec "$node" sh -c '
    id=$(crictl ps -a -q --name "^etcd$" | head -n1)
    [ -n "$id" ] || { echo "no etcd container on $(hostname)" >&2; exit 1; }
    exec crictl logs "$@" "$id"' etcdlogs "$@"
}
