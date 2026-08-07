#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
#  SKY — backup
#
#  Risk #4. Sky Prime's minimum is five layers, and only one of them is
#  "run a backup":
#
#    1. LOCAL VERSIONED   → restic repo on a second local disk
#    2. ENCRYPTED OFFSITE → restic repo on B2/S3 (encrypted before it leaves)
#    3. INFRA FROM GIT    → this repo IS layer 3. Compose + init SQL + ops.
#    4. SECRETS SEPARATE  → .env is EXCLUDED here on purpose. See below.
#    5. RESTORE TESTED    → restore.sh. Run it monthly or layers 1-4 are fiction.
#
#  Why secrets are excluded:
#  If the data backup contained the keys that decrypt the data backup, the
#  encryption is decorative. Secrets get their own encrypted bundle, stored
#  somewhere that is not this machine (password manager / hardware key).
#  ops/backup/secrets-backup.md has the procedure.
# ═══════════════════════════════════════════════════════════════════════
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

[[ -f .env ]] || { echo "FATAL: .env not found in $REPO_ROOT" >&2; exit 1; }
set -a; source .env; set +a

: "${RESTIC_PASSWORD:?RESTIC_PASSWORD is unset — refusing to write an unencrypted backup}"
: "${RESTIC_REPOSITORY_LOCAL:?RESTIC_REPOSITORY_LOCAL is unset}"

STAGE="$(mktemp -d /tmp/sky-backup.XXXXXX)"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
trap 'rm -rf "$STAGE"' EXIT

log() { printf '%s  %s\n' "$(date -u +%H:%M:%S)" "$*"; }

command -v restic >/dev/null || { echo "FATAL: restic not installed (apt install restic)" >&2; exit 1; }

# ─── 1. Dump Postgres ──────────────────────────────────────────────────
log "dumping postgres..."
docker compose exec -T postgres \
  pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom --compress=6 \
  > "$STAGE/sky-${STAMP}.dump"

SIZE=$(du -h "$STAGE/sky-${STAMP}.dump" | cut -f1)
log "dump complete: $SIZE"

# Refuse to back up a suspiciously tiny dump — a 0-byte "success" that
# quietly replaces good snapshots is how backups fail silently.
MIN_BYTES=1024
ACTUAL=$(stat -c%s "$STAGE/sky-${STAMP}.dump")
(( ACTUAL >= MIN_BYTES )) || { echo "FATAL: dump is ${ACTUAL}B — aborting" >&2; exit 1; }

# ─── 2. Stage Tier 2 knowledge files, if present ───────────────────────
if [[ -d /srv/sky/files ]]; then
  log "staging knowledge files..."
  cp -a /srv/sky/files "$STAGE/files"
fi

# Snapshot the reproducible-infra manifest (layer 3 provenance)
{
  echo "commit=$(git rev-parse HEAD 2>/dev/null || echo 'not-a-git-checkout')"
  echo "branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
  echo "dirty=$(git status --porcelain 2>/dev/null | wc -l)"
  echo "stamp=$STAMP"
} > "$STAGE/MANIFEST"

# ─── 3. Local versioned repo ───────────────────────────────────────────
mkdir -p "$RESTIC_REPOSITORY_LOCAL"
export RESTIC_PASSWORD
if ! restic -r "$RESTIC_REPOSITORY_LOCAL" cat config >/dev/null 2>&1; then
  log "initializing local restic repo..."
  restic -r "$RESTIC_REPOSITORY_LOCAL" init
fi

log "backing up → local..."
restic -r "$RESTIC_REPOSITORY_LOCAL" backup "$STAGE" \
  --tag sky --tag "$STAMP" --host sky-node

log "pruning local..."
restic -r "$RESTIC_REPOSITORY_LOCAL" forget \
  --keep-daily   "${BACKUP_KEEP_DAILY:-7}" \
  --keep-weekly  "${BACKUP_KEEP_WEEKLY:-4}" \
  --keep-monthly "${BACKUP_KEEP_MONTHLY:-6}" \
  --prune

# ─── 4. Encrypted offsite ──────────────────────────────────────────────
if [[ -n "${RESTIC_REPOSITORY_REMOTE:-}" ]]; then
  export B2_ACCOUNT_ID B2_ACCOUNT_KEY
  if ! restic -r "$RESTIC_REPOSITORY_REMOTE" cat config >/dev/null 2>&1; then
    log "initializing remote restic repo..."
    restic -r "$RESTIC_REPOSITORY_REMOTE" init
  fi
  log "copying → offsite..."
  restic -r "$RESTIC_REPOSITORY_REMOTE" copy \
    --from-repo "$RESTIC_REPOSITORY_LOCAL" \
    --from-password-file <(printf '%s' "$RESTIC_PASSWORD") 2>/dev/null \
    || restic -r "$RESTIC_REPOSITORY_REMOTE" backup "$STAGE" --tag sky --host sky-node
  restic -r "$RESTIC_REPOSITORY_REMOTE" forget \
    --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune
else
  log "WARNING: RESTIC_REPOSITORY_REMOTE unset — layer 2 (offsite) is NOT active."
  log "         A single-location backup does not survive theft or fire."
fi

log "done. Snapshots:"
restic -r "$RESTIC_REPOSITORY_LOCAL" snapshots --latest 3 --compact
echo
log "Reminder: a backup you have never restored is a theory. Run: make restore-test"
