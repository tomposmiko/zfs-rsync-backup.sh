#!/bin/bash

zrb_completion_begin() {
    local completion_file=$1
    local running_file=$2
    local failed_file=$3
    local vault_name=$4
    local notify_address=$5
    local interrupted=0

    if [ -f "$running_file" ]; then
        rm -f "$running_file"
        touch "$failed_file"
        interrupted=1

        echo "Previous backup was interrupted. Continuing from the last point." | mail -s "zrb.sh ERROR: $vault_name" "$notify_address"

        f_say "${C_YELLOW:-}        WARNING:${C_NOCOLOR:-} Previous backup was interrupted; continuing from the last point."
    fi

    if [ -f "$completion_file" ]; then
        rm -f "$completion_file"
    elif [ "$interrupted" -eq 0 ]; then
        echo "Last backup was not successful. Continuing from the last point." | mail -s "zrb.sh ERROR: $vault_name" "$notify_address"

        f_say "${C_YELLOW:-}        WARNING:${C_NOCOLOR:-} Last backup was not successful; continuing from the last point."
    fi

    touch "$running_file"
}

zrb_completion_mark_success() {
    local completion_file=$1
    local running_file=$2
    local failed_file=$3
    local rsync_status=$4

    if [ "$rsync_status" -eq 0 ]; then
        touch "$completion_file"
        rm -f "$running_file" "$failed_file"
    fi
}

zrb_completion_mark_failed() {
    local running_file=$1
    local failed_file=$2

    if [ -f "$running_file" ]; then
        rm -f "$running_file"
        touch "$failed_file"
    fi
}
