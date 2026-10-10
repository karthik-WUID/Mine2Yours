#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
source "$repo_dir/scripts/runtime.sh"
package_path="${1:?Package path is required}"
script_name="${2:?Package script is required}"
case "$package_path" in
  services/api|apps/admin-web) ;;
  *) echo 'Unknown Mine2YourLingo package.' >&2; exit 1 ;;
esac
shift 2
exec npm --prefix "$repo_dir/$package_path" run "$script_name" -- "$@"
