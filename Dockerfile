# AgentPod — a single image that ships the selected supported agent CLIs.
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
ARG OVERLORD_VERSION=latest
ARG EXTRA_APT_PACKAGES=""
ARG EXTRA_NPM_PACKAGES=""
ARG INSTALL_CLAUDE=1
ARG INSTALL_CODEX=1
ARG INSTALL_OPENCODE=1
ARG INSTALL_OVERLORD=1
ARG INSTALL_CURSOR=1

# Refresh hook for apt/system packages. `agent-pod update-image` changes this
# value so Docker re-runs the apt layer instead of reusing stale package lists.
ARG APT_CACHEBUST=1
# Static Docker CLI release (not in Debian apt as docker-cli).
ARG DOCKER_CLI_VERSION=27.5.1

# Baseline dev tooling. git/curl/less are table stakes; jq + gh are reached for
# by the agents' built-in workflows (JSON pipelines, GitHub PRs/issues).
# ripgrep + unzip are needed by some of the agent installers/runtimes.
# Docker CLI (static binary) lets opt-in host socket access talk to the host
# daemon without running Docker inside this container.
# EXTRA_APT_PACKAGES lets teams bake in project-specific system dependencies,
# for example: "python3 python3-pip build-essential".
RUN echo "$APT_CACHEBUST" >/dev/null \
 && apt-get update \
 && apt-get upgrade -y \
 && apt-get install -y --no-install-recommends \
      git ca-certificates curl less jq gh ripgrep unzip \
      $EXTRA_APT_PACKAGES \
 && ARCH="$(dpkg --print-architecture)" \
 && case "$ARCH" in \
      amd64) DOCKER_ARCH=x86_64 ;; \
      arm64) DOCKER_ARCH=aarch64 ;; \
      *) echo "Unsupported architecture for Docker CLI: $ARCH" >&2; exit 1 ;; \
    esac \
 && curl -fsSL "https://download.docker.com/linux/static/stable/${DOCKER_ARCH}/docker-${DOCKER_CLI_VERSION}.tgz" \
    | tar xz -C /usr/local/bin --strip-components=1 docker/docker \
 && rm -rf /var/lib/apt/lists/*

# Cache-bust hook: install.sh sets this to $(date +%s) when a "latest" version
# is requested, forcing npm to refetch instead of reusing a stale layer.
ARG CACHEBUST=1

# Node-based CLIs: Claude Code, OpenAI Codex, OpenCode, and optional Overlord
# manager package.
# Installed in separate layers so a single failing package is easy to spot in
# the build log (and doesn't invalidate the others' cache). --no-audit/--no-fund
# keep output focused on real errors.
RUN echo "$CACHEBUST" >/dev/null; \
    if [ "$INSTALL_CLAUDE" = "1" ]; then \
      npm install -g --no-audit --no-fund "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}"; \
    fi
RUN echo "$CACHEBUST" >/dev/null; \
    if [ "$INSTALL_CODEX" = "1" ]; then \
      npm install -g --no-audit --no-fund "@openai/codex@${CODEX_VERSION}"; \
    fi
RUN echo "$CACHEBUST" >/dev/null; \
    if [ "$INSTALL_OPENCODE" = "1" ]; then \
      npm install -g --no-audit --no-fund "opencode-ai@${OPENCODE_VERSION}"; \
    fi
RUN echo "$CACHEBUST" >/dev/null; \
    if [ "$INSTALL_OVERLORD" = "1" ]; then \
      npm install -g --no-audit --no-fund "overlord-cli@${OVERLORD_VERSION}"; \
    fi
RUN echo "$CACHEBUST" >/dev/null; \
    if [ -n "$EXTRA_NPM_PACKAGES" ]; then \
      npm install -g --no-audit --no-fund $EXTRA_NPM_PACKAGES; \
    fi
RUN npm cache clean --force

# Cursor Agent ships its own installer/runtime rather than an npm package.
# Install it as root, relocate the runtime to /opt, and expose global symlinks
# so it works for the dynamic runtime user (whose HOME is bind-mounted).
# The user-facing CLI is `agent`; `cursor-agent` is kept as a backward-compat alias.
RUN echo "$CACHEBUST" >/dev/null; \
    if [ "$INSTALL_CURSOR" = "1" ]; then \
      curl https://cursor.com/install -fsS | bash \
      && mv /root/.local/share/cursor-agent /opt/cursor-agent \
      && _bin="$(find /opt/cursor-agent -type f \( -name agent -o -name cursor-agent \) | head -n1)" \
      && [ -n "$_bin" ] || _bin="$(find /opt/cursor-agent -maxdepth 3 -type f -perm /111 | head -n1)" \
      && ln -sf "$_bin" /usr/local/bin/agent \
      && ln -sf /usr/local/bin/agent /usr/local/bin/cursor-agent \
      && chmod -R a+rX /opt/cursor-agent \
      && rm -rf /root/.local /root/.cursor; \
    fi

# Home for the dynamic, nameless runtime user. The launcher bind-mounts a
# per-agent host directory over this path to persist auth/history.
RUN mkdir -p /home/agent-pod && chmod 777 /home/agent-pod

# Runtime npm global installs, including CLI auto-updates, must target the
# mounted HOME instead of root-owned /usr/local.
ENV NPM_CONFIG_PREFIX=/home/agent-pod/.npm-global
ENV PATH="${NPM_CONFIG_PREFIX}/bin:${PATH}"

# Friendlier prompt for the nameless user (avoids "I have no name!").
RUN printf 'PS1="agent-pod:\\w\\$ "\n' >> /etc/bash.bashrc

WORKDIR /home/agent-pod
CMD ["bash"]
