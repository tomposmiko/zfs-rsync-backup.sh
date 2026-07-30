CHANGELOG
---------
##### v0.5 - 2026-07-30

###### Changed
- Refactored the shell code into focused modules under `lib/zrb` while keeping thin executable entrypoints.
- Reworked `zrb.sh` into an orchestration workflow for configuration, vaults, source validation, rsync, hooks, reporting, snapshots, retention, locking, and completion state.
- Reworked `parallel-zrb.sh` to reuse shared modules, build commands as arrays, validate job counts, discover leaf vaults efficiently, and propagate failures.
- Made parallel-run output easier to scan with separated run boundaries, indented vault blocks, warning labels, and one labeled expired snapshot per line.
- Made `backup_dataset` the canonical configuration filename while retaining compatibility with the legacy `BACKUP_DATASET` name.
- Reorganized packaged configuration under `etc/zrb` and the cron example under `etc/cron.d`.
- Moved the deprecated `rsync-novanished.sh` compatibility wrapper under `deprecated`; current rsync status handling lives in `lib/zrb/rsync.sh`.

###### Added
- Added `zrb.sh --check` for non-mutating command, dataset, vault-directory, source, exclude, notification, SSH, retention, hook, and writability validation. It reports every safe check with colorized `PASS` or `FAIL` status words and finishes with aggregate counts.
- Added `RUNNING`, `FAILED`, and `FINISHED` markers to distinguish active, failed, interrupted, and successful rsync runs.
- Added controlled-exit cleanup for `EXIT`, `SIGINT`, and `SIGTERM` while preserving stale lock and `RUNNING` evidence after hard crashes.
- Added exact snapshot-name parsing, minimum retention enforcement, per-vault retention overrides, and explicit `no`, `yes`, and `only` expiration modes.
- Added secure temporary-file handling for parallel vault lists and sudoers generation.
- Added `--user`, `--public-key-file`, and `--dry-run` options to `zrb-client.sh`.
- Added `STYLE.md`, `INSTALL.md`, and a `make check` workflow.
- Added `--version` to all active commands using one shared version value.
- Added unit and stubbed end-to-end integration coverage for the active project, including nested vault names and aggregated preflight failures.

###### Fixed
- Fixed library discovery when entrypoints are invoked through symbolic links such as `/usr/local/sbin/zrb.sh`.
- Fixed incorrect rsync and SSH argument splitting by using Bash arrays.
- Fixed the parallel-runner lock filename initialization order and obsolete cron command name.
- Fixed absolute path handling for configuration directories, exclude files, and local backup sources.
- Fixed missing SSH source directories being accepted as rsync status 23 by validating the configured remote directory before backup and snapshot creation.
- Fixed exact snapshot-name collisions being silently accepted; an existing target snapshot now fails the run.
- Fixed successful completion being recorded before hooks, snapshots, and retention finished.
- Fixed pre-run and post-run hook failures being ignored.
- Fixed race-prone PID lock creation by using atomic kernel-backed locks while retaining PID files for inspection and crash diagnostics.
- Fixed interrupted runs leaving a lock without a failure marker by handling signals explicitly, ignoring repeated signals during cleanup, creating `FAILED` before removing `RUNNING`, and marking armed cleanups as failed unconditionally.
- Fixed snapshot retention matching so unrelated and malformed snapshots are ignored.
- Fixed snapshot creation, listing, destruction, rsync, ZFS discovery, and GNU Parallel failures so they propagate correctly.
- Fixed tests so failed assertions cannot be hidden by later cleanup commands.

###### Security
- Removed the embedded SSH public key from `zrb-client.sh`.
- Made client provisioning idempotent and required sudoers validation with `visudo -cf` before installation.
- Removed shell tracing from the deprecated rsync compatibility wrapper.

###### Compatibility
- Rsync exit statuses `23` and `24` remain accepted to preserve the existing changed or vanished source-file behavior.
- Legacy PID lock files and the legacy uppercase backup-dataset configuration filename remain supported.

##### v0.4
- expiring

##### v0.3
- add todo
- satisfying todo list
- interactive vs. script running
- parallel running
- add locking support
- add vault displaying option
- always run default exclude file
- renaming to zrb

##### v0.2
- add support to creating vault

##### v0.1
-  start testing in semi-production
