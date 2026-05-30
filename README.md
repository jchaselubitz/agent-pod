# AgentPod

Run AI coding-agent CLIs inside a throwaway Docker container that can only see
your **current project directory** — so you can safely let them run in fully
autonomous ("yolo") mode without exposing your home directory, SSH keys, cloud
credentials, or other projects.

One image, one launcher, five agents:

| Agent | CLI | Default autonomous flags |
|-------|-----|--------------------------|
| **Claude Code** | `claude` | `--dangerously-skip-permissions` |
| **OpenAI Codex** | `codex` | `--dangerously-bypass-approvals-and-sandbox` |
| **OpenCode** | `opencode` | _(uses its own config)_ |
| **Overlord** | `ovld` | _(uses its own config)_ |
| **Cursor Agent** | `cursor-agent` | `--force` |

> Inspired by [`claude-pod`](https://github.com/trekhleb/claude-pod), generalized
> to work across multiple agent CLIs.

## Why

These CLIs are most useful when they can edit files and run commands without
asking for confirmation each time. But "skip all permissions" on your laptop
means the agent can touch *anything* your user can. AgentPod narrows that blast
radius to a single directory:

- Only `$PWD` is mounted into the container, at the same path.
- The agent runs as your host UID/GID, so files it creates are owned by you.
- Linux capabilities are dropped and privilege escalation is disabled.
- Auth and history persist per-agent on the host, so you log in once.

> ⚠️ **Outbound network access is not restricted.** The sandbox limits
> *filesystem* exposure, not what the agent can reach over the network.

## Requirements

- Docker (Desktop on macOS/Windows, Engine on Linux)
- On Windows, use WSL2.

## Setup

### 1. Clone and build the image

```bash
git clone https://github.com/jchaselubitz/agent-pod
cd agent-pod
./install.sh
```

`install.sh` builds the `agent-pod` image with all five CLIs and then prints
the installed version of each. A successful build ends with:

```
Image 'agent-pod' built.
Installed versions:
  claude:      ...
  codex:       ...
  opencode:    ...
  ovld:        ...
  cursor-agent: ...

Done. Next steps:
  ...
```

> Run `install.sh` directly (`./install.sh`) from a normal terminal. If you
> launch it via an IDE "run file" action that appends `; exit`, the window
> closes the instant it finishes — which looks like a crash even though the
> build succeeded. Check with `docker images | grep agent-pod`.

Pin versions if you like:

```bash
CLAUDE_CODE_VERSION=2.0.0 OPENCODE_VERSION=0.3.0 ./install.sh
```

Add project/tooling packages to the image when your agents need them:

```bash
AGENT_POD_APT_PACKAGES="python3 python3-pip build-essential" \
AGENT_POD_NPM_PACKAGES="pnpm typescript" \
./install.sh
```

`AGENT_POD_APT_PACKAGES` installs Debian packages with `apt-get`.
`AGENT_POD_NPM_PACKAGES` installs global npm packages. Both are baked into the
Docker image, so rebuild after changing them.

### 2. Put the launcher on your PATH

The `agent-pod` launcher lives in the repo, so alias it to its absolute path
(replace the path with wherever you cloned the repo):

```bash
# zsh
echo "alias agent-pod=\"$PWD/agent-pod\"" >> ~/.zshrc && source ~/.zshrc

# bash
echo "alias agent-pod=\"$PWD/agent-pod\"" >> ~/.bashrc && source ~/.bashrc
```

Or symlink it into a directory already on your PATH:

```bash
ln -s "$PWD/agent-pod" /usr/local/bin/agent-pod
```

### 3. Verify

```bash
agent-pod shell          # opens a prompt like:  agent-pod:/...$
```

Inside the sandbox, confirm all five CLIs are present, then `exit`:

```bash
claude --version
codex --version
opencode --version
ovld version
cursor-agent --version
```

## Usage

From inside any project directory:

```bash
agent-pod claude            # Claude Code
agent-pod codex             # OpenAI Codex
agent-pod opencode          # OpenCode
agent-pod overlord          # Overlord
agent-pod cursor            # Cursor Agent
agent-pod shell             # a plain shell inside the sandbox
```

Anything after the agent name is forwarded straight to the CLI:

```bash
agent-pod claude -p "explain the build setup"
agent-pod codex exec "run the tests and fix failures"
```

### Authentication

Two options, both persist across runs in `~/.agent-pod/<agent>/`:

1. **Interactive login** — run the agent once and complete its normal login
   flow. The credentials are saved in the per-agent state directory.
2. **Provider keys** — export a key in your shell and it is forwarded into the
   container automatically. Recognized variables include:
   `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `CURSOR_API_KEY`, `GEMINI_API_KEY`,
   `OPENROUTER_API_KEY`, `GROQ_API_KEY`, `GITHUB_TOKEN`, and more.

For secrets or API keys you want every pod to receive, create `.agent-pod.env`
next to the `agent-pod` launcher:

```bash
cd /path/to/agent-pod
cp .agent-pod.env.example .agent-pod.env
```

For project-specific secrets, create `.agent-pod.env` in the project root you
run `agent-pod` from:

```dotenv
OPENAI_API_KEY=sk-...
STRIPE_SECRET_KEY=sk_test_...
```

`agent-pod` first checks the current project for `.agent-pod.env`, then
`agent-pod.env`; if neither exists, it checks the launcher directory for the
same filenames. Project-local files take precedence over the central launcher
file. The dotted name is preferred because it is already ignored by many
editor/project conventions. These values are loaded when the container starts,
so restart `agent-pod` after editing the file.

To use a different file:

```bash
AGENT_POD_ENV_FILE=.env.agent agent-pod codex
```

To verify what a new container sees:

```bash
agent-pod shell env | grep OVERLORD_AGENT_TOKEN
```

To forward extra variables from your current shell without an env-file:

```bash
AWS_PROFILE=dev AGENT_POD_ENV=AWS_PROFILE,MY_API_URL agent-pod claude
```

### Exposing dev-server ports

By default nothing is published. Expose ports with `PORTS`:

```bash
PORTS=3000,8080 agent-pod claude
```

Ports are bound to `127.0.0.1` only. Dev servers inside the container must bind
to `0.0.0.0` (not `localhost`) to be reachable from the host.

### Configuration

| Variable | Default | Purpose |
|----------|---------|---------|
| `PORTS` | _(none)_ | Comma-separated ports to publish on localhost |
| `AGENT_POD_ENV` | _(none)_ | Comma- or space-separated host env var names to forward |
| `AGENT_POD_ENV_FILE` | project `.agent-pod.env`, project `agent-pod.env`, launcher `.agent-pod.env`, launcher `agent-pod.env` | Docker env-file to load into the container |
| `AGENT_POD_YOLO` | `1` | Set to `0` to drop the auto-approve flags |
| `AGENT_POD_IMAGE` | `agent-pod` | Image name to build/run |
| `AGENT_POD_HOME` | `~/.agent-pod` | Where per-agent state is stored |
| `AGENT_POD_APT_PACKAGES` | _(none)_ | Extra Debian packages to bake into the image at install time |
| `AGENT_POD_NPM_PACKAGES` | _(none)_ | Extra global npm packages to bake into the image at install time |

## How it works

`install.sh` builds a Node-based image that installs the four npm CLIs
(`@anthropic-ai/claude-code`, `@openai/codex`, `opencode-ai`, `overlord-cli`)
and the Cursor Agent via its vendor installer (relocated to a global path).

The `agent-pod` launcher then runs, roughly:

```bash
docker run --rm -i [-t] \
  --user "$(id -u):$(id -g)" \
  -e HOME=/home/agent-pod \
  -e NPM_CONFIG_PREFIX=/home/agent-pod/.npm-global \
  [--env-file .agent-pod.env] \
  -v ~/.agent-pod/<agent>:/home/agent-pod \   # persisted auth + history
  -v "$PWD:$PWD" -w "$PWD" \                   # only the current project
  --cap-drop ALL --security-opt no-new-privileges \
  agent-pod  <cli> <autonomous-flags> [your args]
```

Each agent gets its own `HOME` (`~/.agent-pod/<agent>`), so whatever paths a
given CLI uses for config/auth/history (`~/.claude*`, `~/.codex`,
`~/.config/opencode`, `~/.cursor`, ...) all persist uniformly.

Runtime npm global installs use `~/.agent-pod/<agent>/.npm-global`, which keeps
agent self-updates writable for the non-root container user and persistent
across runs.

## Uninstall

```bash
./uninstall.sh   # removes the image and ~/.agent-pod (prompts first)
```

## Limitations

- **Network is not sandboxed.** Filesystem isolation only.
- Symlinks/hardlinks pointing outside `$PWD` are not followed in (only `$PWD` is
  mounted), but be mindful of what lives inside your project tree.
- Not native Windows — use WSL2.
- macOS users on the system `/bin/bash` (3.2) should be fine; the scripts avoid
  features that require newer bash.
