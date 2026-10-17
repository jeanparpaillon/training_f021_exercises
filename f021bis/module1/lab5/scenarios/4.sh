symptom="the page works, but a rollout of details never finishes (kubectl -n bookinfo rollout status deploy/details-v1)"

break_it() {
  cat <<YAML | $K -n $NS apply -f - >/dev/null
apiVersion: v1
kind: ResourceQuota
metadata:
  name: bookinfo
spec:
  hard:
    limits.memory: 8Gi
YAML
  $K -n $NS rollout restart deploy/details-v1 >/dev/null
}

check_it() {
  $K -n $NS rollout status deploy/details-v1 --timeout=5s >/dev/null 2>&1 && page_ok 5
}

fix_it() {
  $K -n $NS delete resourcequota bookinfo --ignore-not-found >/dev/null
  $K -n $NS rollout status deploy/details-v1 --timeout=300s >/dev/null 2>&1 || true
}
