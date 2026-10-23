#!/bin/bash
# Runs the Storely cloud schema + all migrations + SQL tests against a local
# Postgres container. Usage: supabase/tests/run.sh [container-name]
set -euo pipefail
CONTAINER=${1:-storely-pg}
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
psql() { docker exec -i "$CONTAINER" psql -U postgres -q -v ON_ERROR_STOP=1 "$@"; }

psql -c "drop database if exists storely_test" >/dev/null
psql -c "create database storely_test" >/dev/null
db() { psql -d storely_test "$@"; }

db < "$HERE/auth_stub.sql"
db < "$ROOT/storely_cloud_schema.sql"
for migration in "$ROOT"/migrations/*.sql; do
  db < "$migration"
done
# Re-running everything must be safe (idempotent schema + migrations).
db < "$ROOT/storely_cloud_schema.sql"
for migration in "$ROOT"/migrations/*.sql; do
  db < "$migration"
done
db -c "grant usage on schema public to authenticated, anon;
       grant all on all tables in schema public to authenticated;
       grant all on all sequences in schema public to authenticated;"

status=0
for test in "$HERE"/*_test.sql; do
  if db -At < "$test" >/dev/null; then
    echo "PASS $(basename "$test")"
  else
    echo "FAIL $(basename "$test")"; status=1
  fi
done
exit $status
