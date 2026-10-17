symptom="the stars are gone from the page"

break_it() {
  # reviews calls ratings on a port nothing listens on. RATINGS_SERVICE_PORT
  # is read by reviews (LibertyRestEndpoint.java) — and is also the name of
  # the variable Kubernetes injects for the `ratings` Service, which an
  # explicit env entry overrides.
  $K -n $NS set env deploy/reviews-v2 RATINGS_SERVICE_PORT=9081 >/dev/null
  $K -n $NS rollout status deploy/reviews-v2 --timeout=300s >/dev/null
}

check_it() { page_ok 10; }

fix_it() {
  $K -n $NS set env deploy/reviews-v2 RATINGS_SERVICE_PORT- >/dev/null
  $K -n $NS rollout status deploy/reviews-v2 --timeout=300s >/dev/null
}
