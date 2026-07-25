#!/bin/bash -eu
#
# activate-remaining-fixes.sh — Apply remaining fork features to Pi config
#
# Run this on the WORKSTATION (not the Pi). It SSHes to the Pi and:
#   1. Creates systemd watchdog drop-in (WatchdogSec=600)
#   2. Adds ARCHIVE_REACHABLE_TIMEOUT=300 + LOG_FORMAT=json to config
#   3. Activates archive-filter (copies sample → /root/bin/archive-filter)
#   4. Runs validate-config.sh
#   5. Reloads systemd + restarts teslausb.service
#
# Usage: ./tools/activate-remaining-fixes.sh [pi-ip]
# Default: 192.168.1.14

PI_HOST="${1:-192.168.1.14}"
PI_USER="pi"

echo "Applying remaining fork fixes to $PI_USER@$PI_HOST..."
echo ""

# All commands in a single SSH session to minimize round-trips
ssh -o ConnectTimeout=20 -o ServerAliveInterval=5 "$PI_USER@$PI_HOST" '
set -e

echo "=== 1. Systemd watchdog drop-in ==="
sudo mkdir -p /etc/systemd/system/teslausb.service.d
sudo tee /etc/systemd/system/teslausb.service.d/watchdog.conf > /dev/null << "UNIT"
[Service]
WatchdogSec=600
NotifyAccess=main
UNIT
echo "Created watchdog drop-in"
cat /etc/systemd/system/teslausb.service.d/watchdog.conf

echo ""
echo "=== 2. Config: ARCHIVE_REACHABLE_TIMEOUT + LOG_FORMAT ==="
# Check if already set to avoid duplicates
if ! sudo grep -q "ARCHIVE_REACHABLE_TIMEOUT" /root/teslausb_setup_variables.conf; then
  sudo sed -i "/^export ARCHIVE_UNREACHABLE_TIMEOUT=300/a\\
# LAN mode: stop waiting for reachable after 300s too (mirror of unreachable timeout)\\
export ARCHIVE_REACHABLE_TIMEOUT=300\\
# Structured JSON logging for easier log parsing by watchdog/health monitoring\\
export LOG_FORMAT=json" /root/teslausb_setup_variables.conf
  echo "Added ARCHIVE_REACHABLE_TIMEOUT=300 + LOG_FORMAT=json"
else
  echo "ARCHIVE_REACHABLE_TIMEOUT already set"
fi
sudo grep -E "ARCHIVE_REACHABLE|LOG_FORMAT|ARCHIVE_UNREACHABLE" /root/teslausb_setup_variables.conf

echo ""
echo "=== 3. Activate archive-filter (front-only) ==="
if [ -f /root/bin/archive-filter ]; then
  echo "archive-filter already exists — checking if it is the v3 version"
  if sudo grep -q "archive-filter v3" /root/bin/archive-filter; then
    echo "Already v3, skipping"
  else
    echo "Replacing with v3 from sample"
    sudo cp /root/bin/archive-filter.sample /root/bin/archive-filter
    sudo chmod +x /root/bin/archive-filter
  fi
else
  sudo cp /root/bin/archive-filter.sample /root/bin/archive-filter
  sudo chmod +x /root/bin/archive-filter
  echo "Activated archive-filter from sample"
fi
sudo head -2 /root/bin/archive-filter

echo ""
echo "=== 4. Validate config ==="
sudo bash /root/tools/validate-config.sh 2>&1 || echo "(validate-config returned non-zero — review warnings above)"

echo ""
echo "=== 5. Reload systemd + restart service ==="
sudo systemctl daemon-reload
sudo systemctl restart teslausb.service
sleep 3
echo "Service status: $(sudo systemctl is-active teslausb.service)"
sudo systemctl show teslausb.service | grep -E "WatchdogSec|NotifyAccess"

echo ""
echo "=== Done ==="
' 2>&1

echo ""
echo "All fixes applied. Verify health endpoint:"
echo "  curl -s -u pi:Trumpet7! http://$PI_HOST/cgi-bin/health.sh | python3 -m json.tool"