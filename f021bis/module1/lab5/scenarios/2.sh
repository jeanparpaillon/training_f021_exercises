symptom="the page has become slow"

# The veth of the MySQL pod, on its node: where the pod's packets enter it.
mysql_veth() {
  local ip n
  ip=$($K -n $NS get pod -l app=mysqldb -o jsonpath='{.items[0].status.podIP}')
  n=$(node_of mysqldb)
  docker exec "$n" ip route get "$ip" | sed -n 's/.* dev \([^ ]*\) .*/\1/p'
}

break_it() {
  # 400 ms on every packet into the MySQL pod. ratings opens a connection
  # per request, so each rating costs several round trips — seconds.
  #
  # A second, slow replica (ratings v-delayed) would not do: Linkerd
  # balances on latency (EWMA) and sends it almost nothing.
  local n dev
  n=$(node_of mysqldb); dev=$(mysql_veth)
  docker exec "$n" tc qdisc replace dev "$dev" root netem delay 400ms
}

check_it() {
  local n
  for n in prod-control-plane prod-worker; do
    docker exec "$n" tc qdisc show | grep -q netem && return 1
  done
  page_ok 10 2
}

fix_it() {
  local n dev
  for n in prod-control-plane prod-worker; do
    for dev in $(docker exec "$n" tc qdisc show | sed -n 's/.*netem.* dev \([^ ]*\) .*/\1/p;s/^qdisc netem [0-9a-f]*: dev \([^ ]*\) .*/\1/p' | sort -u); do
      docker exec "$n" tc qdisc del dev "$dev" root 2>/dev/null || true
    done
  done
}
