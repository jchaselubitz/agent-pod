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

### 1. Install the npm package

```bash
npm install -g agent-pod-cli
```

When you install from an interactive terminal, the package launches
`agent-pod setup` for you automatically and, at the end of setup, offers to
build the Docker image. If your environment hides the install output (some npm
versions, CI, non-interactive shells) the setup flow is skipped — just run the
two commands below yourself. Set `AGENT_POD_SKIP_SETUP=1` before installing to
always skip the auto-launch.

```bash
agent-pod setup          # create ~/.agent-pod/.agent-pod.env (auto-runs on install)
agent-pod install-image  # build the Docker image with the agent CLIs
```

If `OVERLORD_AGENT_TOKEN` is set in your environment or `~/.agent-pod/.agent-pod.env`,
`agent-pod install-image` also runs `ovld setup all` once for each agent's state
directory after the build. That installs the Overlord connectors and pre-approves
the `ovld protocol` commands the agents run (the permission prompt is auto-accepted
because the setup runs non-interactively), so agents launched via AgentPod can drive
Overlord tickets without stopping for permission prompts.

`agent-pod setup` creates or updates `~/.agent-pod/.agent-pod.env` — a single
config file that lives with the CLI, not in whatever directory you run from —
asks which agent CLIs AgentPod should support, asks whether AgentPod should add
each selected agent's default autonomous flag, prompts for an Overlord agent
token when you use Overlord to manage agents, opens the file in your editor
when possible, and finally offers to build the Docker image now so it's ready
the first time you launch an agent.

> Make sure you install with `-g`. Without it, `npm install agent-pod-cli`
> drops the package into the current project's `node_modules` instead of your
> user-level npm folder, and the `agent-pod` command won't be on your PATH.

### Alternative: clone and build from source

```bash
git clone https://github.com/jchaselubitz/agent-pod
cd agent-pod
./install.sh
```

`install.sh` asks which agents to support when no `AGENT_POD_AGENTS` setting is
already configured, builds the `agent-pod` image with those CLIs, and then
prints the installed version of each selected CLI. A successful build ends with:

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

Add project/tooling packages to the image when your agents need them. The
easiest way is to save them to your config file with `package-add`, so they
persist across rebuilds:

```bash
agent-pod package-add --npm pnpm typescript
agent-pod package-add --apt python3 python3-pip build-essential
agent-pod packages            # list what's configured
agent-pod package-remove --npm typescript
agent-pod install-image       # rebuild to apply
```

`--npm` (the default) installs global npm packages; `--apt` installs Debian
packages with `apt-get`. Both lists are saved in `~/.agent-pod/.agent-pod.env`
as `AGENT_POD_NPM_PACKAGES` / `AGENT_POD_APT_PACKAGES` — edit that file directly
if you prefer. They're baked into the Docker image, so rebuild after changing
them.

You can also set them as one-off environment variables, which override the
saved config for that build:

```bash
AGENT_POD_APT_PACKAGES="python3 build-essential" \
AGENT_POD_NPM_PACKAGES="pnpm typescript" \
./install.sh
```

### Put the source checkout launcher on your PATH

If you installed with npm, this is already done. If you cloned from source, the
`agent-pod` launcher lives in the repo, so alias it to its absolute path
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

You can also install a source checkout globally with npm:

```bash
npm install -g .
```

AgentPod configures local npm installs to copy the package into npm's global
prefix, so the installed command does not depend on the checkout remaining in
place.

### Verify

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

Manage supported agents later with:

```bash
agent-pod agents
agent-pod agent-add cursor overlord
agent-pod agent-remove opencode
agent-pod install-image      # rebuild after changing supported agents
```

Manage custom packages baked into the image the same way:

```bash
agent-pod packages
agent-pod package-add --npm pnpm typescript
agent-pod package-add --apt python3 build-essential
agent-pod package-remove --npm typescript
agent-pod install-image      # rebuild after changing packages
```

Anything after the agent name is forwarded straight to the CLI:

```bash
agent-pod claude -p "explain the build setup"
agent-pod codex exec "run the tests and fix failures"
```

### Pod lifecycle and pruning

Each `agent-pod <agent>` run creates one Docker container for that session.
When the agent process exits, Docker removes the container automatically because
the launcher uses `docker run --rm`. New containers are labeled as AgentPod
containers so they can be cleaned up safely if Docker ever leaves a stopped
container behind after an interrupted or abnormal shutdown.

AgentPod intentionally does not prune per-agent state. Auth, history, local CLI
self-updates, and tool config live under `~/.agent-pod/<agent>/` and persist
across runs until you remove them or run `agent-pod uninstall`.

To remove stopped AgentPod containers manually:

```bash
agent-pod prune       # stopped AgentPod containers older than 24 hours
agent-pod prune 0     # all stopped AgentPod containers
agent-pod prune 168   # stopped AgentPod containers older than 7 days
```

Launches also try this stopped-container prune automatically once every 24
hours. Disable or tune that behavior with `AGENT_POD_AUTO_PRUNE`,
`AGENT_POD_PRUNE_INTERVAL_HOURS`, and `AGENT_POD_PRUNE_UNTIL_HOURS`.

### Authentication

Two options, both persist across runs in `~/.agent-pod/<agent>/`:

1. **Interactive login** — run the agent once and complete its normal login
   flow. The credentials are saved in the per-agent state directory.
2. **Provider keys** — export a key in your shell and it is forwarded into the
   container automatically. Recognized variables include:
   `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `CURSOR_API_KEY`, `GEMINI_API_KEY`,
   `OPENROUTER_API_KEY`, `GROQ_API_KEY`, `GITHUB_TOKEN`, and more.

For secrets or API keys you want every pod to receive, put them in the central
config file that `agent-pod setup` manages:

```dotenv
# ~/.agent-pod/.agent-pod.env
OPENAI_API_KEY=sk-...
STRIPE_SECRET_KEY=sk_test_...
```

`agent-pod` resolves the env-file in this order, using the first that exists:

1. `AGENT_POD_ENV_FILE`, if set — an explicit override.
2. `~/.agent-pod/.agent-pod.env` — the central config that lives with the CLI.
3. `.agent-pod.env`, then `agent-pod.env`, in the current project directory —
   legacy project-local files, still honored if present.
4. `.agent-pod.env`, then `agent-pod.env`, next to the launcher — legacy
   source-checkout files.

The central file is the default and what `setup` writes, so the same config
applies no matter which directory you launch from. For a project-specific
override, set `AGENT_POD_ENV_FILE` or keep a `.agent-pod.env` in that project
root. These values are loaded when the container starts, so restart
`agent-pod` after editing the file.

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
| `AGENT_POD_ENV_FILE` | `~/.agent-pod/.agent-pod.env`, then legacy project/launcher files | Docker env-file to load into the container |
| `AGENT_POD_YOLO` | `1` | Set to `0` to drop the auto-approve flags |
| `AGENT_POD_AGENTS` | `claude,codex,opencode,overlord,cursor` | Comma- or space-separated agent CLIs to build and run |
| `AGENT_POD_CLAUDE_AUTO_FLAGS` | `1` | Set to `0` to omit `--dangerously-skip-permissions` |
| `AGENT_POD_CODEX_AUTO_FLAGS` | `1` | Set to `0` to omit `--dangerously-bypass-approvals-and-sandbox` |
| `AGENT_POD_CURSOR_AUTO_FLAGS` | `1` | Set to `0` to omit `--force` |
| `GIT_USER_EMAIL` | _(none)_ | Git `user.email` written into the container's `~/.gitconfig` |
| `GIT_USER_NAME` | _(none)_ | Git `user.name` written into the container's `~/.gitconfig` |
| `AGENT_POD_IMAGE` | `agent-pod` | Image name to build/run |
| `AGENT_POD_HOME` | `~/.agent-pod` | Where per-agent state is stored |
| `AGENT_POD_AUTO_PRUNE` | `1` | Set to `0` to disable periodic stopped-container pruning |
| `AGENT_POD_PRUNE_INTERVAL_HOURS` | `24` | How often launches try automatic pruning; `0` means every launch |
| `AGENT_POD_PRUNE_UNTIL_HOURS` | `24` | Auto-prune stopped AgentPod containers older than this; `0` means all stopped AgentPod containers |
| `AGENT_POD_APT_PACKAGES` | _(none)_ | Extra Debian packages to bake into the image at install time (manage with `agent-pod package-add --apt`) |
| `AGENT_POD_NPM_PACKAGES` | _(none)_ | Extra global npm packages to bake into the image at install time (manage with `agent-pod package-add --npm`) |

`agent-pod setup`, `agent-pod agent-add`/`agent-remove`, and
`agent-pod package-add`/`package-remove` write the supported-agent list,
per-agent autonomous flag choices, and custom package lists into
`~/.agent-pod/.agent-pod.env`. Shell environment values still win over values
from the file.

## How it works

`install.sh` builds a Node-based image that installs the four npm CLIs
(`@anthropic-ai/claude-code`, `@openai/codex`, `opencode-ai`, `overlord-cli`)
and the Cursor Agent via its vendor installer (relocated to a global path).

The `agent-pod` launcher then runs, roughly:

```bash
docker run --rm -i [-t] \
  --label com.agent-pod.managed=true \
  --user "$(id -u):$(id -g)" \
  -e HOME=/home/agent-pod \
  -e NPM_CONFIG_PREFIX=/home/agent-pod/.npm-global \
  [--env-file ~/.agent-pod/.agent-pod.env] \
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

Remove the Docker image and per-user state (`~/.agent-pod`), then remove the
npm package:

```bash
agent-pod uninstall          # removes the image and ~/.agent-pod (prompts first)
npm uninstall -g agent-pod-cli
```

From a source checkout, `./uninstall.sh` does the same as `agent-pod uninstall`.

> **`npm uninstall` fails with `ERESOLVE`?** That happens when the package was
> installed *locally* (without `-g`) into a project, because `npm uninstall`
> then has to rebuild that project's whole dependency tree — which fails if the
> project has any unrelated peer-dependency conflicts. Install and uninstall
> globally with `-g` so npm only touches your user-level npm folder:
>
> ```bash
> npm uninstall -g agent-pod-cli
> ```
>
> If you did install it locally, remove it from that project the same way you
> would any stuck dependency, e.g. `npm uninstall agent-pod-cli --no-save` or
> by deleting the entry from `package.json` and the `node_modules` folder.

## Limitations

- **Network is not sandboxed.** Filesystem isolation only.
- Symlinks/hardlinks pointing outside `$PWD` are not followed in (only `$PWD` is
  mounted), but be mindful of what lives inside your project tree.
- Not native Windows — use WSL2.
- macOS users on the system `/bin/bash` (3.2) should be fine; the scripts avoid
  features that require newer bash.
