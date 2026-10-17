#!/usr/bin/env bash
# Shared cluster only — run by the trainer from their machine (context with
# exec rights in namespace `consoles`), not by attendees.
#
# Installs the flux CLI in every attendee web console, in ~/bin of the
# console's home volume: it survives pod restarts, needs no root and no change
# to the console image. ~/bin is put on the PATH by install-helm-consoles.sh,
# which has to have run once before.
#
#   shared-cluster/install-flux-consoles.sh                 # every console
#   shared-cluster/install-flux-consoles.sh jean ahlem      # some of them
#   FLUX_VERSION=v2.7.2 shared-cluster/install-flux-consoles.sh
#
# Idempotent: a console that already has this version is left alone. Latest
# release by default; pin it to the controllers' version once `flux install`
# has run on the cluster (`flux version` shows both).
set -euo pipefail

NS=consoles
if [ -z "${FLUX_VERSION:-}" ]; then
  FLUX_VERSION=$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
    https://github.com/fluxcd/flux2/releases/latest)
  FLUX_VERSION=${FLUX_VERSION##*/}
fi
echo "flux $FLUX_VERSION"

if [ $# -gt 0 ]; then
  consoles=("$@")
else
  mapfile -t consoles < <(kubectl -n "$NS" get deploy -o name | sed -n 's|^deployment.apps/console-||p')
fi

# Runs inside the console, as user trainee.
remote=$(cat <<'EOF'
set -euo pipefail
v=$1
n=${v#v}
mkdir -p "$HOME/bin"
if [ -x "$HOME/bin/flux" ] && [ "$("$HOME/bin/flux" version --client 2>/dev/null)" = "flux: $v" ]; then
  echo "already $v"
else
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  base="https://github.com/fluxcd/flux2/releases/download/$v"
  f="flux_${n}_linux_amd64.tar.gz"
  curl -fsSL -o "$tmp/$f" "$base/$f"
  curl -fsSL -o "$tmp/checksums.txt" "$base/flux_${n}_checksums.txt"
  (cd "$tmp" && grep " $f\$" checksums.txt | sha256sum -c --quiet)
  tar -xzf "$tmp/$f" -C "$tmp" flux
  install -m 0755 "$tmp/flux" "$HOME/bin/flux"
  echo "installed $("$HOME/bin/flux" version --client)"
fi
case ":$PATH:" in
  *":$HOME/bin:"*) ;;
  *) echo "warning: ~/bin not on PATH, run install-helm-consoles.sh" >&2 ;;
esac
EOF
)

rc=0
for c in "${consoles[@]}"; do
  printf '%-12s ' "$c"
  if ! kubectl -n "$NS" exec "deploy/console-$c" -- bash -lc "$remote" _ "$FLUX_VERSION" 2>&1 | tail -1; then
    rc=1
  fi
done
exit $rc
