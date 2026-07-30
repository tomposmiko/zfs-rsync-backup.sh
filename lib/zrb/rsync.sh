#!/bin/bash

zrb_rsync_build_args() {
    local target_name=$1
    local log_file=$2
    local global_exclude_file=$3
    local additional_exclude_arg=$4
    local vault_exclude_arg=$5
    local -n target=$target_name

    target=(
        -v
        -r
        -l
        -t
        -H
        --delete
        --delete-excluded
        -p
        -g
        -o
        --stats
        -h
        -D
        --numeric-ids
        --inplace
        "--log-file=$log_file"
        "--exclude-from=$global_exclude_file"
    )

    if [ -n "$additional_exclude_arg" ]; then
        target+=("$additional_exclude_arg")
    fi

    if [ -n "$vault_exclude_arg" ]; then
        target+=("$vault_exclude_arg")
    fi
}

zrb_rsync_status_is_acceptable() {
    local status=$1

    case "$status" in
        0|23|24)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

zrb_rsync_run() {
    local source_path=$1
    local destination_path=$2
    local ssh_config=$3
    local args_name=$4
    local -n rsync_args_ref=$args_name
    local status
    local -a command=(
        rsync
        --rsync-path
        "sudo rsync"
    )

    if [ -n "$ssh_config" ]; then
        command+=(
            -e
            "ssh -F $ssh_config"
        )
    fi

    command+=(
        "${rsync_args_ref[@]}"
        "$source_path/"
        "$destination_path/"
    )

    "${command[@]}"
    status=$?

    if zrb_rsync_status_is_acceptable "$status"; then
        return 0
    fi

    return "$status"
}
