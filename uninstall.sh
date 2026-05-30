#!/usr/bin/env bash
#
# uninstall.sh — remove the AgentPod image and persisted state.
set -eo pipefail

IMAGE="${AGENT_POD_IMAGE:-agent-pod}"
STATE_ROOT="${AGENT_POD_HOME:-$HOME/.agent-pod}"

if [ -t 1 ]; then
  C_INFO=$'\033[34m'; C_OK=$'\033[32m'; C_ERR=$'\033[31m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
  C_INFO=""; C_OK=""; C_ERR=""; C_DIM=""; C_OFF=""
fi
info() { printf '%s%s%s\n' "$C_INFO" "$*" "$C_OFF"; }
ok()   { printf '%s%s%s\n' "$C_OK"   "$*" "$C_OFF"; }
warn() { printf '%s%s%s\n' "$C_DIM"  "$*" "$C_OFF"; }
die()  { printf '%s%s%s\n' "$C_ERR"  "$*" "$C_OFF" >&2; exit 1; }

cat <<EOF
This will remove:
  - Docker image:   $IMAGE
  - State directory: $STATE_ROOT
      (per-agent auth tokens and conversation history for all agents)

This will NOT remove:
  - The base node image or Docker build cache
  - This repository / launcher script
  - Any project files

EOF

printf 'Proceed? [y/N] '
read -r reply
case "$reply" in
  y|Y|yes|YES) ;;
  *) warn "Aborted."; exit 0;;
esac

if docker image inspect "$IMAGE" >/dev/null 2>&1; then
  docker rmi -f "$IMAGE" >/dev/null && ok "Removed image '$IMAGE'."
else
  warn "Image '$IMAGE' not present."
fi

if [ -d "$STATE_ROOT" ]; then
  rm -rf "$STATE_ROOT" && ok "Removed state directory '$STATE_ROOT'."
else
  warn "State directory '$STATE_ROOT' not present."
fi

ok "Done."

cat <<EOF

To also remove the npm package and the 'agent-pod' command, run:

  npm uninstall -g agent-pod-cli

(Use -g. A local, non-global install lives inside another project's
node_modules, and 'npm uninstall agent-pod-cli' there has to rebuild that
project's dependency tree — which fails if the project has unrelated peer
dependency conflicts.)
EOF
