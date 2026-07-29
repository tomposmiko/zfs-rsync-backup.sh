# Installation

Install the commands and libraries under one directory so the entrypoints can resolve `lib/zrb` relative to themselves. A typical installation is:

```bash
install -d /opt/zrb/lib/zrb /etc/zrb /root/bin
install -m 0755 zrb.sh parallel-zrb.sh zrb-client.sh /opt/zrb/
install -m 0644 lib/zrb/*.sh /opt/zrb/lib/zrb/
ln -s /opt/zrb/zrb.sh /root/bin/zrb.sh
ln -s /opt/zrb/parallel-zrb.sh /root/bin/parallel-zrb.sh
ln -s /opt/zrb/zrb-client.sh /root/bin/zrb-client.sh
install -m 0644 etc/exclude etc/expire etc/backup_dataset /etc/zrb/
install -m 0644 zrb-runall /etc/cron.d/zrb-runall
```

Review `/etc/zrb/backup_dataset`, `/etc/zrb/exclude`, `/etc/zrb/expire`, and the cron schedule before the first run.

Run the complete project validation before installation:

```bash
make check
```

`rsync-novanished.sh` remains as a deprecated compatibility wrapper and is not required by the current entrypoints.
