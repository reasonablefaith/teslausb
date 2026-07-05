#!/bin/bash -eu
#
# validate-config.sh — Pre-flight configuration validation for TeslaUSB
#
# Checks teslausb_setup_variables.conf for common mistakes before boot
# or after config changes. Run manually or via setup-teslausb.
#
# Usage:
#   sudo /root/bin/validate-config.sh
#   sudo /root/bin/validate-config.sh /path/to/teslausb_setup_variables.conf
#
# Exit codes:
#   0 = all checks passed (or warnings only)
#   1 = one or more critical checks failed

set -u

# Colors for terminal output
if [ -t 1 ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  NC='\033[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  NC=''
fi

PASS=0
FAIL=0
WARN=0

pass() { echo -e "${GREEN}✓ $1${NC}"; PASS=$((PASS + 1)); }
fail() { echo -e "${RED}✗ $1${NC}"; FAIL=$((FAIL + 1)); }
warn() { echo -e "${YELLOW}⚠ $1${NC}"; WARN=$((WARN + 1)); }

CONFIG_FILE="${1:-/root/teslausb_setup_variables.conf}"

if [ ! -f "$CONFIG_FILE" ]; then
  fail "Config file not found: $CONFIG_FILE"
  exit 1
fi

echo "Validating $CONFIG_FILE"
echo "=============================================="

# Source the config to get variables
eval "$(grep -E '^export ' "$CONFIG_FILE" | sed 's/^export //' || true)"

# --- Archive System ---
echo ""
echo "[Archive]"

if [ -z "${ARCHIVE_SYSTEM:-}" ]; then
  fail "ARCHIVE_SYSTEM not set — archiving will be disabled"
else
  pass "ARCHIVE_SYSTEM=$ARCHIVE_SYSTEM"
fi

case "${ARCHIVE_SYSTEM:-none}" in
  rsync)
    if [ -z "${RSYNC_SERVER:-}" ]; then
      fail "RSYNC_SERVER not set (required for rsync archive)"
    else
      pass "RSYNC_SERVER=$RSYNC_SERVER"
      # Check reachability (only if we have network)
      if ping -q -w 2 -c 1 "$RSYNC_SERVER" > /dev/null 2>&1; then
        pass "RSYNC_SERVER ($RSYNC_SERVER) is reachable"
      else
        warn "RSYNC_SERVER ($RSYNC_SERVER) is not reachable (may be offline or Pi not connected to wifi yet)"
      fi
    fi
    if [ -z "${RSYNC_USER:-}" ]; then
      fail "RSYNC_USER not set (required for rsync archive)"
    else
      pass "RSYNC_USER=$RSYNC_USER"
    fi
    if [ -z "${RSYNC_PATH:-}" ]; then
      warn "RSYNC_PATH not set (files will be archived to home directory)"
    else
      pass "RSYNC_PATH=$RSYNC_PATH"
    fi
    # Check SSH key exists
    if [ -f /root/.ssh/id_rsa ]; then
      pass "SSH key found: /root/.ssh/id_rsa"
    elif [ -f /root/.ssh/id_ed25519 ]; then
      pass "SSH key found: /root/.ssh/id_ed25519"
    else
      warn "No SSH key found in /root/.ssh/ — rsync will require password auth"
    fi
    ;;
  cifs)
    if [ -z "${ARCHIVE_SERVER:-}" ]; then fail "ARCHIVE_SERVER not set (required for CIFS)"; else pass "ARCHIVE_SERVER=$ARCHIVE_SERVER"; fi
    if [ -z "${SHARE_NAME:-}" ]; then fail "SHARE_NAME not set (required for CIFS)"; else pass "SHARE_NAME=$SHARE_NAME"; fi
    if [ -z "${SHARE_USER:-}" ]; then warn "SHARE_USER not set (guest access)"; else pass "SHARE_USER=$SHARE_USER"; fi
    ;;
  rclone)
    if [ -z "${RCLONE_DRIVE:-}" ]; then fail "RCLONE_DRIVE not set (required for rclone)"; else pass "RCLONE_DRIVE=$RCLONE_DRIVE"; fi
    ;;
  nfs)
    if [ -z "${ARCHIVE_SERVER:-}" ]; then fail "ARCHIVE_SERVER not set (required for NFS)"; else pass "ARCHIVE_SERVER=$ARCHIVE_SERVER"; fi
    if [ -z "${SHARE_NAME:-}" ]; then fail "SHARE_NAME not set (required for NFS)"; else pass "SHARE_NAME=$SHARE_NAME"; fi
    ;;
  none)
    warn "ARCHIVE_SYSTEM=none — no archiving will occur"
    ;;
esac

# --- WiFi ---
echo ""
echo "[WiFi]"

if [ -z "${SSID:-}" ]; then
  warn "SSID not set (must be pre-configured or set via wpa_supplicant)"
else
  pass "SSID=$SSID"
fi

if [ -z "${WIFIPASS:-}" ]; then
  warn "WIFIPASS not set (must be pre-configured)"
else
  pass "WIFIPASS is set (hidden)"
fi

# --- Storage ---
echo ""
echo "[Storage]"

if [ "${CAM_SIZE:-0}" = "0" ]; then
  warn "CAM_SIZE not set or 0 — default will be used"
else
  pass "CAM_SIZE=${CAM_SIZE}"
fi

# Check if backing files exist
if [ -f /backingfiles/cam_disk.bin ]; then
  pass "cam_disk.bin exists"
  cam_free=$(stat --file-system --format="%f" /backingfiles/cam_disk.bin 2>/dev/null || echo "?")
  pass "cam_disk.bin free blocks: $cam_free"
else
  warn "cam_disk.bin not found (may not be created yet — normal for first boot)"
fi

# --- Archive Options ---
echo ""
echo "[Archive Options]"

for opt in ARCHIVE_SAVEDCLIPS ARCHIVE_SENTRYCLIPS ARCHIVE_TRACKMODECLIPS ARCHIVE_RECENTCLIPS ARCHIVE_ENCRYPTEDCLIPS; do
  val="${!opt:-}"
  if [ -n "$val" ]; then
    pass "$opt=$val"
  fi
done

# --- Timeouts ---
echo ""
echo "[Timeouts]"

if [ "${ARCHIVE_UNREACHABLE_TIMEOUT:-0}" -gt 0 ] 2>/dev/null; then
  pass "ARCHIVE_UNREACHABLE_TIMEOUT=${ARCHIVE_UNREACHABLE_TIMEOUT}s (LAN mode)"
elif [ -n "${ARCHIVE_UNREACHABLE_TIMEOUT:-}" ]; then
  pass "ARCHIVE_UNREACHABLE_TIMEOUT=0 (infinite wait, mobile mode)"
else
  warn "ARCHIVE_UNREACHABLE_TIMEOUT not set (default: 0, infinite wait)"
fi

if [ "${ARCHIVE_REACHABLE_TIMEOUT:-0}" -gt 0 ] 2>/dev/null; then
  pass "ARCHIVE_REACHABLE_TIMEOUT=${ARCHIVE_REACHABLE_TIMEOUT}s"
elif [ -n "${ARCHIVE_REACHABLE_TIMEOUT:-}" ]; then
  pass "ARCHIVE_REACHABLE_TIMEOUT=0 (infinite wait)"
else
  warn "ARCHIVE_REACHABLE_TIMEOUT not set (default: 0, infinite wait)"
fi

# --- Notifications ---
echo ""
echo "[Notifications]"

notif_configured=false
for svc in PUSHOVER GOTIFY IFTTT SNS TELEGRAM DISCORD SLACK MATRIX NTFY WEBHOOK SIGNAL; do
  if [ "${${svc}_ENABLED:-false}" = "true" ] 2>/dev/null || [ "${!svc:-}" = "true" ] 2>/dev/null; then
    pass "$svc notifications enabled"
    notif_configured=true
  fi
done

if [ "$notif_configured" = false ]; then
  warn "No push notification system configured — you won't be alerted to archive failures"
fi

# --- Keep Awake ---
echo ""
echo "[Keep Awake]"

if [ -n "${SENTRY_CASE:-}" ]; then
  pass "SENTRY_CASE=$SENTRY_CASE"
  # Check that only one API is configured
  apis=0
  [ -n "${TESLAFI_API_TOKEN:-}" ] && apis=$((apis + 1))
  [ -n "${TESSIE_API_TOKEN:-}" ] && apis=$((apis + 1))
  [ -n "${TESLA_BLE_VIN:-}" ] && apis=$((apis + 1))
  [ -n "${KEEP_AWAKE_WEBHOOK_URL:-}" ] && apis=$((apis + 1))
  if [ "$apis" -gt 1 ]; then
    fail "Multiple keep-awake APIs configured ($apis) — only ONE should be used at a time"
  elif [ "$apis" -eq 1 ]; then
    pass "One keep-awake API configured"
  else
    warn "SENTRY_CASE set but no keep-awake API token configured"
  fi
fi

# --- Summary ---
echo ""
echo "=============================================="
echo -e "${GREEN}Passed: $PASS${NC}  ${RED}Failed: $FAIL${NC}  ${YELLOW}Warnings: $WARN${NC}"

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo -e "${RED}Configuration has $FAIL critical issue(s) that need to be fixed.${NC}"
  exit 1
else
  echo ""
  echo -e "${GREEN}Configuration validation complete.${NC}"
  exit 0
fi