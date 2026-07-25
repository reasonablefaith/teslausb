#!/bin/bash -eu
#
# archive-clips.sh — TeslaUSB rsync archive backend (Tailscale-aware)
#
# Transfers clip files from the Pi to the archive server using rsync.
# The file list passed via --files-from must contain paths RELATIVE to
# the rsync source directory ($1), NOT absolute paths.  rsync silently
# ignores absolute paths in --files-from (it prepends the source dir to
# every entry), which results in 0 files transferred with exit code 0
# — a silent no-op that is extremely hard to detect.
#
# If a file in the list no longer exists on the source, --ignore-missing-args
# skips it without error (exit 24 is treated as success for this reason).
#
# Tailscale routing: rsync and trigger SSH use /root/bin/archive-ssh.sh
# wrapper to avoid ProxyCommand quoting hell.
#
# Arguments (shift 4 loop — archiveloop passes 4 args per iteration):
#   $1 = source_dir          (rsync source, e.g. /tmp/cam/merged)
#   $2 = file_list           (sentrylist — files to transfer)
#   $3 = trigger_dir         (e.g. /tmp/triggers)
#   $4 = trigger_list        (e.g. /tmp/triggers.txt — often EMPTY)
#
# The key pitfall fixed here: checking $4 for SavedClips is wrong
# because $4 is empty when TRIGGER_FILE_SAVED is not configured.
# Check $2 (the actual file list) instead.

ARCHIVE_SSH_WRAPPER="/root/bin/archive-ssh.sh"

while [ -n "${1+x}" ]
do
  source_dir="$1"
  file_list="$2"

  # Log what we're about to transfer for diagnostics
  file_count=0
  if [ -s "$file_list" ]
  then
    file_count=$(wc -l < "$file_list")
  fi
  echo "$(date): rsync: $file_count file(s) from $source_dir to $RSYNC_USER@$RSYNC_SERVER:$RSYNC_PATH" >&2

  # Optional bandwidth limit (KB/s) to prevent saturating slow wifi
  bwlimit_opt=()
  if [[ "${RSYNC_BWLIMIT:-0}" -gt 0 ]] 2>/dev/null
  then
    bwlimit_opt=("--bwlimit=$RSYNC_BWLIMIT")
  fi

  # --partial: keep partially transferred files on the archive server (with a
  # .~partial~ suffix) when the transfer is interrupted by a timeout or
  # network drop. On the next rsync run, the partial file is detected and
  # the transfer resumes from where it left off instead of restarting the
  # whole file from byte 0. This is critical for large clip files that can
  # take many minutes to transfer over slow wifi and would otherwise be
  # re-transmitted in full after every transient network blip. Note: the
  # source file is only removed by --remove-source-files after a successful
  # complete transfer, so an interrupted transfer leaves the source intact
  # for the next attempt.
  if ! (rsync -avhRL --timeout=60 --partial --remove-source-files --no-perms --omit-dir-times \
        --stats --log-file=/tmp/archive-rsync-cmd.log --ignore-missing-args \
        --rsh="$ARCHIVE_SSH_WRAPPER" \
        "${bwlimit_opt[@]}" \
        --files-from="$file_list" "$source_dir" "${RSYNC_USER:?}@${RSYNC_SERVER:?}:${RSYNC_PATH:?}" &> /tmp/rsynclog || [[ "$?" = "24" ]] )
  then
    cat /tmp/archive-rsync-cmd.log /tmp/rsynclog > /tmp/archive-error.log
    exit 1
  fi

  # Log transfer statistics
  if [ -f /tmp/archive-rsync-cmd.log ]
  then
    grep -E 'Number of (regular )?files transferred|Total file size|sent|received' /tmp/archive-rsync-cmd.log >&2 || true

    # Calculate throughput (bytes/sec) from rsync stats
    transferred_bytes=$(grep 'Total transferred file size' /tmp/archive-rsync-cmd.log 2>/dev/null | sed 's/.*: //' | tr -dc '0-9' || echo 0)
    total_seconds=$(grep 'total size' /tmp/rsynclog 2>/dev/null | sed 's/.*speedup is.*//' | tr -dc '0-9' || echo 0)
    if [[ "$transferred_bytes" -gt 0 && "$total_seconds" -gt 0 ]] 2>/dev/null
    then
      throughput_bps=$((transferred_bytes / total_seconds))
      throughput_kbps=$((throughput_bps / 1024))
      echo "$(date): rsync throughput: ${throughput_kbps} KB/s (${transferred_bytes} bytes in ${total_seconds}s)" >&2
    fi
  fi

  # Trigger processing box when SavedClips were archived.
  # $2 is the file list (sentrylist) that contains the actual files being rsynced.
  # TRIGGER: fire whenever ANY SavedClips entry is in the transfer list.
  if [ -n "${2+x}" ] && [ -s "$2" ] && grep -q '^SavedClips/' "$2"; then
      $ARCHIVE_SSH_WRAPPER -o ConnectTimeout=5 -o BatchMode=yes \
          "${RSYNC_USER:?}@${RSYNC_SERVER:?}" \
          "python3 /home/greg/.openclaw/workspace/scripts/tc_pipeline_trigger.py set" \
          > /dev/null 2>&1 || true
  fi

  shift 4
done
