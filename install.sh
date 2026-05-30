#!/usr/bin/env bash
#
# install.sh — build the AgentPod Docker image.
#
# Version pins (optional), override via env before running:
#   CLAUDE_CODE_VERSION=2.0.0 ./install.sh
#   CODEX_VERSION=...          OPENCODE_VERSION=...
#   OVERLORD_VERSION=...
set -eo pipefail

IMAGE="${AGENT_POD_IMAGE:-agent-pod}"
DIR="$(cd "$(dirname "$0")" && pwd)"

CLAUDE_CODE_VERSION="${CLAUDE_CODE_VERSION:-latest}"
CODEX_VERSION="${CODEX_VERSION:-latest}"
OPENCODE_VERSION="${OPENCODE_VERSION:-latest}"
OVERLORD_VERSION="${OVERLORD_VERSION:-latest}"
EXTRA_APT_PACKAGES="${AGENT_POD_APT_PACKAGES:-${EXTRA_APT_PACKAGES:-}}"
EXTRA_NPM_PACKAGES="${AGENT_POD_NPM_PACKAGES:-${EXTRA_NPM_PACKAGES:-}}"

if [ -t 1 ]; then
  C_INFO=$'\033[34m'; C_OK=$'\033[32m'; C_ERR=$'\033[31m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
  C_INFO=""; C_OK=""; C_ERR=""; C_DIM=""; C_OFF=""
fi
info() { printf '%s%s%s\n' "$C_INFO" "$*" "$C_OFF"; }
ok()   { printf '%s%s%s\n' "$C_OK"   "$*" "$C_OFF"; }
warn() { printf '%s%s%s\n' "$C_DIM"  "$*" "$C_OFF"; }
die()  { printf '%s%s%s\n' "$C_ERR"  "$*" "$C_OFF" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || die "Docker is not installed or not on PATH."
docker info >/dev/null 2>&1       || die "Docker daemon is not running. Start Docker and retry."

BUILD_ARGS=(
  --build-arg "CLAUDE_CODE_VERSION=$CLAUDE_CODE_VERSION"
  --build-arg "CODEX_VERSION=$CODEX_VERSION"
  --build-arg "OPENCODE_VERSION=$OPENCODE_VERSION"
  --build-arg "OVERLORD_VERSION=$OVERLORD_VERSION"
  --build-arg "EXTRA_APT_PACKAGES=$EXTRA_APT_PACKAGES"
  --build-arg "EXTRA_NPM_PACKAGES=$EXTRA_NPM_PACKAGES"
)

# Force a fresh npm fetch whenever any CLI tracks "latest".
case "$CLAUDE_CODE_VERSION$CODEX_VERSION$OPENCODE_VERSION$OVERLORD_VERSION" in
  *latest*) BUILD_ARGS+=(--build-arg "CACHEBUST=$(date +%s)");;
esac

info "Building image '$IMAGE'..."
info "  claude-code: $CLAUDE_CODE_VERSION"
info "  codex:       $CODEX_VERSION"
info "  opencode:    $OPENCODE_VERSION"
info "  overlord:    $OVERLORD_VERSION"
info "  cursor:      latest (vendor installer)"
[ -n "$EXTRA_APT_PACKAGES" ] && info "  extra apt:   $EXTRA_APT_PACKAGES"
[ -n "$EXTRA_NPM_PACKAGES" ] && info "  extra npm:   $EXTRA_NPM_PACKAGES"

docker build "${BUILD_ARGS[@]}" -t "$IMAGE" "$DIR" \
  || die "Build failed."

ok "Image '$IMAGE' built."

# Best-effort version report (non-fatal; some CLIs may probe the network or
# block, so each probe is bounded by a timeout and never aborts the script).
info "Installed versions:"
for probe in "claude --version" "codex --version" "opencode --version" "ovld version" "cursor-agent --version"; do
  out="$(docker run --rm "$IMAGE" sh -lc "timeout 10 $probe </dev/null" 2>/dev/null || true)"
  printf '  %-12s %s\n' "${probe%% *}:" "${out:-"(unavailable)"}"
done

cat <<EOF

$(ok "Done.") Next steps:

  # Put the launcher on your PATH (or alias it):
  alias agent-pod='$DIR/agent-pod'

  # Then, from any project directory:
  agent-pod claude          # Claude Code
  agent-pod codex           # OpenAI Codex
  agent-pod opencode        # OpenCode
  agent-pod overlord        # Overlord
  agent-pod cursor          # Cursor Agent
  agent-pod shell           # a plain shell in the sandbox
EOF
