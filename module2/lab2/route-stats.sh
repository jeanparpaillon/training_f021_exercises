#!/bin/sh
# Per-route counters from the Linkerd proxies of one Deployment, summed over
# its pods: what the caller asked for, and what the proxy actually sent.
#
#   lab2/route-stats.sh reviews-v2          # every route reviews-v2 calls
#   lab2/route-stats.sh productpage-v1 reviews
#
# `linkerd viz routes` would show this as EFFECTIVE vs ACTUAL, but it only
# reads ServiceProfiles. HTTPRoutes report through these proxy metrics:
#
#   requests   outbound_http_route_request_statuses_total           one per call
#                                                                   from the app
#   attempts   outbound_http_route_backend_response_statuses_total  one per try,
#                                                                   retries included
#   retries    outbound_http_route_retry_requests_total
#
# The counters are cumulative since each pod started: run it twice and
# subtract, or compare ratios.
set -eu
DEPLOY=${1:?usage: $0 <deployment> [route-name]}
ROUTE=${2:-}

linkerd diagnostics proxy-metrics -n "${NS:?set NS}" "deploy/$DEPLOY" |
  awk -v want="$ROUTE" '
    /^outbound_http_route_(request_statuses|backend_response_statuses|retry_requests)_total\{/ {
      match($0, /route_name="[^"]*"/); route = substr($0, RSTART + 12, RLENGTH - 13)
      if (want != "" && route != want) next
      status = ""
      if (match($0, /http_status="[^"]*"/)) status = substr($0, RSTART + 13, RLENGTH - 14)
      if (match($0, /error="[^"]*"/) && RLENGTH > 8) status = status (status ? " " : "") substr($0, RSTART + 7, RLENGTH - 8)
      if ($0 ~ /^outbound_http_route_request_statuses/)       kind = "requests"
      else if ($0 ~ /^outbound_http_route_backend_response/)  kind = "attempts"
      else { kind = "retries"; status = "" }
      n[route " " kind " " status] += $NF
    }
    END { for (k in n) printf "%-50s %8d\n", k, n[k] }' |
  sort
