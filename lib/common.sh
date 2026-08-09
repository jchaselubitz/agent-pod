#!/usr/bin/env bash
# Shared configuration and agent-model helpers for the launcher and image builder.
# Callers own command dispatch and side effects; this file only defines reusable
# parsing, validation, and env-file mutation primitives.

dotenv_get() {
  local key="$1"
  local file="${2:-}"
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

# Resolve one setting consistently everywhere: the process environment wins,
# then the active env-file, then the caller's default.
config_value() {
  local key="$1"
  local default_value="${2:-}"
  local file="${3:-${ENV_FILE:-}}"
  local value
  if [ -n "${!key+x}" ]; then
    printf '%s\n' "${!key}"
  elif value="$(dotenv_get "$key" "$file" 2>/dev/null)"; then
    printf '%s\n' "$value"
  else
    printf '%s\n' "$default_value"
  fi
}

upsert_env_var() {
  local file="$1"
  local key="$2"
  local value="$3"
  local tmp="${file}.tmp.$$"
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

truthy() {
  case "$1" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0;;
    *) return 1;;
  esac
}

normalize_overlord_backend_url() {
  local url="${1:-}"
  [ -z "$url" ] && return 0
  case "$url" in
    http://*|https://*) printf '%s\n' "$url";;
    *) printf 'http://%s\n' "$url";;
  esac
}

# Shell fragment shared by runtime launches and post-build connector setup.
# It configures the selected backend and persists the env-provided user token
# without ever consuming stdin intended for the agent that starts afterward.
overlord_in_pod_bootstrap_fragment() {
  printf '%s' \
    'if command -v ovld >/dev/null 2>&1; then ' \
    'backend_url="${OVERLORD_BACKEND_URL:-}"; ' \
    'user_token="${OVERLORD_USER_TOKEN:-${OVLD_USER_TOKEN:-}}"; ' \
    'if [ -n "$backend_url" ]; then ' \
    'case "$backend_url" in http://*|https://*) ;; *) backend_url="http://${backend_url}";; esac; ' \
    'export OVERLORD_BACKEND_URL="$backend_url"; ' \
    'case "$backend_url" in ' \
    '*://127.0.0.1:*|*://127.0.0.1|*://localhost:*|*://localhost|*://host.docker.internal:*|*://host.docker.internal) ' \
    'ovld config set local "$backend_url" </dev/null >/dev/null 2>&1 || true;; ' \
    '*) ovld config set cloud "$backend_url" </dev/null >/dev/null 2>&1 || true;; esac; ' \
    'if [ -n "$user_token" ]; then ovld auth login --token "$user_token" </dev/null >/dev/null 2>&1 || true; fi; ' \
    'fi; fi; '
}

builtin_agents() {
  printf '%s\n' "claude codex opencode cursor agent"
}

valid_agent_id() {
  case "$1" in
    [a-z][a-z0-9_-]*) return 0;;
    *) return 1;;
  esac
}

is_builtin_agent() {
  case "$1" in
    claude|codex|opencode|cursor|agent) return 0;;
    *) return 1;;
  esac
}

agent_env_key() {
  printf '%s' "$1" | tr '[:lower:]-' '[:upper:]_'
}

normalize_agents() {
  local raw normalized agent
  raw="$*"
  [ -n "$raw" ] || return 1
  normalized=""
  for agent in $(printf '%s\n' "$raw" | tr '[:upper:],;' '[:lower:]  '); do
    case "$agent" in
      all) builtin_agents; return 0;;
      *) valid_agent_id "$agent" || return 1;;
    esac
    case " $normalized " in
      *" $agent "*) ;;
      *) normalized="${normalized:+$normalized }$agent";;
    esac
  done
  [ -n "$normalized" ] || return 1
  printf '%s\n' "$normalized"
}

agents_csv() {
  printf '%s\n' "$*" | tr ' ' ','
}

agent_in_list() {
  local needle="$1"
  local agent
  shift
  for agent in "$@"; do
    [ "$agent" = "$needle" ] && return 0
  done
  return 1
}

valid_package_token() {
  case "$1" in
    ""|-*|*[!A-Za-z0-9@._/+~^=-]*) return 1;;
    *) return 0;;
  esac
}
