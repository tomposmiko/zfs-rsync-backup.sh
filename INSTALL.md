# Installation

Install the commands and libraries under one directory so the entrypoints can resolve `lib/zrb` relative to themselves. A typical installation is:

```bash
install -d /opt/zrb.sh/lib/zrb /etc/zrb
install -m 0755 zrb.sh parallel-zrb.sh zrb-client.sh /opt/zrb.sh/
install -m 0644 lib/zrb/*.sh /opt/zrb.sh/lib/zrb/
ln -sfn /opt/zrb.sh/zrb.sh /usr/local/sbin/zrb.sh
ln -sfn /opt/zrb.sh/parallel-zrb.sh /usr/local/sbin/parallel-zrb.sh
ln -sfn /opt/zrb.sh/zrb-client.sh /usr/local/sbin/zrb-client.sh
install -m 0644 etc/zrb/exclude etc/zrb/expire etc/zrb/backup_dataset /etc/zrb/
install -m 0644 etc/cron.d/zrb-runall /etc/cron.d/zrb-runall
```

Review `/etc/zrb/backup_dataset`, `/etc/zrb/exclude`, `/etc/zrb/expire`, and the cron schedule before the first run.

Run the complete project validation before installation:

```bash
make check
```

`deprecated/rsync-novanished.sh` is retained only for historical compatibility and is not required by the current entrypoints.
