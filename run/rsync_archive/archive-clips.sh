#!/bin/bash -eu

# archive-clips.sh — rsync archive backend
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

  if ! (rsync -avhRL --timeout=60 --remove-source-files --no-perms --omit-dir-times \
        --stats --log-file=/tmp/archive-rsync-cmd.log --ignore-missing-args \
        "${bwlimit_opt[@]}" \
        --files-from="$file_list" "$source_dir" "$RSYNC_USER@$RSYNC_SERVER:$RSYNC_PATH" &> /tmp/rsynclog || [[ "$?" = "24" ]] )
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

  shift 2
done
