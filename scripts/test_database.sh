#!/usr/bin/env bash
set -euo pipefail
# An isolated PostgreSQL cluster; never connects to an existing project or database.
TIKDOG_PG_BIN="${TIKDOG_PG_BIN:-/opt/homebrew/opt/postgresql@17/bin}"
TIKDOG_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TIKDOG_TEST_DIR="$(mktemp -d /tmp/tikdog-postgres.XXXXXX)"
TIKDOG_TEST_PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
cleanup() { "$TIKDOG_PG_BIN/pg_ctl" -D "$TIKDOG_TEST_DIR/data" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$TIKDOG_TEST_DIR"; }
trap cleanup EXIT
"$TIKDOG_PG_BIN/initdb" -D "$TIKDOG_TEST_DIR/data" -A trust --no-locale -E UTF8 >/dev/null
"$TIKDOG_PG_BIN/pg_ctl" -D "$TIKDOG_TEST_DIR/data" -l "$TIKDOG_TEST_DIR/server.log" -o "-k $TIKDOG_TEST_DIR -p $TIKDOG_TEST_PORT -h 127.0.0.1" -w start >/dev/null
TIKDOG_PSQL=("$TIKDOG_PG_BIN/psql" -X -v ON_ERROR_STOP=1 -h "$TIKDOG_TEST_DIR" -p "$TIKDOG_TEST_PORT" -d postgres)
"${TIKDOG_PSQL[@]}" -f "$TIKDOG_ROOT/scripts/test_database_fixture.sql" >/dev/null
for migration in "$TIKDOG_ROOT"/supabase/migrations/*.sql; do "${TIKDOG_PSQL[@]}" -f "$migration" >/dev/null; done
"${TIKDOG_PSQL[@]}" -f "$TIKDOG_ROOT/scripts/test_database_assertions.sql"
"${TIKDOG_PSQL[@]}" -f "$TIKDOG_ROOT/scripts/test_release_safety.sql"
