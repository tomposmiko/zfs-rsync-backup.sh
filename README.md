zfs rsync backup
----------------
zrb (*Z*FS *R*sync *B*ackup) is a simple and rough solution to manage backup with the 'rsync' + 'zfs snapshot' commands.
It is running from a central backup server and works pull mode.

Features:
- pull mode backup
- resuming backup job ot of box
- excluding via rsync exclude file
- optionally different pool/dataset name
- various expiring rules
- parallel jobs with configurable process number
- command to add and list vaults

USAGE
=====

Display the installed version:

$ zrb.sh --version

#### dictionary
VAULT: backup directory where backed up data and config files kept.
Each VAULT has 3 directories:
config/ -> per VAULT config files
data/ -> copied data
log/ -> logs

Each vault also uses execution-state markers:
RUNNING -> a backup is currently in progress or the server stopped before cleanup
FAILED -> the previous controlled or recovered abandoned run failed
FINISHED -> the previous rsync run completed with an accepted status

#### init
- local (mounted) directory

$ zrb.sh -a /path/to/backup/source -v VAULT

- remote source (rsync syntax)

$ zrb.sh -a hostname:/ -v VAULT


Initializes zfs dataset of the VAULT and necessary directories and define rsync source.

#### client setup

Copy the backup server public key to the client and preview the required changes:

$ zrb-client.sh --public-key-file /path/to/backup.pub --dry-run

Apply the client configuration:

$ zrb-client.sh --public-key-file /path/to/backup.pub

#### manual running
$ zrb.sh -v VAULT

#### preflight

Validate a vault without running hooks, rsync, snapshots, retention, locks, reports, or state-marker changes:

$ zrb.sh --check -v VAULT

The preflight report checks required commands, backup and vault datasets, vault directories, source configuration, exclude files, notification addresses, log writability, local placeholders or remote SSH access, hook syntax, and retention configuration. It continues through all safe checks so one run reports every detected problem.

Each result starts with a green `PASS` or red `FAIL`. Only the status word is colorized. The final line summarizes the number of passed and failed checks:

```text
PASS: Preflight check passed: 26 checks passed.
```

or:

```text
FAIL: Preflight check failed: 22 checks passed, 3 checks failed.
```

#### expected-share backup coverage

The normal parallel runner and freshness monitor discover existing vaults. They cannot detect a project that never had a vault. `zrb-coverage.sh` starts with the expected Samba inventory instead, and reports every missing or inconsistent backup configuration.

```bash
zrb-coverage.sh --inventory /tank/zrb/samba_shares.txt --ignore-host samba-dfs --ignore-share R2D2
```

For `samba11:ABCD:/tank/Projects/ABCD` (or `/data/Projects/ABCD`), the expected vault is `tank/zrb/Projects/ABCD` and its source file is `/tank/zrb/Projects/ABCD/config/source`. Both default source prefixes map to the same relative vault name. The source file must refer to the same host and path; a `user@` prefix and trailing slash are accepted, but regex, prefix and substring matching are not used.

The audit flags missing datasets/configuration/directories, incorrect sources, disabled vaults, destination collisions, wrong/unmounted mountpoints, and non-leaf vaults skipped by `parallel-zrb.sh`. It makes one read-only ZFS dataset listing (including volumes when checking leaf selection), reads configuration and never contacts sources, starts backups, runs hooks, snapshots, retention, mail commands or modifies state markers. It does not modify files at all. Only findings/errors produce output by default, so cron can email them. Exit 0 means configured and eligible for the normal parallel runner; exit 1 means coverage problems; exit 2 means the audit could not run. Use `--verbose` for a success summary.

Findings are separated by blank lines, with a short heading and labeled details:

```text
MISSING_VAULT: samba17/HAL
- server path: samba17:/data/Projects/HAL
- vault dataset: tank/zrb/Projects/HAL
```

Configure email in `etc/cron.d/zrb-coverage` (`MAILTO=root` by default). The audit example runs hourly. The companion Puppet repository installs the checker and cron on backup servers and improves Samba inventory generation using parsed `testparm -s` output, source timestamps, row counts and independent expected-host markers. The new generator keeps the previous inventory if parsing fails.

```bash
zrb-coverage.sh --max-inventory-age 36h --hosts-file /tank/zrb/samba_servers.txt \
  --ignore-host samba-dfs --ignore-share R2D2
```

Strict inventory-age checking detects stale, missing and incomplete per-host exports. The regenerated aggregate file mtime is deliberately ignored. Puppet automatically registers every server managed by `pts_samba` in `/tank/zrb/samba_servers.txt`, independently of its share inventory. The scheduled audit reads this file with `--hosts-file` and detects missing share exports without a manually maintained server list. An empty or unavailable server list is an audit failure. Legacy three-field inventories remain accepted when no age requirement is passed. An empty/fully excluded inventory always fails rather than claiming complete coverage.

Host and filesystem aliases are never guessed. If verified equivalent, configure them explicitly, for example `--host-alias samba11.prd.svfx=samba11 --path-alias /data=/tank`. Do not add an alias merely to hide a wrong-source report. Other source roots can be configured with repeatable `--source-prefix` arguments, which replace the `/data`, `/tank` defaults. The backup root dataset is read from `/etc/zrb/backup_dataset` (or legacy `BACKUP_DATASET`), with optional CLI overrides; vault mountpoints must match zrb's expected `/<dataset>/<vault>` layout.

This is **configuration coverage**, not proof of a recent successful backup or restore. Keep the existing FINISHED/RUNNING/FAILED freshness monitoring and job-failure emails. It does not evaluate rsync exclude files, hooks, parent-level aggregate backups or custom scheduling. The inventory includes declared Samba shares; unshared project directories require an independent source inventory. Explicit ignore rules are exact matches and should be reviewed as backup-policy exceptions.

#### expiring
- preview expiration without deleting snapshots:

$ zrb.sh -e preview -v VAULT

$ zrb.sh -e dry-run -v VAULT

- expire only:

$ zrb.sh -e only -v VAULT

- backup + expire:

$ zrb.sh -e yes -v VAULT

#### cron job
$ cp etc/cron.d/zrb-runall /etc/cron.d/

$ chmod 644 /etc/cron.d/zrb-runall

Change whatever timing and frequency (eg. hourly, daily, weekly, monthly) you prefer.

#### listing
$ zrb.sh -l VAULT

ARCHITECTURE
============

The executable scripts are thin entrypoints. Reusable behavior is grouped by responsibility under `lib/zrb`, including configuration, CLI parsing, vaults, source checks, rsync, snapshots, retention, locks, completion state, reports, hooks, parallel execution, and client provisioning.

Use `make check` to run Bash syntax validation, ShellCheck, and the complete test suite.

See `INSTALL.md` for the installation layout.

`deprecated/rsync-novanished.sh` is retained only for historical compatibility. Current backups use the exit-status policy in `lib/zrb/rsync.sh`.
