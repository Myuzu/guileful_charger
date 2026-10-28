#!/usr/bin/env bash
set -euo pipefail

container=guileful-charger-ci-postgres
trap '
  if (( $? != 0 )); then
    docker logs --tail 200 "$container" >&2 || true
    docker rm -f -v "$container" >/dev/null 2>&1 || true
  fi
' EXIT
docker rm -f -v "$container" >/dev/null 2>&1 || true

docker build -f .devcontainer/postgres/Dockerfile -t guileful-postgres .
docker run -d \
  --name "$container" \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=guileful_charger_development \
  -p 5432:5432 \
  guileful-postgres \
  postgres \
    -c shared_preload_libraries=pg_cron \
    -c cron.database_name=guileful_charger_development

for attempt in {1..60}; do
  if pg_isready -h localhost -U postgres; then exit 0; fi
  echo "Waiting for PostgreSQL ($attempt/60)"
  sleep 1
done
exit 1
