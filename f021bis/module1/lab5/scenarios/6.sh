symptom="some page loads fail or lose a box, others are fine"

break_it() {
  # On the worker, drop forwarded traffic coming from the control plane's
  # pods: same-node traffic is untouched, cross-node traffic one way dies.
  local src
  src=$(pod_cidr prod-control-plane)
  docker exec prod-worker iptables -I FORWARD -s "$src" -m comment --comment lab5 -j DROP
}

check_it() {
  ! docker exec prod-worker iptables -S FORWARD | grep -q 'lab5' && page_ok 20
}

fix_it() {
  local rule
  while rule=$(docker exec prod-worker iptables -S FORWARD | grep -m1 -- '--comment lab5'); do
    # shellcheck disable=SC2086
    docker exec prod-worker iptables ${rule/-A /-D }
  done
}
