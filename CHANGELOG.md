# Changelog

## Batch 1: LAN-Specific Fixes
- Added: `ARCHIVE_UNREACHABLE_TIMEOUT` to prevent archiveloop hangs on LAN
- Fixed: Silent no-op in `archive-clips.sh` via diagnostic logging
- Fixed: Low timeouts in `archive-is-reachable.sh`
- Added: Sample archive filter script for front-camera filtering
- Added: `health.sh` JSON endpoint for remote monitoring
- Added: Documentation for new LAN variables in sample config

## Batch 2: QA, Community, and Ops Improvements
- Added: `ARCHIVE_REACHABLE_TIMEOUT` to prevent infinite wait for archive
- Fixed: Timeout accuracy using wall-clock epoch in `archiveloop`
- Added: Support for `EncryptedClips/` folder archiving
- Added: Warning for "Archived 0 files" silent failures
- Fixed: Invalid use of `local` at script level in `archive-clips.sh`
- Fixed: `bc` dependency in `health.sh`
- Added: Stuck detection and error counting to health endpoint
- Added: `tools/validate-config.sh` for pre-flight configuration checks
- Fixed: Regex in `archive-filter.sample` for RecentClips

## Batch 3: Reliability and Performance (Items 16-22)
- Added: Automatic retry of archive-clips on transient network errors
- Fixed: Memory leak in `health.sh` when handling large disk sizes
- Added: Support for ZFS-backed archive targets via specific rsync flags
- Fixed: Incorrect permission handling on CIFS mounts during archive
- Added: Parallel upload of clips for high-bandwidth LANs
- Fixed: Race condition in `archiveloop` during disk remount
- Added: Detailed rsync transfer rates in archive logs

## Batch 4: Final Polishing and Stability (Items 23-26)
- Added: Integration with systemd-notify for better service tracking
- Fixed: Improper cleanup of temporary file lists in `archive-clips.sh`
- Added: Configurable log rotation for `archiveloop` logs
- Fixed: SSH timeout inconsistency across different Pi OS versions
