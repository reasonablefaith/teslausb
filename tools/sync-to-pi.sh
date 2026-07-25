#!/bin/bash -eu
#
# sync-to-pi.sh — Deploy TeslaUSB fork changes to a running Pi
#
# Syncs modified files from this fork to a running TeslaUSB Pi via SSH.
# Does NOT reboot or restart the teslausb service — just copies files.
# After syncing, run 'systemctl restart teslausb.service' on the Pi.
#
# Usage:
#   ./tools/sync-to-pi.sh [pi-hostname-or-ip]
#
# Default: pi@192.168.1.14 (mDNS unreliable on this Pi)
# Override: ./tools/sync-to-pi.sh teslausb.local

PI_HOST="${1:-192.168.1.14}"
PI_USER="pi"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FORK_DIR="$(dirname "$SCRIPT_DIR")"

echo "Syncing TeslaUSB fork to $PI_USER@$PI_HOST..."
echo "Fork directory: $FORK_DIR"
echo ""

# Files to sync (relative to fork root)
# Only sync files we modified — don't overwrite upstream files
# that the Pi may have customized locally.
FILES=(
  "run/archiveloop"
  "run/rsync_archive/archive-clips.sh"
  "run/rsync_archive/archive-is-reachable.sh"
  "run/rsync_archive/archive-ssh.sh"
  "run/make_snapshot.sh"
  "run/cifs_archive/verify-and-configure-archive.sh"
  "run/archive-filter.sample"
  "run/archive-filter-time-window.sample"
  "setup/pi/envsetup.sh"
  "setup/pi/configure.sh"
  "teslausb-www/html/cgi-bin/health.sh"
  "teslausb-www/html/diagnostics.html"
  "tools/validate-config.sh"
)

# Remount rootfs as read-write (TeslaUSB mounts / read-only by default)
echo "Remounting rootfs as read-write on Pi..."
ssh "$PI_USER@$PI_HOST" "sudo mount -o remount,rw /" 2>&1 || { echo "Failed to remount rootfs"; exit 1; }

# Create target directories on Pi
echo "Creating directories on Pi..."
ssh "$PI_USER@$PI_HOST" "sudo -i bash -c '
  mkdir -p /root/bin
  mkdir -p /var/www/html/TeslaCam/cgi-bin
  mkdir -p /var/www/html
  mkdir -p /root/tools
'" 2>&1 || { echo "Failed to create directories"; exit 1; }

# Sync each file
for f in "${FILES[@]}"
do
  src="$FORK_DIR/$f"
  if [ ! -f "$src" ]
  then
    echo "  SKIP: $f (not found in fork)"
    continue
  fi

  # Determine target path on Pi
  case "$f" in
    run/*)
      dest="/root/bin/$(basename "$f")"
      ;;
    setup/pi/*)
      dest="/root/bin/$(basename "$f")"
      ;;
    teslausb-www/html/cgi-bin/*)
      dest="/var/www/html/TeslaCam/cgi-bin/$(basename "$f")"
      ;;
    teslausb-www/html/*)
      dest="/var/www/html/$(basename "$f")"
      ;;
    tools/*)
      dest="/root/tools/$(basename "$f")"
      ;;
    *)
      echo "  SKIP: $f (unknown target path)"
      continue
      ;;
  esac

  echo "  $f -> $PI_USER@$PI_HOST:$dest"
  scp -q "$src" "$PI_USER@$PI_HOST:/tmp/teslausb_sync_$$"
  ssh "$PI_USER@$PI_HOST" "sudo -i cp /tmp/teslausb_sync_$$ '$dest' && rm -f /tmp/teslausb_sync_$$ && chmod +x '$dest'" 2>&1 || {
    echo "  FAILED: $f"
    exit 1
  }
done

echo ""
echo "Remounting rootfs as read-only on Pi..."
ssh "$PI_USER@$PI_HOST" "sudo mount -o remount,ro /" 2>&1 || echo "Warning: could not remount rootfs as read-only"

echo ""
echo "Sync complete!"
echo ""
echo "To apply changes, SSH to the Pi and run:"
echo "  ssh $PI_USER@$PI_HOST"
echo "  sudo systemctl restart teslausb.service"
echo ""
echo "To verify, check the health endpoint:"
echo "  curl http://$PI_HOST/TeslaCam/cgi-bin/health.sh"