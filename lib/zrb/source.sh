#!/bin/bash

zrb_source_remote_host() {
    local source_path=$1

    if [[ $source_path == /* ]]; then
        return 1
    fi

    if [[ $source_path =~ ^([0-9a-z@.-]+) ]]; then
        echo "${BASH_REMATCH[1]}"

        return 0
    fi

    return 1
}

zrb_source_ssh_config() {
    local config_file=$1

    if [ -f "$config_file" ]; then
        echo "$config_file"
    fi
}

zrb_source_check_remote_access() {
    local source_path=$1
    local ssh_config=$2
    local vault_name=$3
    local notify_address=$4
    local backup_host
    local -a ssh_args=()

    backup_host=$(zrb_source_remote_host "$source_path") || return 0

    if [ -n "$ssh_config" ]; then
        ssh_args+=(
            -F
            "$ssh_config"
        )
    fi

    if ( ! ssh "${ssh_args[@]}" "$backup_host" "echo -n" 2>/dev/null ); then
        echo "Host $backup_host is not accessible!" | mail -s "zrb.sh ERROR: $vault_name" "$notify_address"
        f_say "$C_RED Host $backup_host is not accessible!"

        return 1
    fi
}
