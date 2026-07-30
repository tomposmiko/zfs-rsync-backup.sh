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

zrb_rsync_diagnostics_only_report_source_changes() {
    local diagnostics_file=$1
    local diagnostic
    local source_change_found=0

    while IFS= read -r diagnostic || [ -n "$diagnostic" ]; do
        case "$diagnostic" in
            "")
                ;;
            "file has vanished: "*)
                source_change_found=1
                ;;
            "rsync: ["*"] link_stat "*" failed: No such file or directory (2)")
                source_change_found=1
                ;;
            "rsync: ["*"] readlink_stat("*") failed: No such file or directory (2)")
                source_change_found=1
                ;;
            "ERROR: "*" failed verification -- update discarded.")
                source_change_found=1
                ;;
            "rsync warning: some files vanished before they could be transferred"*)
                ;;
            "rsync error: some files/attrs were not transferred"*"code 23"*)
                ;;
            *)
                return 1
                ;;
        esac
    done < "$diagnostics_file"

    [ "$source_change_found" -eq 1 ]
}

zrb_rsync_status_is_acceptable() {
    local status=$1
    local diagnostics_file=${2:-}

    case "$status" in
        0|24)
            return 0
            ;;
        23)
            if [ -z "$diagnostics_file" ]; then
                return 1
            fi

            zrb_rsync_diagnostics_only_report_source_changes "$diagnostics_file"
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
    local diagnostics_file
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

    diagnostics_file=$(mktemp) || return 1

    "${command[@]}" 2> "$diagnostics_file"
    status=$?

    cat "$diagnostics_file" >&2

    if { zrb_rsync_status_is_acceptable "$status" "$diagnostics_file"; }; then
        rm -f "$diagnostics_file"

        return 0
    fi

    rm -f "$diagnostics_file"

    return "$status"
}
