---
name: configure-agent-pod
description: >-
  Configure the AgentPod sandbox for a project: add a custom coding agent or
  harness, bake apt/npm packages into the sandbox image, or give the pod access
  to other Docker containers (for example a local Supabase stack so migrations
  can be applied). Use whenever the user asks to set up, extend, or change how
  agent-pod runs — e.g. "add gemini to agent-pod", "the sandbox is missing
  python", "let the pod reach my supabase database", "apply migrations from the
  pod".
---

# Configuring AgentPod

AgentPod runs coding-agent CLIs inside a throwaway Docker sandbox scoped to the
current project. Users can ask you to extend that sandbox. The authoritative,
always-current instructions live in the CLI itself — **do not guess flags**, read
them first:

```bash
agent-pod protocol help
```

`agent-pod protocol` is the machine-readable control surface. Each topic prints
the exact commands, the env-file keys they write, and the rebuild/verify step:

| You're asked to…                                   | Run                              |
|----------------------------------------------------|----------------------------------|
| Add a custom agent / harness CLI                   | `agent-pod protocol agents`      |
| Make sure a tool/library is in the sandbox image   | `agent-pod protocol packages`    |
| Let the pod reach other containers (e.g. Supabase) | `agent-pod protocol docker`      |
| Find or install these skills                       | `agent-pod protocol skills`      |

## Workflow

1. Run `agent-pod protocol <topic>` for the relevant area and follow it exactly.
2. Apply the change with the `agent-pod` subcommands it lists (these write to
   `~/.agent-pod/.agent-pod.env`).
3. **Rebuild the image** when the change affects what's installed:
   `agent-pod install-image` (first build / config changes) or
   `agent-pod update-image` (refresh CLIs & packages without resetting auth).
4. Verify, e.g. `agent-pod agents`, `agent-pod packages`,
   `agent-pod docker-access status`, or `agent-pod shell <command>`.

## Important constraints

- `agent-pod` runs on the **host** (it drives the host Docker daemon and writes
  the host config file). Run these commands where `agent-pod` is on `PATH`, not
  from inside an already-running pod.
- Config and package changes only take effect in **new** pods, and image changes
  require a rebuild — a pod that's already running keeps the image it started
  with.
- Giving the pod Docker socket access is privileged: a process with the socket
  can control the host daemon. Only enable it when the task needs it.

When in doubt, `agent-pod protocol help` is the source of truth.
