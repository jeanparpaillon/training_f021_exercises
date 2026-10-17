symptom="the ratings are unavailable since MySQL was restarted"

break_it() {
  local n
  n=$(node_of mysqldb)
  $K taint node "$n" storage=maintenance:NoSchedule --overwrite >/dev/null
  $K -n $NS delete pod -l app=mysqldb --wait=false >/dev/null
}

check_it() {
  $K -n $NS rollout status deploy/mysqldb-v1 --timeout=5s >/dev/null 2>&1 && page_ok 5
}

fix_it() {
  local n
  for n in $($K get nodes -o jsonpath='{.items[*].metadata.name}'); do
    $K taint node "$n" storage=maintenance:NoSchedule- >/dev/null 2>&1 || true
  done
  $K -n $NS rollout status deploy/mysqldb-v1 --timeout=300s >/dev/null 2>&1 || true
}
