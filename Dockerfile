# AgentPod — a single image that ships the four supported agent CLIs.
#
# We deliberately do NOT bake in a user with `USER`. The launcher passes
# `--user "$(id -u):$(id -g)"` at runtime so files created inside the container
# are owned by the host user (important on Linux). A globally-writable home is
# created below for that dynamic, nameless user.
FROM node:24-slim

# Versions can be pinned at build time, e.g.
#   --build-arg CLAUDE_CODE_VERSION=2.0.0
# The default "latest" tracks whatever is current on npm. install.sh passes a
# CACHEBUST value when any version is "latest" so the npm layer is refetched.
ARG CLAUDE_CODE_VERSION=latest
ARG CODEX_VERSION=latest
ARG OPENCODE_VERSION=latest

# Baseline dev tooling. git/curl/less are table stakes; jq + gh are reached for
# by the agents' built-in workflows (JSON pipelines, GitHub PRs/issues).
# ripgrep + unzip are needed by some of the agent installers/runtimes.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      git ca-certificates curl less jq gh ripgrep unzip \
 && rm -rf /var/lib/apt/lists/*

# Cache-bust hook: install.sh sets this to $(date +%s) when a "latest" version
# is requested, forcing npm to refetch instead of reusing a stale layer.
ARG CACHEBUST=1

# Node-based CLIs: Claude Code, OpenAI Codex, OpenCode.
# Installed in separate layers so a single failing package is easy to spot in
# the build log (and doesn't invalidate the others' cache). --no-audit/--no-fund
# keep output focused on real errors.
RUN npm install -g --no-audit --no-fund "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}"
RUN npm install -g --no-audit --no-fund "@openai/codex@${CODEX_VERSION}"
RUN npm install -g --no-audit --no-fund "opencode-ai@${OPENCODE_VERSION}"
RUN npm cache clean --force

# Cursor Agent ships its own installer/runtime rather than an npm package.
# Install it as root, relocate the runtime to /opt, and expose a global symlink
# so it works for the dynamic runtime user (whose HOME is bind-mounted).
RUN curl https://cursor.com/install -fsS | bash \
 && mv /root/.local/share/cursor-agent /opt/cursor-agent \
 && ln -sf "$(find /opt/cursor-agent -type f -name cursor-agent | head -n1)" \
      /usr/local/bin/cursor-agent \
 && chmod -R a+rX /opt/cursor-agent \
 && rm -rf /root/.local /root/.cursor

# Home for the dynamic, nameless runtime user. The launcher bind-mounts a
# per-agent host directory over this path to persist auth/history.
RUN mkdir -p /home/agent-pod && chmod 777 /home/agent-pod

# Friendlier prompt for the nameless user (avoids "I have no name!").
RUN printf 'PS1="agent-pod:\\w\\$ "\n' >> /etc/bash.bashrc

WORKDIR /home/agent-pod
CMD ["bash"]
