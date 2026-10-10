#!/usr/bin/env bash
# Fetch the pinned SQLite web runtime instead of committing dependency binaries.
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
task_sqlite_file="$repo_dir/apps/mobile/web/sqlite3.wasm"
task_sqlite_sha=13d3f11d05b39ba0618a7115fb41640a5d48b6300f5d3f325f554b42bd6688a4
task_sqlite_url=https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-3.5.2/sqlite3.wasm
if [[ -f "$task_sqlite_file" ]] && [[ "$(shasum -a 256 "$task_sqlite_file" | cut -d ' ' -f 1)" == "$task_sqlite_sha" ]]; then
  exit 0
fi
task_sqlite_download="$(mktemp "$repo_dir/apps/mobile/web/.sqlite3-download.XXXXXX")"
trap 'rm -f "$task_sqlite_download"' EXIT
curl --fail --location --retry 2 --output "$task_sqlite_download" "$task_sqlite_url"
printf '%s  %s\n' "$task_sqlite_sha" "$task_sqlite_download" | shasum -a 256 --check --status
mv "$task_sqlite_download" "$task_sqlite_file"
trap - EXIT
