#!/bin/bash -eu

ARCHIVE_HOST_NAME="$1"

# Use a short connect timeout so the archiveloop doesn't hang for
# the full SSH timeout when the archive server is temporarily down.
# The default SSH ConnectTimeout is system-dependent (often 30s+);
# we cap it at 5s to keep the retry loop responsive.
ping -q -w 2 -c 1 "$ARCHIVE_HOST_NAME" &> /dev/null || ssh -q -o ConnectTimeout=5 "$RSYNC_USER"@"$ARCHIVE_HOST_NAME" exit
