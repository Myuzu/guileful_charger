#!/usr/bin/env bash
set -euo pipefail

if docker compose version >/dev/null 2>&1; then
  compose=(docker compose)
else
  if ! compose_version=$(docker-compose version --short 2>/dev/null) ||
    [[ ! $compose_version =~ ^v?([0-9]+)\. ]] || (( BASH_REMATCH[1] < 2 )); then
    echo 'Docker Compose 2 or later is required (docker compose or standalone docker-compose).' >&2
    exit 1
  fi
  compose=(docker-compose)
fi
# Load only the shared database model: unrelated application/broker settings
# cannot invalidate CI startup. The project isolates CI containers and volumes.
compose+=(--project-name guileful-charger-ci -f .devcontainer/postgres/compose.yaml -f .github/ci/postgres.compose.yml)
trap '
  if (( $? != 0 )); then
    "${compose[@]}" logs --tail 200 postgres >&2 || true
    "${compose[@]}" down --volumes --remove-orphans >/dev/null 2>&1 || true
  fi
' EXIT

# Retire the exact container name used before the Compose migration, which is
# outside the CI project and can still hold port 5432. Named volumes are kept.
if docker container inspect guileful-charger-ci-postgres >/dev/null 2>&1; then
  docker container rm --force --volumes guileful-charger-ci-postgres
fi
"${compose[@]}" down --volumes --remove-orphans

"${compose[@]}" up -d --build --no-deps postgres

for attempt in {1..60}; do
  if pg_isready -h localhost -U postgres; then exit 0; fi
  echo "Waiting for PostgreSQL ($attempt/60)"
  sleep 1
done
exit 1
