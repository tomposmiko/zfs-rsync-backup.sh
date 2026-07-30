#!/bin/bash

zrb_snapshot_name() {
    local prefix=$1
    local frequency=$2
    local timestamp=$3

    echo "${prefix}_${frequency}_${timestamp}"
}

zrb_snapshot_create() {
    local dataset=$1
    local prefix=$2
    local frequency=$3
    local timestamp=$4
    local snapshot_name
    local full_snapshot_name

    snapshot_name=$(zrb_snapshot_name "$prefix" "$frequency" "$timestamp")
    full_snapshot_name="$dataset@$snapshot_name"

    if { zfs list -H -o name -t snapshot "$full_snapshot_name" > /dev/null 2>&1; }; then
        f_say "${C_YELLOW:-}        WARNING:${C_NOCOLOR:-} Snapshot already exists: $full_snapshot_name"

        return 0
    fi

    zfs snap "$full_snapshot_name"
}
