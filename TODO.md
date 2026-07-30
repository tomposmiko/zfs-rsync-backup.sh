# TODO

- Add LVM snapshot support.
- Determine how to back up GlusterFS.
- Confirm how MRB views should be backed up and whether `-R` is appropriate.
- Do not create a snapshot when rsync transfers no data.
- Run rsync only after creating a remote snapshot in a pre-run hook.
