#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
#  SKY NODE — host health  →  JSON on stdout
#
#  Risk #7. This is a 2013 Mac Pro running containers around the clock in
#  a case designed for burst workloads. Thermals and the blade SSD are the
#  two things that will actually kill it, and both give warning first —
#  but only if something is looking.
#
#  Every probe degrades to null rather than failing. A monitoring script
#  that exits non-zero because lm-sensors is missing is worse than none.
#
#  Cron:  */10 * * * * /srv/sky/ops/health/healthcheck.sh > /srv/sky/.health.json
# ═══════════════════════════════════════════════════════════════════════
set -uo pipefail

json_num() { [[ -n "${1:-}" && "$1" =~ ^-?[0-9]+([.][0-9]+)?$ ]] && printf '%s' "$1" || printf 'null'; }
json_str() { [[ -n "${1:-}" ]] && printf '"%s"' "${1//\"/\\\"}" || printf 'null'; }

# ─── CPU temperature ───────────────────────────────────────────────────
# Needs: apt install lm-sensors && sensors-detect --auto && modprobe coretemp
CPU_TEMP=""
if command -v sensors >/dev/null 2>&1; then
  CPU_TEMP=$(sensors -u 2>/dev/null | awk -F': ' '/temp[0-9]+_input/ {print $2; exit}')
  CPU_TEMP=${CPU_TEMP%%.*}
fi
if [[ -z "$CPU_TEMP" && -r /sys/class/thermal/thermal_zone0/temp ]]; then
  CPU_TEMP=$(( $(cat /sys/class/thermal/thermal_zone0/temp) / 1000 ))
fi

# ─── Load / CPU count ──────────────────────────────────────────────────
LOAD_1M=$(awk '{print $1}' /proc/loadavg 2>/dev/null)
NPROC=$(nproc 2>/dev/null || echo 1)

# ─── Memory ────────────────────────────────────────────────────────────
MEM_PCT=$(free 2>/dev/null | awk '/^Mem:/ {printf "%.2f", ($2-$7)/$2*100}')
MEM_TOTAL_MB=$(free -m 2>/dev/null | awk '/^Mem:/ {print $2}')

# ─── Disk (root + the backup target) ───────────────────────────────────
DISK_PCT=$(df --output=pcent / 2>/dev/null | tail -1 | tr -dc '0-9')
BACKUP_PCT=""
[[ -d /srv/sky-backup ]] && BACKUP_PCT=$(df --output=pcent /srv/sky-backup 2>/dev/null | tail -1 | tr -dc '0-9')

# ─── SMART — the blade SSD is 13 years old ─────────────────────────────
SMART_OK="null"; SMART_DETAIL=""
if command -v smartctl >/dev/null 2>&1; then
  DEV=$(lsblk -ndo NAME,TYPE 2>/dev/null | awk '$2=="disk"{print "/dev/"$1; exit}')
  if [[ -n "$DEV" ]]; then
    OUT=$(sudo -n smartctl -H "$DEV" 2>/dev/null || smartctl -H "$DEV" 2>/dev/null)
    if grep -qiE 'PASSED|OK' <<<"$OUT"; then SMART_OK="true"
    elif grep -qiE 'FAILED' <<<"$OUT"; then SMART_OK="false"; SMART_DETAIL="SMART reports FAILED on $DEV"
    fi
  fi
fi

# ─── Uptime / containers ───────────────────────────────────────────────
UPTIME_S=$(awk '{printf "%d", $1}' /proc/uptime 2>/dev/null)
CONTAINERS=$(docker ps --filter "name=sky-" --format '{{.Names}}:{{.State}}' 2>/dev/null | paste -sd, - || echo "")

# ─── Verdict ───────────────────────────────────────────────────────────
STATUS="ok"; WARNINGS=()
[[ -n "$CPU_TEMP"   && "$CPU_TEMP" -ge 85 ]] && { STATUS="warn"; WARNINGS+=("cpu_temp_${CPU_TEMP}C"); }
[[ -n "$CPU_TEMP"   && "$CPU_TEMP" -ge 95 ]] && { STATUS="critical"; }
[[ -n "$DISK_PCT"   && "$DISK_PCT" -ge 85 ]] && { STATUS="warn"; WARNINGS+=("disk_${DISK_PCT}pct"); }
[[ -n "$DISK_PCT"   && "$DISK_PCT" -ge 95 ]] && { STATUS="critical"; }
[[ "$SMART_OK" == "false" ]] && { STATUS="critical"; WARNINGS+=("smart_failed"); }

WARN_JSON=$(printf '"%s",' "${WARNINGS[@]:-}" | sed 's/,$//'); [[ "$WARN_JSON" == '""' ]] && WARN_JSON=""

cat <<EOF
{
  "status": "$STATUS",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "cpu": { "temp_c": $(json_num "$CPU_TEMP"), "load_1m": $(json_num "$LOAD_1M"), "cores": $(json_num "$NPROC") },
  "memory": { "used_pct": $(json_num "$MEM_PCT"), "total_mb": $(json_num "$MEM_TOTAL_MB") },
  "disk": { "root_used_pct": $(json_num "$DISK_PCT"), "backup_used_pct": $(json_num "$BACKUP_PCT") },
  "smart": { "ok": $SMART_OK, "detail": $(json_str "$SMART_DETAIL") },
  "uptime_seconds": $(json_num "$UPTIME_S"),
  "containers": $(json_str "$CONTAINERS"),
  "warnings": [$WARN_JSON]
}
EOF

[[ "$STATUS" == "critical" ]] && exit 2
[[ "$STATUS" == "warn"     ]] && exit 1
exit 0
