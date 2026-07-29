#!/bin/bash

zrb_completion_begin() {
    local completion_file=$1
    local vault_name=$2
    local notify_address=$3

    if [ -f "$completion_file" ]; then
        rm -f "$completion_file"
    else
        echo "Last backup was not succesful. Continuing from the last point." | mail -s "zrb.sh ERROR: $vault_name" "$notify_address"
        f_say "$C_RED Last backup was not succesful. Continuing from the last point."
    fi
}

zrb_completion_mark_success() {
    local completion_file=$1
    local rsync_status=$2

    if [ "$rsync_status" -eq 0 ]; then
        touch "$completion_file"
    fi
}
