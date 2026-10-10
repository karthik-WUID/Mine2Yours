#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
source "$repo_dir/scripts/runtime.sh"
cd "$repo_dir/apps/admin-web"
export DEV_API_URL="${DEV_API_URL:-http://127.0.0.1:3100}"
exec npm run dev
