# Shared by lab5/break, check, reset and the scenarios. Not for you to run.
set -euo pipefail
NS=bookinfo
CTX=kind-prod
K="kubectl --context $CTX"
PAGE=http://127.0.0.1:30080/productpage
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

die() { echo "$*" >&2; exit 1; }

# The context must be prod's: these scripts run docker exec on its nodes.
$K get --raw /readyz >/dev/null 2>&1 \
  || die "context $CTX does not answer: is prod up? (kind get clusters)"

# N page loads; fails if any is not a 200 with ratings and reviews shown, or
# takes longer than MAX seconds.
page_ok() {
  local n=${1:-20} max=${2:-2} i out code t
  for i in $(seq "$n"); do
    out=$(curl -s -m 10 -w '\n%{http_code} %{time_total}' "$PAGE") || return 1
    read -r code t <<<"$(tail -n1 <<<"$out")"
    [ "$code" = 200 ] || return 1
    awk -v t="$t" -v m="$max" 'BEGIN { exit !(t <= m) }' || return 1
    grep -q 'currently unavailable' <<<"$out" && return 1
  done
  return 0
}

# The node that runs a pod of app=$1.
node_of() { $K -n $NS get pod -l app="$1" -o jsonpath='{.items[0].spec.nodeName}'; }

# The pod CIDR of a node.
pod_cidr() { $K get node "$1" -o jsonpath='{.spec.podCIDR}'; }
