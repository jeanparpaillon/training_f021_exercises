#!/usr/bin/env bash
# Shared cluster only — run by the trainer, ON THE SERVER (the passwords never
# leave it):
#
#   ssh root@srv2052563.hstgr.cloud 'bash -s' < shared-cluster/grafana-users.sh
#   ssh root@srv2052563.hstgr.cloud 'ROLE=Viewer bash -s' < shared-cluster/grafana-users.sh
#
# One Grafana user per line of /root/users/consoles.txt (`<name> <password>
# <url>`): login = the attendee's name, same password as their web console.
# Role Editor by default: attendees build dashboards in the labs.
#
# Idempotent: an existing user gets its password and role reset to the file's.
# Users are stored in Grafana's database (on its PVC), so they survive a pod
# restart but not an uninstall of the release.
set -euo pipefail

USERS=${USERS:-/root/users/consoles.txt}
ROLE=${ROLE:-Editor}
URL=${GRAFANA_URL:-https://grafana.srv2052563.hstgr.cloud}

admin_pw=$(kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d)
api() {  # method path [json]
  curl -sS -u "admin:$admin_pw" -H 'Content-Type: application/json' \
    -X "$1" "$URL$2" ${3:+--data-binary "$3"} -w '\n%{http_code}'
}
json() { python3 -c 'import json,sys; print(json.dumps(dict(zip(sys.argv[1::2], sys.argv[2::2]))))' "$@"; }

rc=0
while read -r name pw _; do
  [ -n "$name" ] || continue
  printf '%-12s ' "$name"
  out=$(api POST /api/admin/users "$(json name "$name" login "$name" email "$name@f021.local" password "$pw")")
  code=${out##*$'\n'}
  if [ "$code" = 200 ]; then
    id=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["id"])' "${out%$'\n'*}")
    state=created
  elif [ "$code" = 412 ]; then  # login already taken
    out=$(api GET "/api/users/lookup?loginOrEmail=$name")
    id=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["id"])' "${out%$'\n'*}")
    out=$(api PUT "/api/admin/users/$id/password" "$(json password "$pw")")
    [ "${out##*$'\n'}" = 200 ] || { echo "password reset failed: ${out%$'\n'*}"; rc=1; continue; }
    state=updated
  else
    echo "failed ($code): ${out%$'\n'*}"; rc=1; continue
  fi
  out=$(api PATCH "/api/org/users/$id" "$(json role "$ROLE")")
  [ "${out##*$'\n'}" = 200 ] || { echo "$state, role failed: ${out%$'\n'*}"; rc=1; continue; }
  echo "$state, $ROLE"
done < "$USERS"
exit $rc
