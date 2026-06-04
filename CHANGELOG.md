# Changelog

All notable changes to this project are documented in this file.

## [1.16.0] - 2026-06-04:16:38

### Added

- Install the Overlord plugin inside the pod at launch. Before starting Claude or Codex, the launcher now runs the idempotent `ovld setup <agent>` in-container as the agent's own user/HOME, so `overlord:*` skills resolve in a fresh session instead of failing with "Unknown skill". Runs only when `ovld` is present on the pod PATH.

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
