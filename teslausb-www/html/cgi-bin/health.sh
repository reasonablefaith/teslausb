#!/bin/bash -eu
#
# health.sh — Health/status endpoint for TeslaUSB
#
# Returns JSON with:
#   - archiveloop running status
#   - last archive log entry (timestamp)
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
#
# Install: copy to /var/www/html/TeslaCam/cgi-bin/health.sh and make executable
# Access: http://teslausb.local/TeslaCam/cgi-bin/health.sh

echo "Content-type: application/json"
echo ""

# Helper: safely read a value or return null
json_val() {
  if [ -n "${1:-}" ]; then
    echo "\"$1\""
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

# Last archive log entry timestamp
last_archive_time=null
if [ -f /mutable/archiveloop.log ]
then
  last_line=$(tail -1 /mutable/archiveloop.log 2>/dev/null || true)
  if [ -n "$last_line" ]
  then
    # Extract the date prefix from the log line
    last_archive_time=$(echo "$last_line" | sed 's/: .*//' | sed 's/^[[:space:]]*//')
    last_archive_time=$(json_val "$last_archive_time")
  fi
fi

# Cam disk free space (in bytes)
cam_free_bytes=null
cam_total_bytes=null
if [ -f /backingfiles/cam_disk.bin ]
then
  cam_free_bytes=$(stat --file-system --format="%f*%S" /backingfiles/cam_disk.bin 2>/dev/null | bc 2>/dev/null || echo null)
  cam_total_bytes=$(stat --file-system --format="%b*%S" /backingfiles/cam_disk.bin 2>/dev/null | bc 2>/dev/null || echo null)
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
  wifi_state=$(cat /sys/class/net/wlan0/operstate 2>/dev/null || echo "unknown")
  wifi_status="$wifi_state"
fi

# Temperature (milli-degrees C, if available)
temp_mc=null
if [ -f /sys/class/thermal/thermal_zone0/temp ]
then
  temp_mc=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo null)
fi

# Output JSON
cat <<EOF
{
  "hostname": "$(hostname)",
  "uptime_seconds": $uptime_secs,
  "archiveloop_running": $archiveloop_running,
  "last_archive_time": $last_archive_time,
  "cam_disk": {
    "free_bytes": $cam_free_bytes,
    "total_bytes": $cam_total_bytes
  },
  "snapshots": $snapshot_count,
  "wifi": {
    "interface": "wlan0",
    "status": "$(json_val "$wifi_status")"
  },
  "temperature_mc": $temp_mc,
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF