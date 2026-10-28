#!/usr/bin/env bash
set -euo pipefail

if docker compose version >/dev/null 2>&1; then
  compose=(docker compose)
else
  compose=(docker-compose)
fi
# Share database, extension and image settings with development, using isolated
# CI containers and volumes. Only port publishing and restart policy differ.
compose+=(--project-name guileful-charger-ci -f .devcontainer/compose.yaml -f .github/ci/postgres.compose.yml)
trap '
  if (( $? != 0 )); then
    "${compose[@]}" logs --tail 200 postgres >&2 || true
    "${compose[@]}" down --volumes --remove-orphans >/dev/null 2>&1 || true
  fi
' EXIT
"${compose[@]}" down --volumes --remove-orphans

"${compose[@]}" up -d --build --no-deps postgres

for attempt in {1..60}; do
  if pg_isready -h localhost -U postgres; then exit 0; fi
  echo "Waiting for PostgreSQL ($attempt/60)"
  sleep 1
done
exit 1
