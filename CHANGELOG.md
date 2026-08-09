# Changelog

All notable changes to this project are documented in this file.

## [Unreleased]

### Added

- Shared codex login. Codex's `~/.codex` now lives once in `~/.agent-pod/.shared-auth/` and is mounted into every pod, so a single device-code login applies to codex however it is launched instead of only under the `codex` agent name. An existing login is moved into the shared store on first launch. Opt out with `AGENT_POD_SHARE_CODEX_AUTH=0`.
- `CLAUDE_CODE_OAUTH_TOKEN` is forwarded from the host environment, alongside the other provider credentials. Previously it only reached a pod when written into the config file.
- `AGENT_POD_AGENT_AUTOUPDATE` (default `0`): agent CLIs no longer update themselves inside pods. Versions come from the image — refresh them with `agent-pod update-image`.

### Fixed

- Removed `.npm-global` from the shared cache list. It is npm's install prefix, not a cache: sharing it let concurrent pods race to install an agent CLI's self-update into one directory and swap the binary out from under running sessions.

### Changed

- None.

### Security

- None.

### Documentation

- Document the shared codex login, `AGENT_POD_SHARE_CODEX_AUTH`, and `AGENT_POD_AGENT_AUTOUPDATE` in `.agent-pod.env.example`.

## [1.26.0] - 2026-08-07:09:44

### Added

- Shared package-manager caches. One copy of `.npm`, `.npm-global`, `.cache`, `.yarn`, `.cargo`, `.rustup`, `.bun`, `.deno`, and `.local/share/pnpm` now lives in `~/.agent-pod/.shared-cache/` and is bind-mounted over the same path in every pod's HOME, instead of each agent keeping its own copy. Agent auth, history, and config stay per-agent. Configurable with `AGENT_POD_SHARE_CACHES` and `AGENT_POD_SHARED_CACHES`.
- `agent-pod cache [status|migrate|clean|clear|on|off]` to inspect shared cache sizes, consolidate existing per-agent copies, and reclaim the space they were using.
- `agent-pod protocol cache` topic so agents can diagnose and fix AgentPod disk usage on the user's behalf.
- `AGENT_POD_HOST_CACHES`: opt-in reuse of the host's own caches, for stores whose contents are platform-neutral (e.g. `.npm`, `.yarn`). Off by default because a macOS/Windows host's `.cargo`/`.rustup`/`.cache` hold binaries a linux pod cannot execute.

### Fixed

- None.

### Changed

- The first launch of an agent after upgrading renames that agent's existing cache into the shared store rather than re-downloading it. Copies belonging to other agents are then shadowed by the shared mount and can be deleted with `agent-pod cache clean`.

### Security

- None.

### Documentation

- Document shared caches, `agent-pod cache`, and host-cache reuse in the README and `.agent-pod.env.example`.

## [1.25.0] - 2026-07-20:12:50

### Added

- None.

### Fixed

- Prevent Docker `Duplicate mount point` failures when the launch directory is also listed in `AGENT_POD_ALLOWED_PATHS`, the project allowlist, or `AGENT_POD_EXTRA_ALLOWED_PATHS` by treating `$PWD` as already mounted.
- Trim per-entry whitespace in the CSV allowlist parser so spaced lists like `/a:rw, /b:ro` work the same across all three allowlist sources.

### Changed

- Keep the launch directory mounted read/write even when an allowlist entry asks for `:ro`, so the agent can always write where it runs.

### Security

- None.

### Documentation

- Clarify allowlist entry format (`<absolute-path>[:rw|:ro]`), whitespace tolerance, always-rw launch dir behavior, and the recommendation that services writing `AGENT_POD_EXTRA_ALLOWED_PATHS` include an explicit mode suffix on every entry.

## [1.20.0] - 2026-06-17:00:00

### Added

- Prompt for `OVERLORD_BACKEND_URL` during `agent-pod setup` when using Overlord to manage agents.

### Fixed

- Normalize bare `host:port` Overlord backend URLs (e.g. `host.docker.internal:4310`) to include `http://` before forwarding them into pods.

### Changed

- Configure `ovld` inside the pod at launch from `OVERLORD_BACKEND_URL` and `OVERLORD_USER_TOKEN`, writing persistent config under the agent's bind-mounted HOME.
- Switch from `open-overlord` to the `overlord-cli` npm package for `ovld`.
- Use `ovld agent-setup` instead of `ovld setup` for connector and permission installation.
- Store Overlord credentials as `OVERLORD_BACKEND_URL` and `OVERLORD_USER_TOKEN` (legacy `OVERLORD_URL` / `OVERLORD_AGENT_TOKEN` names are still read as fallbacks).

### Security

- None.

## [1.16.0] - 2026-06-04:16:38

### Added

- Install the Overlord plugin inside the pod at launch. Before starting Claude or Codex, the launcher now runs the idempotent `ovld agent-setup <agent>` in-container as the agent's own user/HOME, so `overlord:*` skills resolve in a fresh session instead of failing with "Unknown skill". Runs only when `ovld` is present on the pod PATH.

### Fixed

- None.

### Changed

- None.

### Security

- None.

## [1.15.0] - 2026-06-04:14:09

### Added

- None.

### Fixed

- Fix Claude Code bus errors on Linux arm64 when Docker starts the agent directly, by launching through bash so argv and behavior match the stable `agent-pod shell` path.

### Changed

- None.

### Security

- None.
