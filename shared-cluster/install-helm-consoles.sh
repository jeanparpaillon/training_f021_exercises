#!/usr/bin/env bash
# Shared cluster only — run by the trainer from their machine (context with
# exec rights in namespace `consoles`), not by attendees.
#
# Installs helm in every attendee web console, in ~/bin of the console's home
# volume: it survives pod restarts, needs no root and no change to the console
# image. Also puts ~/bin and ~/.linkerd2/bin on the PATH, once, in ~/.profile:
# the console runs `ttyd … bash -l`, and a login shell reads ~/.profile (or
# ~/.bash_profile), never ~/.bashrc on its own. A ~/.profile created here
# sources ~/.bashrc, as Debian's default one does.
#
#   shared-cluster/install-helm-consoles.sh                 # every console
#   shared-cluster/install-helm-consoles.sh jean ahlem      # some of them
#   HELM_VERSION=v4.3.0 shared-cluster/install-helm-consoles.sh
#
# Idempotent: a console that already has this version is left alone. Same
# version as on the server by default, so charts behave the same for both.
set -euo pipefail

HELM_VERSION=${HELM_VERSION:-v4.3.0}
NS=consoles

if [ $# -gt 0 ]; then
  consoles=("$@")
else
  mapfile -t consoles < <(kubectl -n "$NS" get deploy -o name | sed -n 's|^deployment.apps/console-||p')
fi

# Runs inside the console, as user trainee.
remote=$(cat <<'EOF'
set -euo pipefail
v=$1
mkdir -p "$HOME/bin"
if [ -x "$HOME/bin/helm" ] && "$HOME/bin/helm" version --short 2>/dev/null | grep -q "^$v+"; then
  echo "already $v"
else
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  f="helm-$v-linux-amd64.tar.gz"
  curl -fsSL -o "$tmp/$f" "https://get.helm.sh/$f"
  curl -fsSL -o "$tmp/$f.sha256sum" "https://get.helm.sh/$f.sha256sum"
  (cd "$tmp" && sha256sum -c --quiet "$f.sha256sum")
  tar -xzf "$tmp/$f" -C "$tmp" linux-amd64/helm
  install -m 0755 "$tmp/linux-amd64/helm" "$HOME/bin/helm"
  echo "installed $("$HOME/bin/helm" version --short)"
fi
marker='# added by install-helm-consoles.sh'
# Earlier versions of this script put the PATH in ~/.bashrc: drop it there.
sed -i "\|^$marker\$|,+1d" "$HOME/.bashrc" 2>/dev/null || true
if ! grep -qF "$marker" "$HOME/.profile" 2>/dev/null; then
  if [ ! -e "$HOME/.profile" ]; then
    # What Debian's skeleton ~/.profile does: a login shell reads only this
    # file, so it has to pull ~/.bashrc in (prompt, aliases, completion).
    printf '%s\n' \
      'if [ -n "$BASH_VERSION" ] && [ -f "$HOME/.bashrc" ]; then' \
      '    . "$HOME/.bashrc"' \
      'fi' > "$HOME/.profile"
  fi
  printf '\n%s\nexport PATH="$HOME/bin:$HOME/.linkerd2/bin:$PATH"\n' "$marker" >> "$HOME/.profile"
fi
EOF
)

rc=0
for c in "${consoles[@]}"; do
  printf '%-12s ' "$c"
  if ! kubectl -n "$NS" exec "deploy/console-$c" -- bash -c "$remote" _ "$HELM_VERSION" 2>&1 | tail -1; then
    rc=1
  fi
done
exit $rc
