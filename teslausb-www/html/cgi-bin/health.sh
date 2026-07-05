#!/bin/bash -eu
#
# health.sh — Health/status endpoint for TeslaUSB
#
# Returns JSON with:
#   - archiveloop running status
#   - last archive log entry (timestamp)
#   - archiveloop stuck detection (no log activity for > N seconds)
#   - error count from recent archiveloop log
#   - cam disk free space
#   - snapshot count
#   - uptime
#   - wifi status
#   - temperature (if available)
#
# This endpoint is designed to be polled by a workstation monitoring
# system (e.g. a cron-based watchdog) to detect:
#   - archiveloop stuck in wait_for_archive_unreachable (the LAN bug)
#   - disk full conditions
#   - wifi failures
#   - stale snapshots (no recent archive activity)
#   - repeated archive errors (the "Archived 0 files" silent failure)
#
# Install: copy to /var/www/html/TeslaCam/cgi-bin/health.sh and make executable
# Access: http://teslausb.local/TeslaCam/cgi-bin/health.sh

echo "Content-type: application/json"
echo ""

# Helper: safely output a JSON string value
json_str() {
  if [ -n "${1:-}" ]; then
    printf '"%s"' "$1"
  else
    echo "null"
  fi
}

# Helper: output a JSON number (no quotes)
json_num() {
  if [ -n "${1:-}" ] && [ "$1" != "null" ]; then
    echo "$1"
  else
    echo "null"
  fi
}

# Check if archiveloop is running
archiveloop_running=false
if pgrep -x archiveloop > /dev/null 2>&1 || pgrep -f "bash.*archiveloop" > /dev/null 2>&1
then
  archiveloop_running=true
fi

# Last archive log entry timestamp and stuck detection
last_archive_time=null
last_archive_epoch=0
archiveloop_stuck=false
error_count=0
now_epoch=$(date +%s)

if [ -f /mutable/archiveloop.log ]
then
  last_line=$(tail -1 /mutable/archiveloop.log 2>/dev/null || true)
  if [ -n "$last_line" ]
  then
    # Extract the date prefix from the log line (format: "Mon Jan 1 12:00:00 UTC 2026: ...")
    last_archive_time=$(echo "$last_line" | sed 's/: .*//' | sed 's/^[[:space:]]*//')
    # Try to convert to epoch for stuck detection
    parsed_date=$(echo "$last_archive_time" | sed 's/: .*//')
    last_archive_epoch=$(date -d "$parsed_date" +%s 2>/dev/null || echo 0)
  fi

  # Count errors in the last 100 log lines
  error_count=$(tail -100 /mutable/archiveloop.log 2>/dev/null | grep -c -iE 'Error|failed|Archived 0|WARNING' 2>/dev/null || echo 0)

  # Stuck detection: if last log entry is older than 600s (10min),
  # the archiveloop is likely stuck
  if [[ "$last_archive_epoch" -gt 0 && $((now_epoch - last_archive_epoch)) -gt 600 ]]
  then
    archiveloop_stuck=true
  fi
fi

# Cam disk free space (in bytes) — use $((...)) instead of bc
cam_free_bytes=null
cam_total_bytes=null
if [ -f /backingfiles/cam_disk.bin ]
then
  read free_blocks block_size _ < <(stat --file-system --format="%f %S %a" /backingfiles/cam_disk.bin 2>/dev/null || echo "0 0 0")
  if [[ "$block_size" -gt 0 && "$free_blocks" -gt 0 ]]
  then
    cam_free_bytes=$((free_blocks * block_size))
  fi
  read total_blocks _ _ < <(stat --file-system --format="%b %S %a" /backingfiles/cam_disk.bin 2>/dev/null || echo "0 0 0")
  if [[ "$block_size" -gt 0 && "$total_blocks" -gt 0 ]]
  then
    cam_total_bytes=$((total_blocks * block_size))
  fi
fi

# Snapshot count
snapshot_count=0
if [ -d /backingfiles/snapshots ]
then
  snapshot_count=$(find /backingfiles/snapshots -name "snap.bin" 2>/dev/null | wc -l)
fi

# Uptime (seconds)
uptime_secs=$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo 0)

# Wifi status
wifi_status="unknown"
if ip link show wlan0 > /dev/null 2>&1
then
  wifi_status=$(cat /sys/class/net/wlan0/operstate 2>/dev/null || echo "unknown")
fi

# Temperature (milli-degrees C, if available)
temp_mc=null
if [ -f /sys/class/thermal/thermal_zone0/temp ]
then
  temp_mc=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo null)
fi

# Seconds since last archive log entry (for monitoring)
secs_since_last_log=null
if [[ "$last_archive_epoch" -gt 0 ]]
then
  secs_since_last_log=$((now_epoch - last_archive_epoch))
fi

# Output JSON
cat <<EOF
{
  "hostname": "$(hostname)",
  "uptime_seconds": $uptime_secs,
  "archiveloop": {
    "running": $archiveloop_running,
    "stuck": $archiveloop_stuck,
    "secs_since_last_log": $(json_num "$secs_since_last_log"),
    "last_log_time": $(json_str "$last_archive_time"),
    "recent_error_count": $error_count
  },
  "cam_disk": {
    "free_bytes": $(json_num "$cam_free_bytes"),
    "total_bytes": $(json_num "$cam_total_bytes")
  },
  "snapshots": $snapshot_count,
  "wifi": {
    "interface": "wlan0",
    "status": $(json_str "$wifi_status")
  },
  "temperature_mc": $(json_num "$temp_mc"),
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF