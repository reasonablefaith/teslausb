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
  local_file_count=0
  if [ -s "$file_list" ]
  then
    local_file_count=$(wc -l < "$file_list")
  fi
  echo "$(date): rsync: $local_file_count file(s) from $source_dir to $RSYNC_USER@$RSYNC_SERVER:$RSYNC_PATH" >&2

  if ! (rsync -avhRL --timeout=60 --remove-source-files --no-perms --omit-dir-times \
        --stats --log-file=/tmp/archive-rsync-cmd.log --ignore-missing-args \
        --files-from="$file_list" "$source_dir" "$RSYNC_USER@$RSYNC_SERVER:$RSYNC_PATH" &> /tmp/rsynclog || [[ "$?" = "24" ]] )
  then
    cat /tmp/archive-rsync-cmd.log /tmp/rsynclog > /tmp/archive-error.log
    exit 1
  fi

  # Log transfer statistics
  if [ -f /tmp/archive-rsync-cmd.log ]
  then
    grep -E 'Number of (regular )?files transferred|Total file size|sent|received' /tmp/archive-rsync-cmd.log >&2 || true
  fi

  shift 2
done
