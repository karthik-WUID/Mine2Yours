#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_dir/apps/mobile"
flutter_cmd="${FLUTTER_BIN:-flutter}"
if [[ "$flutter_cmd" == flutter ]] && ! command -v flutter >/dev/null && [[ -x "$HOME/development/flutter/bin/flutter" ]]; then
  flutter_cmd="$HOME/development/flutter/bin/flutter"
fi
# Host-only workaround: no bundled dylib/lipo when Xcode CLT is absent.
# Android and release builds always use the original bundled SQLite hook.
if [[ "$(uname -s)" == Darwin ]] && ! xcrun --show-sdk-path >/dev/null 2>&1; then
  task_backup="$(mktemp)"
  cp pubspec.yaml "$task_backup"
  trap 'cp "$task_backup" pubspec.yaml; rm -f "$task_backup"' EXIT HUP INT TERM
  cat >> pubspec.yaml <<'YAML'

hooks:
  user_defines:
    sqlite3:
      source: system
YAML
  "$flutter_cmd" test "$@"
else
  "$flutter_cmd" test "$@"
fi
