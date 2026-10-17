symptom="kubectl get nodes shows a node NotReady"

flags=/var/lib/kubelet/kubeadm-flags.env

break_it() {
  # A kubelet that cannot reach its container runtime: the node goes
  # NotReady after ~40 s, its pods are evicted ~5 min later.
  docker exec prod-worker sh -c "
    cp $flags $flags.lab5
    sed -i 's|\"\$| --container-runtime-endpoint=unix:///run/containerd/containerd.sock.lab5\"|' $flags
    systemctl restart kubelet"
}

check_it() {
  [ "$($K get node prod-worker -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')" = True ]
}

fix_it() {
  docker exec prod-worker sh -c "
    if [ -f $flags.lab5 ]; then mv $flags.lab5 $flags; systemctl restart kubelet; fi"
}
