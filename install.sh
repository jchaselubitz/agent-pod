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
CONFIG_ENV_FILE="${AGENT_POD_ENV_FILE:-${AGENT_POD_HOME:-$HOME/.agent-pod}/.agent-pod.env}"

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

upsert_env_var() {
  file="$1"
  key="$2"
  value="$3"
  tmp="${file}.tmp.$$"
  mkdir -p "$(dirname "$file")" 2>/dev/null || true
  if [ -f "$file" ] && grep -Eq "^[[:space:]]*(export[[:space:]]+)?${key}=" "$file"; then
    awk -v key="$key" -v value="$value" '
      BEGIN { done=0 }
      $0 ~ "^[[:space:]]*(export[[:space:]]+)?" key "=" {
        if (!done) {
          print key "=" value
          done=1
        }
        next
      }
      { print }
    ' "$file" > "$tmp"
  else
    [ -f "$file" ] && cp "$file" "$tmp" || : > "$tmp"
    printf '%s=%s\n' "$key" "$value" >> "$tmp"
  fi
  mv "$tmp" "$file"
  chmod 600 "$file" 2>/dev/null || true
}

available_agents() {
  printf '%s\n' "claude codex opencode overlord cursor"
}

normalize_agents() {
  local raw normalized agent
  raw="$*"
  [ -n "$raw" ] || return 1
  normalized=""
  for agent in $(printf '%s\n' "$raw" | tr '[:upper:],;' '[:lower:]  '); do
    case "$agent" in
      all) printf '%s\n' "$(available_agents)"; return 0;;
      claude|codex|opencode|overlord|cursor) ;;
      *) return 1;;
    esac
    case " $normalized " in
      *" $agent "*) ;;
      *) normalized="${normalized:+$normalized }$agent";;
    esac
  done
  [ -n "$normalized" ] || return 1
  printf '%s\n' "$normalized"
}

agent_in_list() {
  local needle agent
  needle="$1"; shift
  for agent in "$@"; do
    [ "$agent" = "$needle" ] && return 0
  done
  return 1
}

agents_csv() {
  printf '%s\n' "$*" | tr ' ' ','
}

prompt_yes_no() {
  prompt="$1"
  default="$2"
  [ -t 0 ] || { [ "$default" = "yes" ]; return; }
  if [ "$default" = "yes" ]; then suffix="[Y/n]"; else suffix="[y/N]"; fi
  while true; do
    printf '%s %s ' "$prompt" "$suffix"
    read -r reply
    case "$reply" in
      "") [ "$default" = "yes" ] && return 0 || return 1;;
      y|Y|yes|YES) return 0;;
      n|N|no|NO) return 1;;
      *) warn "Please answer yes or no.";;
    esac
  done
}

prompt_agent_selection() {
  [ -t 0 ] || { available_agents; return 0; }
  if prompt_yes_no "Build support for all available agents? ($(available_agents))" "yes"; then
    available_agents
    return 0
  fi
  while true; do
    printf 'Agents to support (space/comma separated: %s): ' "$(available_agents)"
    read -r reply
    if normalized="$(normalize_agents "$reply" 2>/dev/null)"; then
      printf '%s\n' "$normalized"
      return 0
    fi
    warn "Choose one or more agents from: $(available_agents)"
  done
}

resolve_agents() {
  if [ -n "${AGENT_POD_AGENTS:-}" ]; then
    normalize_agents "$AGENT_POD_AGENTS" || die "Invalid AGENT_POD_AGENTS. Choose from: $(available_agents)"
    return 0
  fi
  if agents="$(dotenv_get AGENT_POD_AGENTS "$CONFIG_ENV_FILE" 2>/dev/null)"; then
    normalize_agents "$agents" || die "Invalid AGENT_POD_AGENTS in $CONFIG_ENV_FILE. Choose from: $(available_agents)"
    return 0
  fi
  agents="$(prompt_agent_selection)"
  upsert_env_var "$CONFIG_ENV_FILE" AGENT_POD_AGENTS "$(agents_csv "$agents")"
  printf '%s\n' "$agents"
}

# Resolve the Overlord agent token the same way the launcher resolves config:
# an explicit environment variable wins, otherwise fall back to the central
# config file (~/.agent-pod/.agent-pod.env, or AGENT_POD_ENV_FILE if set).
resolve_overlord_token() {
  if [ -n "${OVERLORD_AGENT_TOKEN:-}" ]; then
    printf '%s\n' "$OVERLORD_AGENT_TOKEN"; return 0
  fi
  cfg="${AGENT_POD_ENV_FILE:-${AGENT_POD_HOME:-$HOME/.agent-pod}/.agent-pod.env}"
  dotenv_get OVERLORD_AGENT_TOKEN "$cfg" 2>/dev/null
}

# Fall back to the saved config file (managed by `agent-pod package-add`) when
# the custom package lists aren't provided via the environment. This is the
# "config file" path: edit ~/.agent-pod/.agent-pod.env (or use `package-add`)
# once and every rebuild picks the packages up — no need to re-export them.
[ -n "$EXTRA_APT_PACKAGES" ] || EXTRA_APT_PACKAGES="$(dotenv_get AGENT_POD_APT_PACKAGES "$CONFIG_ENV_FILE" 2>/dev/null || true)"
[ -n "$EXTRA_NPM_PACKAGES" ] || EXTRA_NPM_PACKAGES="$(dotenv_get AGENT_POD_NPM_PACKAGES "$CONFIG_ENV_FILE" 2>/dev/null || true)"

BUILD_ARGS=(
  --build-arg "CLAUDE_CODE_VERSION=$CLAUDE_CODE_VERSION"
  --build-arg "CODEX_VERSION=$CODEX_VERSION"
  --build-arg "OPENCODE_VERSION=$OPENCODE_VERSION"
  --build-arg "OVERLORD_VERSION=$OVERLORD_VERSION"
  --build-arg "EXTRA_APT_PACKAGES=$EXTRA_APT_PACKAGES"
  --build-arg "EXTRA_NPM_PACKAGES=$EXTRA_NPM_PACKAGES"
)

ENABLED_AGENTS="$(resolve_agents)"
INSTALL_CLAUDE=0; INSTALL_CODEX=0; INSTALL_OPENCODE=0; INSTALL_OVERLORD=0; INSTALL_CURSOR=0
agent_in_list claude $ENABLED_AGENTS && INSTALL_CLAUDE=1
agent_in_list codex $ENABLED_AGENTS && INSTALL_CODEX=1
agent_in_list opencode $ENABLED_AGENTS && INSTALL_OPENCODE=1
agent_in_list overlord $ENABLED_AGENTS && INSTALL_OVERLORD=1
agent_in_list cursor $ENABLED_AGENTS && INSTALL_CURSOR=1
BUILD_ARGS+=(
  --build-arg "INSTALL_CLAUDE=$INSTALL_CLAUDE"
  --build-arg "INSTALL_CODEX=$INSTALL_CODEX"
  --build-arg "INSTALL_OPENCODE=$INSTALL_OPENCODE"
  --build-arg "INSTALL_OVERLORD=$INSTALL_OVERLORD"
  --build-arg "INSTALL_CURSOR=$INSTALL_CURSOR"
)

# Force a fresh npm fetch whenever any CLI tracks "latest".
case "$CLAUDE_CODE_VERSION$CODEX_VERSION$OPENCODE_VERSION$OVERLORD_VERSION" in
  *latest*) BUILD_ARGS+=(--build-arg "CACHEBUST=$(date +%s)");;
esac

info "Building image '$IMAGE'..."
info "  agents:      $ENABLED_AGENTS"
[ "$INSTALL_CLAUDE" = "1" ] && info "  claude-code: $CLAUDE_CODE_VERSION"
[ "$INSTALL_CODEX" = "1" ] && info "  codex:       $CODEX_VERSION"
[ "$INSTALL_OPENCODE" = "1" ] && info "  opencode:    $OPENCODE_VERSION"
[ "$INSTALL_OVERLORD" = "1" ] && info "  overlord:    $OVERLORD_VERSION"
[ "$INSTALL_CURSOR" = "1" ] && info "  cursor:      latest (vendor installer)"
[ -n "$EXTRA_APT_PACKAGES" ] && info "  extra apt:   $EXTRA_APT_PACKAGES"
[ -n "$EXTRA_NPM_PACKAGES" ] && info "  extra npm:   $EXTRA_NPM_PACKAGES"

docker build "${BUILD_ARGS[@]}" -t "$IMAGE" "$DIR" \
  || die "Build failed."

ok "Image '$IMAGE' built."

# Best-effort version report (non-fatal; some CLIs may probe the network or
# block, so each probe is bounded by a timeout and never aborts the script).
info "Installed versions:"
PROBES=()
[ "$INSTALL_CLAUDE" = "1" ] && PROBES+=("claude --version")
[ "$INSTALL_CODEX" = "1" ] && PROBES+=("codex --version")
[ "$INSTALL_OPENCODE" = "1" ] && PROBES+=("opencode --version")
[ "$INSTALL_OVERLORD" = "1" ] && PROBES+=("ovld version")
[ "$INSTALL_CURSOR" = "1" ] && PROBES+=("cursor-agent --version")
for probe in "${PROBES[@]}"; do
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
  if [ "$INSTALL_OVERLORD" != "1" ]; then
    warn "Overlord token detected, but Overlord support is disabled. Skipping connector setup."
    return 0
  fi

  state_root="${AGENT_POD_HOME:-$HOME/.agent-pod}"
  ov_env=(-e "OVERLORD_AGENT_TOKEN=$token")
  [ -n "${OVERLORD_URL:-}" ] && ov_env+=(-e "OVERLORD_URL=$OVERLORD_URL")

  info ""
  info "Overlord token detected — running 'ovld setup all' for each agent..."
  for agent in claude codex opencode cursor; do
    agent_in_list "$agent" $ENABLED_AGENTS || continue
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
