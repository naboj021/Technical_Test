#!/usr/bin/env bash
# Creates the database, loads the fixture and installs the procedures.
# Run once from the repo root, after: docker compose up -d
set -euo pipefail

CONTAINER=testops-sql
PASSWORD='Str0ng!Passw0rd'

SQLCMD=""
for p in /opt/mssql-tools18/bin/sqlcmd /opt/mssql-tools/bin/sqlcmd; do
  if docker exec "$CONTAINER" test -x "$p" 2>/dev/null; then SQLCMD="$p"; break; fi
done
[ -n "$SQLCMD" ] || { echo "sqlcmd not found inside $CONTAINER" >&2; exit 1; }

echo "waiting for sql server..."
for _ in $(seq 1 40); do
  docker exec "$CONTAINER" "$SQLCMD" -S localhost -U sa -P "$PASSWORD" -C -Q "SELECT 1" >/dev/null 2>&1 && break
  sleep 3
done

for f in 01_schema.sql 02_seed.sql 03_procs.sql; do
  echo "applying $f"
  docker exec "$CONTAINER" "$SQLCMD" -S localhost -U sa -P "$PASSWORD" -C -d master -i "/db/$f"
done

echo
echo "sanity check - expect FirstPassYieldPct = 91.88"
docker exec "$CONTAINER" "$SQLCMD" -S localhost -U sa -P "$PASSWORD" -C -d TestOps \
  -Q "EXEC dbo.usp_GetFirstPassYield @FromDate='2026-01-01', @ToDate='2026-01-31';"
