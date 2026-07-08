# Changelog

All notable changes to this project are documented in this file.

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
