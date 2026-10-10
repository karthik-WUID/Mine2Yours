#!/usr/bin/env bash
set -euo pipefail
umask 077
backup_directory="${1:-.local/backups}"
mkdir -p "$backup_directory"
backup_file="$backup_directory/mine2yourlingo-$(date -u +%Y%m%dT%H%M%SZ).dump"
trap 'rm -f "$backup_file.part"' EXIT
docker compose exec -T postgres pg_dump -U mine2yourlingo -d mine2yourlingo -Fc > "$backup_file.part"
mv "$backup_file.part" "$backup_file"
printf 'Created PostgreSQL backup: %s\n' "$backup_file"
