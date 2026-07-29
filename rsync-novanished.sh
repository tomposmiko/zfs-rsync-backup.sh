#!/bin/bash

rsync --rsync-path="sudo rsync" "$@"
status=$?

if [ "$status" -eq 23 ] || [ "$status" -eq 24 ]; then
    exit 0
fi

exit "$status"
