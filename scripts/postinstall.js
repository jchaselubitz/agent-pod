#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const { spawn, spawnSync } = require("child_process");

const nextSteps = `
agent-pod installed.

Next steps:
  agent-pod setup           Create and edit ~/.agent-pod/agent-pod.env
  agent-pod install-image   Build the Docker image with the agent CLIs

Run agent-pod --help for usage.
`;

function printNextSteps() {
  console.log(nextSteps.trim());
}

// Auto-launch the setup flow right after install so a fresh user is guided
// straight into configuring AgentPod (and, at the end of setup, offered the
// chance to build the Docker image). Installs in CI, Docker builds, or any
// non-interactive pipeline fall back to printing the manual next steps so
// nothing is created or prompted behind the user's back.
function skipForEnv() {
  if (process.env.AGENT_POD_SKIP_SETUP) return true;
  if (process.env.CI) return true;
  return false;
}

// npm pipes a lifecycle script's stdio (stdout/stderr are captured), so the
// inherited process.std{in,out} are almost never TTYs during `npm install -g`
// — which is why keying off process.stdin.isTTY meant setup effectively never
// auto-launched. The process still keeps its *controlling terminal*, though,
// so we can open /dev/tty directly and run setup against that. We open it
// read/write once and reuse the same fd for stdin/stdout/stderr so prompts
// render and read keystrokes even when npm has redirected the standard fds.
//
// Returns an open fd for /dev/tty, or null when there is no controlling
// terminal (CI, Docker build, piped install) or the platform has no /dev/tty
// (Windows). Callers must close the fd.
function openControllingTty() {
  try {
    return fs.openSync("/dev/tty", "r+");
  } catch {
    return null;
  }
}

function truthyEnv(value) {
  return /^(1|true|yes)$/i.test(value || "");
}

// When npm is not running scripts in the foreground, its progress renderer can
// repeatedly clear the terminal line while setup is asking questions on
// /dev/tty. Defer the interactive setup until that renderer is gone.
function shouldDeferSetupUntilAfterNpm() {
  return Boolean(process.env.npm_lifecycle_event) && !truthyEnv(process.env.npm_config_foreground_scripts);
}

function findNpmAncestorPid() {
  let pid = process.ppid;
  for (let i = 0; i < 5 && pid > 1; i += 1) {
    const result = spawnSync("ps", ["-o", "ppid=", "-o", "command=", "-p", String(pid)], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    });
    const line = (result.stdout || "").trim();
    if (!line) return null;

    const match = line.match(/^(\d+)\s+(.+)$/);
    if (!match) return null;

    const parentPid = Number(match[1]);
    const command = match[2];
    if (/(^|[ /])npm([ /]|$)|npm-cli\.js/.test(command)) return pid;
    pid = parentPid;
  }
  return null;
}

function runSetup(stdio) {
  const launcher = path.resolve(__dirname, "..", "agent-pod");
  const result = spawnSync(launcher, ["setup"], { stdio });
  // If we couldn't actually run the launcher (missing bash, perms, etc.),
  // fall back to the manual instructions instead of failing the install.
  if (result.error || result.status !== 0) {
    if (result.error) {
      console.error(`Could not launch 'agent-pod setup' automatically: ${result.error.message}`);
    }
    printNextSteps();
  }
}

function runSetupAfterNpm(ttyFd) {
  const launcher = path.resolve(__dirname, "..", "agent-pod");
  const npmPid = findNpmAncestorPid();
  const waitScript = `
npm_pid="$1"
launcher="$2"
if [ "$npm_pid" != "0" ]; then
  while kill -0 "$npm_pid" 2>/dev/null; do
    sleep 0.1
  done
else
  sleep 1
fi
sleep 0.2
printf '\\n' >&2
exec "$launcher" setup
`;

  try {
    const child = spawn("sh", ["-c", waitScript, "agent-pod-deferred-setup", String(npmPid || 0), launcher], {
      detached: true,
      stdio: [ttyFd, ttyFd, ttyFd],
    });
    child.unref();
  } catch (error) {
    console.error(`Could not launch 'agent-pod setup' automatically: ${error.message}`);
    printNextSteps();
  }
}

function main() {
  if (skipForEnv()) {
    printNextSteps();
    return;
  }

  const ttyFd = openControllingTty();
  if (ttyFd !== null) {
    try {
      if (shouldDeferSetupUntilAfterNpm()) {
        runSetupAfterNpm(ttyFd);
      } else {
        runSetup([ttyFd, ttyFd, ttyFd]);
      }
    } finally {
      try {
        fs.closeSync(ttyFd);
      } catch {
        /* ignore */
      }
    }
    return;
  }

  // No controlling terminal to open. As a last resort, honor an inherited tty
  // (e.g. `npm i -g --foreground-scripts` on npm versions that pass it
  // through); otherwise just print the manual next steps.
  if (process.stdin.isTTY && process.stdout.isTTY) {
    runSetup("inherit");
  } else {
    printNextSteps();
  }
}

main();
