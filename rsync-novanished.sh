#!/bin/bash

# Deprecated compatibility wrapper. zrb.sh now handles accepted rsync statuses in lib/zrb/rsync.sh.

rsync --rsync-path="sudo rsync" "$@"
status=$?

if [ "$status" -eq 23 ] || [ "$status" -eq 24 ]; then
    exit 0
fi

exit "$status"
