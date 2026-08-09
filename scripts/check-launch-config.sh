#!/usr/bin/env bash
set -eo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

TEST_HOME="$TEST_ROOT/home"
TEST_PROJECT="$TEST_ROOT/project"
FAKE_BIN="$TEST_ROOT/bin"
DOCKER_LOG="$TEST_ROOT/docker.log"
mkdir -p "$TEST_HOME/.agent-pod" "$TEST_PROJECT" "$FAKE_BIN"

cat > "$TEST_HOME/.agent-pod/.agent-pod.env" <<'EOF'
AGENT_POD_AGENTS=claude,codex
AGENT_POD_IMAGE=central-image
AGENT_POD_AUTO_PRUNE=0
AGENT_POD_OVERLORD=0
CLAUDE_CODE_OAUTH_TOKEN=saved-claude-token
EOF

# A project-local file must not be discovered implicitly. It exists only to
# catch a regression to the removed multi-location loading rules.
cat > "$TEST_PROJECT/.agent-pod.env" <<'EOF'
AGENT_POD_IMAGE=project-image-must-not-load
EOF

cat > "$FAKE_BIN/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '--- docker invocation ---' >> "$AGENT_POD_TEST_DOCKER_LOG"
printf '%s\n' "$@" >> "$AGENT_POD_TEST_DOCKER_LOG"
exit 0
EOF
chmod +x "$FAKE_BIN/docker"

run_agent() {
  (
    cd "$TEST_PROJECT"
    env -i \
      HOME="$TEST_HOME" \
      PATH="$FAKE_BIN:$PATH" \
      TERM="${TERM:-xterm-256color}" \
      AGENT_POD_TEST_DOCKER_LOG="$DOCKER_LOG" \
      "$ROOT/agent-pod" "$1" --version >/dev/null
  )
}

run_agent claude
run_agent codex

# The image builder must consume the same central config implementation. Agent
# selection remains overridable per invocation while the saved image name is
# still honored.
env -i \
  HOME="$TEST_HOME" \
  PATH="$FAKE_BIN:$PATH" \
  TERM="${TERM:-xterm-256color}" \
  AGENT_POD_TEST_DOCKER_LOG="$DOCKER_LOG" \
  AGENT_POD_AGENTS=claude \
  AGENT_POD_OVERLORD=0 \
  "$ROOT/install.sh" >/dev/null

CONFIG_FILE="$TEST_HOME/.agent-pod/.agent-pod.env"
SHARED_NPM="$TEST_HOME/.agent-pod/.shared-cache/.npm:/home/agent-pod/.npm"

grep -Fx -- '--env-file' "$DOCKER_LOG" >/dev/null
grep -Fx -- "$CONFIG_FILE" "$DOCKER_LOG" >/dev/null
[ "$(grep -Fxc -- "$SHARED_NPM" "$DOCKER_LOG")" -eq 2 ]
! grep -F -- '.shared-cache/.npm-global' "$DOCKER_LOG" >/dev/null
grep -Fx -- 'central-image' "$DOCKER_LOG" >/dev/null
! grep -F -- 'project-image-must-not-load' "$DOCKER_LOG" >/dev/null
grep -Fx -- 'INSTALL_CLAUDE=1' "$DOCKER_LOG" >/dev/null
grep -Fx -- 'INSTALL_CODEX=0' "$DOCKER_LOG" >/dev/null

for agent in claude codex; do
  ONBOARDING_FILE="$TEST_HOME/.agent-pod/$agent/.claude.json"
  [ -f "$ONBOARDING_FILE" ]
  grep -Eq '"hasCompletedOnboarding"[[:space:]]*:[[:space:]]*true' "$ONBOARDING_FILE"
done

printf '%s\n' 'Launcher config, shared cache, and Claude token checks passed.'
