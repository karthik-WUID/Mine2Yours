#!/usr/bin/env bash
# Sourced by task scripts. Never changes global installations or settings.
task_node_dir="$HOME/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin"
if ! command -v node >/dev/null || [[ "$(node -p 'Number(process.versions.node.split(".")[0])')" -lt 22 ]]; then
  if [[ -x "$task_node_dir/node" ]]; then export PATH="$task_node_dir:$PATH"; fi
fi
if ! command -v node >/dev/null || [[ "$(node -p 'Number(process.versions.node.split(".")[0])')" -lt 22 ]]; then
  echo 'Node.js 22 or newer is required.' >&2
  exit 1
fi
if ! command -v flutter >/dev/null && [[ -x "$HOME/development/flutter/bin/flutter" ]]; then
  export PATH="$HOME/development/flutter/bin:$PATH"
fi
