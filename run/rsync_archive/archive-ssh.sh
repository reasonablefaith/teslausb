#!/bin/sh
#
# archive-ssh.sh — SSH wrapper for Tailscale transport with LAN fallback
# Location on Pi: /root/bin/archive-ssh.sh
#
# Provides a clean ProxyCommand for routing SSH through Tailscale's
# userspace-networking daemon without inline quoting hell.
# Falls back to direct SSH if Tailscale proxy fails (daemon down,
# stale peer IP, or LAN-only connectivity).
#
# Usage: /root/bin/archive-ssh.sh [standard ssh flags] user@host command
#
# Must be owned by root:root with 755 permissions on the RO rootfs.
#
# CRITICAL: Do NOT use 'exec' — exec replaces the shell process entirely,
# so the '||' fallback to direct SSH can never execute.

ssh -i /root/.ssh/id_ed25519 -o StrictHostKeyChecking=no \
  -o "ProxyCommand=/mutable/bin/tailscale --socket=/mutable/tailscale/tailscaled.sock nc %h %p" \
  "$@" 2>/dev/null || \
  ssh -i /root/.ssh/id_ed25519 -o StrictHostKeyChecking=no \
  "$@"
