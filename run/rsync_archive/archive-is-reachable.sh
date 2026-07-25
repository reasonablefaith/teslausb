#!/bin/sh
#
# archive-is-reachable.sh — Archive reachability probe (Tailscale-aware)
#
# Try ping first (2s timeout — keeps the archiveloop retry loop responsive).
# On failure, fall back to an SSH probe routed through /root/bin/archive-ssh.sh,
# which tunnels over Tailscale (with LAN fallback) when direct ICMP/SSH is
# blocked. Tailscale adds latency, so use a 10s ConnectTimeout instead of
# the 5s we used for direct LAN SSH.

ARCHIVE_HOST_NAME="$1"
ARCHIVE_SSH_WRAPPER="/root/bin/archive-ssh.sh"

ping -q -w 2 -c 1 "$ARCHIVE_HOST_NAME" > /dev/null 2>&1 || \
  $ARCHIVE_SSH_WRAPPER -q -o ConnectTimeout=10 "$RSYNC_USER@$ARCHIVE_HOST_NAME" exit
