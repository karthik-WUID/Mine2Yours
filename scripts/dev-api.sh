#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
source "$repo_dir/scripts/runtime.sh"
cd "$repo_dir/services/api"
export NODE_ENV=development ENABLE_DEV_AUTH=true
export PORT="${PORT:-3100}"
exec npm run dev
