#!/bin/bash
# shellcheck disable=SC2034 # Nameref assignments provide outputs to callers.

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

zrb_source_validate_placeholder() {
    local source_path=$1
    local global_placeholder_file=$2
    local vault_placeholder_file=$3
    local vault_name=$4
    local notify_address=$5
    local placeholder=""
    local placeholder_path

    if [[ $source_path != /* ]]; then
        return 0
    fi

    if [ -e "$global_placeholder_file" ]; then
        placeholder=$(<"$global_placeholder_file")
    fi

    if [ -f "$vault_placeholder_file" ]; then
        placeholder=$(<"$vault_placeholder_file")
    fi

    placeholder_path="$source_path/$placeholder"

    if [ ! -e "$placeholder_path" ]; then
        echo "Placeholder file defined but does not exist: $placeholder_path !" | mail -s "zrb.sh ERROR: $vault_name" "$notify_address"
        f_say "$C_RED Placeholder file defined but does not exist: $placeholder_path !"
        f_say "$C_RED Filesystem is not mounted?"

        return 1
    fi
}

zrb_source_placeholder_path() {
    local target_name=$1
    local source_path=$2
    local global_placeholder_file=$3
    local vault_placeholder_file=$4
    local -n placeholder_path_ref=$target_name
    local placeholder=""

    placeholder_path_ref=""

    if [[ $source_path != /* ]]; then
        return 0
    fi

    if [ -e "$global_placeholder_file" ]; then
        placeholder=$(<"$global_placeholder_file")
    fi

    if [ -f "$vault_placeholder_file" ]; then
        placeholder=$(<"$vault_placeholder_file")
    fi

    placeholder_path_ref="$source_path/$placeholder"
}

zrb_source_remote_accessible() {
    local source_path=$1
    local ssh_config=$2
    local backup_host
    local -a ssh_args=()

    backup_host=$(zrb_source_remote_host "$source_path") || return 0

    if [ -n "$ssh_config" ]; then
        ssh_args+=(
            -F
            "$ssh_config"
        )
    fi

    ssh "${ssh_args[@]}" "$backup_host" "echo -n" 2>/dev/null
}

zrb_source_check_remote_access() {
    local source_path=$1
    local ssh_config=$2
    local vault_name=$3
    local notify_address=$4
    local backup_host

    backup_host=$(zrb_source_remote_host "$source_path") || return 0

    if ! zrb_source_remote_accessible "$source_path" "$ssh_config"; then
        echo "Host $backup_host is not accessible!" | mail -s "zrb.sh ERROR: $vault_name" "$notify_address"
        f_say "$C_RED Host $backup_host is not accessible!"

        return 1
    fi
}
