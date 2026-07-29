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

#### expiring
- expire only:

$ zrb.sh -e only -v VAULT

- backup + expire:

$ zrb.sh -e yes -v VAULT

#### cron job
$ cp zrb-runall /etc/cron.d/

$ chmod 644 /etc/cron.d/zrb-runall

Change whatever timing and frequency (eg. hourly, daily, weekly, monthly) you prefer.

#### listing
$ zrb.sh -l VAULT

ARCHITECTURE
============

The executable scripts are thin entrypoints. Reusable behavior is grouped by responsibility under `lib/zrb`, including configuration, CLI parsing, vaults, source checks, rsync, snapshots, retention, locks, completion state, reports, hooks, parallel execution, and client provisioning.

Use `make check` to run Bash syntax validation, ShellCheck, and the complete test suite.

See `INSTALL.md` for the installation layout.

`rsync-novanished.sh` is a deprecated compatibility wrapper. Current backups use the exit-status policy in `lib/zrb/rsync.sh`.
