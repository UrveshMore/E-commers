#!/usr/bin/env bash
# name: scripts/create_zips.sh
# Purpose: Create dist/backend.zip, dist/frontend.zip and dist/db_dump.zip (SQL dump)
# Usage: ./scripts/create_zips.sh
# Notes:
# - Ensure this script is run from repo root.
# - Requires: zip, docker (optional), mysqldump (optional)
# - Do NOT commit .env files; they are excluded from zips.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

DIST_DIR="${REPO_ROOT}/dist"
BACKEND_DIR="${REPO_ROOT}/backend"
FRONTEND_DIR="${REPO_ROOT}/frontend"
TMP_DIR="${REPO_ROOT}/tmp_zip"
DB_DUMP_SQL="${DIST_DIR}/db_dump.sql"
DB_DUMP_ZIP="${DIST_DIR}/db_dump.zip"
BACKEND_ZIP="${DIST_DIR}/backend.zip"
FRONTEND_ZIP="${DIST_DIR}/frontend.zip"

# Clean and create directories
rm -rf "$DIST_DIR" "$TMP_DIR"
mkdir -p "$DIST_DIR" "$TMP_DIR"

echo "Preparing zips in $DIST_DIR ..."

# Read DB config from backend/.env if present
DB_HOST=""
DB_PORT="3306"
DB_NAME=""
DB_USER=""
DB_PASS=""

ENV_FILE="${BACKEND_DIR}/.env"
if [ -f "$ENV_FILE" ]; then
  echo "Reading DB config from $ENV_FILE"
  # load simple KEY=VALUE lines (no eval of arbitrary code)
  while IFS='=' read -r key value; do
    case "$key" in
      DB_HOST) DB_HOST="${value//\"/}" ;;
      DB_PORT) DB_PORT="${value//\"/}" ;;
      DB_NAME) DB_NAME="${value//\"/}" ;;
      DB_USER) DB_USER="${value//\"/}" ;;
      DB_PASS) DB_PASS="${value//\"/}" ;;
      MYSQL_DATABASE) [ -z "$DB_NAME" ] && DB_NAME="${value//\"/}" ;;
      MYSQL_USER) [ -z "$DB_USER" ] && DB_USER="${value//\"/}" ;;
      MYSQL_PASSWORD) [ -z "$DB_PASS" ] && DB_PASS="${value//\"/}" ;;
    esac
  done < <(grep -E '^(DB_HOST|DB_PORT|DB_NAME|DB_USER|DB_PASS|MYSQL_DATABASE|MYSQL_USER|MYSQL_PASSWORD)=' "$ENV_FILE" || true)
fi

# Fallback defaults (matching typical docker-compose dev)
DB_HOST=${DB_HOST:-db}
DB_PORT=${DB_PORT:-3306}
DB_NAME=${DB_NAME:-ecomm_db}
DB_USER=${DB_USER:-root}
DB_PASS=${DB_PASS:-rootpassword}

echo "DB host: $DB_HOST, DB name: $DB_NAME, DB user: $DB_USER"

# Create DB dump:
# Strategy:
# 1) If docker container named ecomm-db is running, try docker exec mysqldump using env inside container
# 2) Else, if mysqldump binary is available locally, use it with credentials from .env
# 3) Else, skip DB dump and warn.

DB_CONTAINER_NAME="ecomm-db"
DB_DUMP_OCCURRED=false

if docker ps --format '{{.Names}}' | grep -q "^${DB_CONTAINER_NAME}$"; then
  echo "Detected running Docker container '${DB_CONTAINER_NAME}'. Attempting docker exec mysqldump..."
  # We assume container has MYSQL_DATABASE, MYSQL_USER, MYSQL_PASSWORD env variables (typical in our compose)
  # Run mysqldump inside container and stream output to host file
  if docker exec "$DB_CONTAINER_NAME" sh -c 'command -v mysqldump >/dev/null 2>&1'; then
    echo "Running mysqldump in container..."
    docker exec "$DB_CONTAINER_NAME" sh -c "mysqldump -u\"\${MYSQL_USER}\" -p\"\${MYSQL_PASSWORD}\" \"\${MYSQL_DATABASE}\" --single-transaction --quick --lock-tables=false" > "$DB_DUMP_SQL"
    DB_DUMP_OCCURRED=true
  else
    echo "mysqldump not found in container '${DB_CONTAINER_NAME}'."
  fi
fi

if [ "$DB_DUMP_OCCURRED" = false ] && command -v mysqldump >/dev/null 2>&1; then
  echo "Using local mysqldump..."
  # Use DB_HOST, DB_PORT, DB_USER, DB_PASS, DB_NAME
  # If DB_HOST is 'db' (Docker), local mysqldump won't access it
  mysqldump -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" --single-transaction --quick --lock-tables=false > "$DB_DUMP_SQL" || {
    echo "mysqldump failed. If your DB is running in Docker, ensure it's accessible or start ecomm-db container."
    rm -f "$DB_DUMP_SQL"
  }
  if [ -f "$DB_DUMP_SQL" ]; then DB_DUMP_OCCURRED=true; fi
fi

if [ "$DB_DUMP_OCCURRED" = false ]; then
  echo "WARNING: Could not create DB dump (no docker container or local mysqldump). Skipping DB dump."
else
  echo "DB dump created at $DB_DUMP_SQL"
  # Zip the SQL file
  (cd "$DIST_DIR" && zip -q -r "$(basename "$DB_DUMP_ZIP")" "$(basename "$DB_DUMP_SQL")")
  echo "DB dump zipped to $DB_DUMP_ZIP"
fi

# Create backend zip (exclude node_modules, storage, .env, .log)
echo "Zipping backend directory..."
cd "$REPO_ROOT"
zip -q -r "$BACKEND_ZIP" backend -x \
  "backend/node_modules/*" \
  "backend/.env" \
  "backend/*.env" \
  "backend/storage/*" \
  "backend/*.log" \
  "backend/.DS_Store" \
  "__MACOSX/*"

echo "Backend zip created at $BACKEND_ZIP"

# Create frontend zip (exclude node_modules, dist, .env)
echo "Zipping frontend directory..."
zip -q -r "$FRONTEND_ZIP" frontend -x \
  "frontend/node_modules/*" \
  "frontend/dist/*" \
  "frontend/.env" \
  "frontend/*.env" \
  "frontend/*.log" \
  "frontend/.DS_Store" \
  "__MACOSX/*"

echo "Frontend zip created at $FRONTEND_ZIP"

# Final stats
echo "Done. Zips available in $DIST_DIR:"
ls -lh "$DIST_DIR" || true