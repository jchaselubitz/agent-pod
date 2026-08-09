#!/usr/bin/env bash
set -eo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PREFIX="$(mktemp -d)"
cleanup() {
  rm -rf "$PREFIX"
}
trap cleanup EXIT

NPM_CONFIG_PREFIX="$PREFIX" npm install -g "$ROOT" --ignore-scripts >/dev/null

GLOBAL_PACKAGE="$PREFIX/lib/node_modules/agent-pod-cli"
BIN="$PREFIX/bin/agent-pod"

[ -d "$GLOBAL_PACKAGE" ] || {
  echo "Expected global package directory to exist: $GLOBAL_PACKAGE" >&2
  exit 1
}

if [ -L "$GLOBAL_PACKAGE" ]; then
  echo "Expected npm install -g to copy agent-pod-cli, but it symlinked to: $(readlink "$GLOBAL_PACKAGE")" >&2
  exit 1
fi

[ -x "$GLOBAL_PACKAGE/agent-pod" ] || {
  echo "Expected launcher to be installed at: $GLOBAL_PACKAGE/agent-pod" >&2
  exit 1
}

[ -f "$GLOBAL_PACKAGE/lib/common.sh" ] || {
  echo "Expected shared runtime library to be installed at: $GLOBAL_PACKAGE/lib/common.sh" >&2
  exit 1
}

[ -L "$BIN" ] || {
  echo "Expected npm to create the global agent-pod bin link: $BIN" >&2
  exit 1
}
