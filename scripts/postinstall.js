#!/usr/bin/env node

const path = require("path");
const { spawnSync } = require("child_process");

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
// chance to build the Docker image). We only do this when we have a real
// terminal to talk to — installs in CI, Docker builds, or any non-interactive
// pipeline fall back to printing the manual next steps so nothing is created
// or prompted behind the user's back.
function shouldRunSetup() {
  if (process.env.AGENT_POD_SKIP_SETUP) return false;
  if (process.env.CI) return false;
  // setup needs stdin to prompt and stdout to render. npm normally pipes
  // lifecycle-script output, so this is only true when the user installed with
  // output attached to the terminal (e.g. `npm i -g agent-pod-cli
  // --foreground-scripts`, or a plain interactive install on npm versions that
  // inherit the tty).
  return Boolean(process.stdin.isTTY && process.stdout.isTTY);
}

function runSetup() {
  const launcher = path.resolve(__dirname, "..", "agent-pod");
  const result = spawnSync(launcher, ["setup"], { stdio: "inherit" });
  // If we couldn't actually run the launcher (missing bash, perms, etc.),
  // fall back to the manual instructions instead of failing the install.
  if (result.error || result.status !== 0) {
    if (result.error) {
      console.error(`Could not launch 'agent-pod setup' automatically: ${result.error.message}`);
    }
    printNextSteps();
  }
}

if (shouldRunSetup()) {
  runSetup();
} else {
  printNextSteps();
}
