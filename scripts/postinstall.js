#!/usr/bin/env node

const message = `
agent-pod installed.

Next steps:
  agent-pod install-image   Build the Docker image with the agent CLIs
  agent-pod setup           Create and edit .agent-pod.env for your project

Run agent-pod --help for usage.
`;

console.log(message.trim());
