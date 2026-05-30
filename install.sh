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

# Read a KEY=VALUE entry out of an env-file, ignoring comments/blank lines and
# stripping an optional `export ` prefix and surrounding quotes. Mirrors the
# launcher's dotenv parser so both agree on what "the user has in the env".
dotenv_get() {
  key="$1"; file="$2"
  [ -n "$file" ] && [ -f "$file" ] || return 1
  awk -v key="$key" '
    /^[[:space:]]*(#|$)/ { next }
    {
      line=$0
      sub(/^[[:space:]]*export[[:space:]]+/, "", line)
      split(line, parts, "=")
      k=parts[1]
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", k)
      if (k == key) {
        sub(/^[^=]*=/, "", line)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
        if (line ~ /^".*"$/ || line ~ /^'\''.*'\''$/) {
          line=substr(line, 2, length(line)-2)
        }
        print line
        found=1
      }
    }
    END { exit found ? 0 : 1 }
  ' "$file"
}

# Resolve the Overlord agent token the same way the launcher resolves config:
# an explicit environment variable wins, otherwise fall back to the central
# config file (~/.agent-pod/agent-pod.env, or AGENT_POD_ENV_FILE if set).
resolve_overlord_token() {
  if [ -n "${OVERLORD_AGENT_TOKEN:-}" ]; then
    printf '%s\n' "$OVERLORD_AGENT_TOKEN"; return 0
  fi
  cfg="${AGENT_POD_ENV_FILE:-${AGENT_POD_HOME:-$HOME/.agent-pod}/agent-pod.env}"
  dotenv_get OVERLORD_AGENT_TOKEN "$cfg" 2>/dev/null
}

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

# ---------------------------------------------------------------------------
# Overlord connector setup (only when an Overlord token is configured).
#
# `ovld setup all` writes its connectors and protocol permissions under the
# agent's HOME (~/.codex, ~/.config/opencode, ~/.cursor, ~/.claude/plugins) and,
# for Claude, into the project's ./.claude/settings.local.json. The launcher
# bind-mounts a *per-agent* state directory (~/.agent-pod/<agent>) over the
# container's HOME at runtime, so anything written to HOME during `docker build`
# is hidden behind that mount. We therefore run setup once per state directory,
# inside a container from the freshly-built image, so the connectors land in the
# host directories the launcher actually mounts back in.
#
# It runs with stdin redirected from /dev/null (no TTY), which makes ovld's
# permission prompt fall through to its default "yes" — so the protocol
# commands each agent runs are pre-approved with no manual interaction and no
# change to the Overlord CLI itself.
setup_overlord_connectors() {
  token="$(resolve_overlord_token || true)"
  [ -n "$token" ] || return 0

  state_root="${AGENT_POD_HOME:-$HOME/.agent-pod}"
  ov_env=(-e "OVERLORD_AGENT_TOKEN=$token")
  [ -n "${OVERLORD_URL:-}" ] && ov_env+=(-e "OVERLORD_URL=$OVERLORD_URL")

  info ""
  info "Overlord token detected — running 'ovld setup all' for each agent..."
  for agent in claude codex opencode cursor; do
    state_dir="$state_root/$agent"
    mkdir -p "$state_dir/.npm-global"
    chmod 700 "$state_root" "$state_dir" 2>/dev/null || true
    info "  • $agent ($state_dir)"
    if docker run --rm \
        --user "$(id -u):$(id -g)" \
        -e HOME=/home/agent-pod \
        -e NPM_CONFIG_PREFIX=/home/agent-pod/.npm-global \
        "${ov_env[@]}" \
        -v "$state_dir:/home/agent-pod" \
        -w /home/agent-pod \
        "$IMAGE" \
        ovld setup all </dev/null >/dev/null 2>&1; then
      ok "    connectors + permissions configured"
    else
      warn "    'ovld setup all' failed for '$agent' — run it later with: agent-pod $agent (then 'ovld setup all')"
    fi
  done
}

setup_overlord_connectors

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
