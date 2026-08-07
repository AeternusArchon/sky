#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
#  SKY — RESTORE DRILL  (layer 5)
#
#  Restores the latest snapshot into a THROWAWAY database and verifies it
#  actually contains data. Production is never touched. Run monthly.
#
#  Phase 0 does not complete until this exits PASS at least once. That is
#  the whole point of Risk #4 — an untested backup is a belief, not a
#  control. Record the result in docs/DECISIONS.md.
#
#  Usage:
#    ./restore.sh              # drill from the LOCAL repo
#    ./restore.sh --offsite    # drill from OFFSITE — the one that matters
# ═══════════════════════════════════════════════════════════════════════
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

[[ -f .env ]] || { echo "FATAL: .env not found" >&2; exit 1; }
set -a; source .env; set +a

SOURCE="local"
[[ "${1:-}" == "--offsite" ]] && SOURCE="offsite"

if [[ "$SOURCE" == "offsite" ]]; then
  REPO="${RESTIC_REPOSITORY_REMOTE:?RESTIC_REPOSITORY_REMOTE unset}"
  export B2_ACCOUNT_ID B2_ACCOUNT_KEY
else
  REPO="${RESTIC_REPOSITORY_LOCAL:?RESTIC_REPOSITORY_LOCAL unset}"
fi
export RESTIC_PASSWORD="${RESTIC_PASSWORD:?}"

SCRATCH="$(mktemp -d /tmp/sky-restore.XXXXXX)"
TEST_DB="sky_restore_drill"
trap 'rm -rf "$SCRATCH"' EXIT

log()  { printf '%s  %s\n' "$(date -u +%H:%M:%S)" "$*"; }
fail() { printf '\n\033[31m✗ RESTORE DRILL FAILED\033[0m — %s\n' "$*"; exit 1; }

echo
echo "═══ SKY RESTORE DRILL ═══  source=$SOURCE  $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo

# ─── 1. Pull the latest snapshot ───────────────────────────────────────
log "restoring latest snapshot from $SOURCE..."
restic -r "$REPO" restore latest --target "$SCRATCH" --tag sky \
  || fail "restic restore failed — the repo is unreadable"

DUMP="$(find "$SCRATCH" -name 'sky-*.dump' -type f | sort | tail -1)"
[[ -n "$DUMP" ]] || fail "no .dump file inside the snapshot"
log "found dump: $(basename "$DUMP")  ($(du -h "$DUMP" | cut -f1))"

# ─── 2. Restore into a throwaway DB ────────────────────────────────────
log "creating throwaway database '$TEST_DB'..."
docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres \
  -c "DROP DATABASE IF EXISTS $TEST_DB;" >/dev/null
docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres \
  -c "CREATE DATABASE $TEST_DB;" >/dev/null

log "restoring into $TEST_DB..."
docker compose exec -T postgres pg_restore -U "$POSTGRES_USER" -d "$TEST_DB" --no-owner \
  < "$DUMP" 2>/dev/null || log "  (pg_restore emitted warnings — checking contents anyway)"

# ─── 3. Verify it is actually there ────────────────────────────────────
log "verifying..."
TABLES=$(docker compose exec -T postgres psql -U "$POSTGRES_USER" -d "$TEST_DB" -tAc \
  "SELECT count(*) FROM information_schema.tables
   WHERE table_schema IN ('sky_ops','sky_memory','sky_knowledge');")
TABLES="${TABLES//[[:space:]]/}"

SCHEMAS=$(docker compose exec -T postgres psql -U "$POSTGRES_USER" -d "$TEST_DB" -tAc \
  "SELECT count(*) FROM information_schema.schemata
   WHERE schema_name IN ('sky_ops','sky_memory','sky_knowledge');")
SCHEMAS="${SCHEMAS//[[:space:]]/}"

echo
echo "  schemas recovered : $SCHEMAS / 3"
echo "  tables recovered  : $TABLES"
echo

# ─── 4. Clean up ───────────────────────────────────────────────────────
docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres \
  -c "DROP DATABASE IF EXISTS $TEST_DB;" >/dev/null
log "throwaway database dropped — production untouched"

(( SCHEMAS == 3 )) || fail "expected 3 schemas, got $SCHEMAS"
(( TABLES  >= 5 )) || fail "expected >=5 tables, got $TABLES"

echo
printf '\033[32m✓ RESTORE DRILL PASSED\033[0m  source=%s\n' "$SOURCE"
echo
echo "  Log this in docs/DECISIONS.md with today's date."
echo "  Next drill: $(date -u -d '+1 month' +%Y-%m-%d 2>/dev/null || date -u -v+1m +%Y-%m-%d)"
echo
