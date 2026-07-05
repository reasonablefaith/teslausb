# TeslaUSB Fork Improvements

This fork of [marcone/teslausb](https://github.com/marcone/teslausb) contains
improvements developed for a production TeslaCam pipeline that uses TeslaUSB on
a Raspberry Pi connected via LAN (not the typical mobile/wifi-drive-away use
case).

## Background

The TeslaCam pipeline (workstation-side) processes raw dashcam footage from a
Tesla into polished YouTube videos with music overlay. The Pi running TeslaUSB
sits in the car, archives clips to the workstation via rsync when the car
returns home, and the workstation handles encoding, audio, and upload.

Several issues were discovered during months of production use that are
specific to the LAN/permanent-installation use case.

## Improvements

### 1. Archiveloop LAN Timeout (`ARCHIVE_UNREACHABLE_TIMEOUT`)

**Problem**: The archiveloop's main loop is:
`wait_for_archive_reachable → archive_clips → wait_for_archive_unreachable → repeat`

The `wait_for_archive_to_be_unreachable()` function polls in an **infinite loop
with no timeout**. This is correct for the mobile use case (car drives away → Pi
loses WiFi → archive unreachable → loop continues). But on a LAN where the
workstation never "drives away," a transient rsync failure (workstation asleep,
brief network hiccup) leaves the archiveloop trapped forever in the
unreachable-wait — taking snapshots but never re-attempting archiving.

**Fix**: Added `ARCHIVE_UNREACHABLE_TIMEOUT` environment variable (seconds).
When set > 0, the function breaks out after the timeout and re-attempts
archiving. When 0 (or unset), falls back to the original infinite-wait
behaviour — fully backward compatible.

**Config**: `export ARCHIVE_UNREACHABLE_TIMEOUT=300` in
`teslausb_setup_variables.conf`

**Files changed**:
- `run/archiveloop` — timeout logic in `wait_for_archive_to_be_unreachable()`
- `setup/pi/envsetup.sh` — export the variable
- `pi-gen-sources/.../teslausb_setup_variables.conf.sample` — documentation

### 2. Rsync Archive-Clips Logging

**Problem**: The original `archive-clips.sh` silently transferred 0 files if
the `--files-from` list contained absolute paths (rsync interprets them as
relative to the source dir, doubling the path). The script exited 0 with no
error, making this a **silent no-op** — extremely hard to diagnose.

**Fix**: Added diagnostic logging — file count before transfer, and rsync
statistics after transfer — plus comprehensive documentation of the
`--files-from` relative-path requirement.

**Files changed**: `run/rsync_archive/archive-clips.sh`

### 3. Archive-Is-Reachable Timeout

**Problem**: The SSH fallback in `archive-is-reachable.sh` used
`ConnectTimeout=1`, which is too short for some network conditions, but the
ping only used `-w 1` (1 second deadline). On slow networks, both could
incorrectly report the archive as unreachable.

**Fix**: Increased ping deadline to 2s and SSH `ConnectTimeout` to 5s for more
reliable reachability detection while still keeping the retry loop responsive.

**Files changed**: `run/rsync_archive/archive-is-reachable.sh`

### 4. Archive Filter Hook (Sample)

**Feature**: The archiveloop already calls `/root/bin/archive-filter` if it
exists. This fork adds a **sample filter script** that demonstrates
front-camera-only RecentClips filtering — useful for driving-focused channels
that don't need side/rear cameras.

**Files added**: `run/archive-filter.sample`

**Usage**: Copy to `/root/bin/archive-filter`, make executable, customise.

### 5. Health/Status JSON Endpoint

**Feature**: New `health.sh` CGI script for the web UI that returns JSON with:
- archiveloop running status
- last archive log entry timestamp
- cam disk free/total bytes
- snapshot count
- uptime
- wifi status
- temperature

This can be polled by a workstation monitoring system (cron-based watchdog) to
detect:
- archiveloop stuck in wait_for_archive_unreachable (the LAN bug)
- disk full conditions
- wifi failures
- stale snapshots (no recent archive activity)

**Files added**: `teslausb-www/html/cgi-bin/health.sh`

**URL**: `http://<hostname>/TeslaCam/cgi-bin/health.sh`

### 6. Sample Config Documentation

Added documentation for all new variables to the sample config file:
- `ARCHIVE_UNREACHABLE_TIMEOUT`
- `ARCHIVE_FILTER_SCRIPT`
- Health endpoint URL

**Files changed**: `pi-gen-sources/.../teslausb_setup_variables.conf.sample`

## Compatibility

All changes are **backward compatible**:
- New variables default to 0/unset → original behaviour preserved
- New files (health.sh, archive-filter.sample) don't affect existing installs
- No changes to the archiveloop's core logic — only additions

## Upstream Sync

This fork tracks `marcone/teslausb` as upstream. To sync:

```bash
git fetch upstream
git merge upstream/main-dev
```

## License

MIT (same as upstream teslausb)