#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
source "$repo_dir/scripts/runtime.sh"
cd "$repo_dir/apps/mobile"
flutter pub get
bash "$repo_dir/scripts/prepare-mobile-web.sh"
dart compile js -O4 web/drift_worker.dart -o web/drift_worker.dart.js
exec flutter build web --release --dart-define="API_URL=${API_URL:-http://127.0.0.1:3100/v1}"
