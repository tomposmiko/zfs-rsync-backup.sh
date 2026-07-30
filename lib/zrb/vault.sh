#!/bin/bash
# shellcheck disable=SC2034 # Nameref assignments provide outputs to callers.

zrb_vault_report_error() {
    local message=$1
    local vault_name=$2
    local notify_address=$3

    if [ -n "$notify_address" ]; then
        echo "$message" | mail -s "zrb.sh ERROR: $vault_name" "$notify_address"
    fi

    f_say "$C_RED $message"
}

zrb_vault_create() {
    local backup_dataset=$1
    local vault_name=$2
    local data_source=$3
    local vault_root="/$backup_dataset/$vault_name"
    local vault_config="$vault_root/config"
    local vault_data="$vault_root/data"
    local vault_log="$vault_root/log"

    if [ -d "$vault_root" ]; then
        f_say "$C_RED Cannot add vault!"
        f_say "$C_RED Existing directory: $vault_root !"

        return 1
    fi

    if { zfs list -s name "$backup_dataset/$vault_name" > /dev/null 2>&1; }; then
        f_say "$C_RED Cannot add vault!"
        f_say "$C_RED Existing dataset: $backup_dataset/$vault_name !"

        return 1
    fi

    if ! { zfs create "$backup_dataset/$vault_name"; }; then
        f_say "$C_RED Cannot create dataset:"
        f_say "$C_RED $ zfs create $backup_dataset/$vault_name"

        return 1
    fi

    mkdir "$vault_config"
    mkdir "$vault_data"
    mkdir "$vault_log"
    echo "$data_source" > "$vault_config/source"

    echo
    zfs list -s name "$backup_dataset/$vault_name"
    echo
    f_say "$C_GREEN Data source: $data_source"
    echo
}

zrb_vault_list() {
    local backup_dataset=$1
    local vault_query=$2
    local notify_address=$3
    local filesystems

    if [[ $vault_query == "$backup_dataset"* ]]; then
        zfs list -s name -t all -r "$vault_query"

        return
    fi

    filesystems=$(zfs list -o name -s name | grep "^$backup_dataset/.*$vault_query")

    if [ -z "$filesystems" ]; then
        echo "No matching filesystem!" | mail -s "zrb.sh ERROR: $vault_query" "$notify_address"
        f_say "$C_RED No matching filesystem!"

        return 1
    fi

    zfs list -s name -t all -r "$filesystems"
}

zrb_vault_validate() {
    local dataset_name=$1
    local vault_root=$2
    local vault_config=$3
    local vault_data=$4
    local vault_log=$5
    local vault_name=$6
    local notify_address=$7

    if ! { zfs list -s name "$dataset_name" > /dev/null 2>&1; }; then
        zrb_vault_report_error "Non-existent dataset for vault: $dataset_name !" "$vault_name" "$notify_address"

        return 1
    fi

    if [ ! -d "$vault_root" ]; then
        zrb_vault_report_error "Non-existent vault directory: $vault_root !" "$vault_name" "$notify_address"

        return 1
    fi

    if [ ! -d "$vault_config" ]; then
        zrb_vault_report_error "Non-existent config directory: $vault_config !" "$vault_name" "$notify_address"

        return 1
    fi

    if [ ! -d "$vault_data" ]; then
        zrb_vault_report_error "Non-existent rsync destination directory: $vault_data !" "$vault_name" "$notify_address"

        return 1
    fi

    if [ ! -d "$vault_log" ]; then
        zrb_vault_report_error "Non-existent rsync destination directory: $vault_log !" "$vault_name" "$notify_address"

        return 1
    fi
}

zrb_vault_is_disabled() {
    local vault_config=$1

    [ -f "$vault_config/DISABLE" ]
}

zrb_vault_load_source() {
    local target_name=$1
    local vault_config=$2
    local vault_name=$3
    local notify_address=$4
    local -n source_ref=$target_name
    local source_file="$vault_config/source"

    if [ ! -f "$source_file" ] || [ ! -r "$source_file" ]; then
        zrb_vault_report_error "Non-existent or unreadable source file: $source_file !" "$vault_name" "$notify_address"

        return 1
    fi

    source_ref=$(cat "$source_file")
}

zrb_vault_resolve_excludes() {
    local additional_target_name=$1
    local vault_target_name=$2
    local exclude_parameter=$3
    local vault_config=$4
    local -n additional_ref=$additional_target_name
    local -n vault_ref=$vault_target_name
    local vault_exclude_file="$vault_config/exclude"

    additional_ref=""
    vault_ref=""

    if [ -n "$exclude_parameter" ]; then
        additional_ref="--exclude-from=$exclude_parameter"
    fi

    if [ -f "$vault_exclude_file" ]; then
        if [ -n "$exclude_parameter" ]; then
            f_say "$C_RED The switch '--exclude-file' and the 'vault specific exclude' file are mutually exclusive!"
            f_say "$C_RED switch: $exclude_parameter"
            f_say "$C_RED exclude file: $vault_exclude_file"

            return 1
        fi

        vault_ref="--exclude-from=$vault_exclude_file"
    fi
}

zrb_vault_add_notify_address() {
    local target_name=$1
    local vault_config=$2
    local -n notify_ref=$target_name
    local notify_file="$vault_config/notify"
    local vault_notify_address

    if [ ! -f "$notify_file" ]; then
        return 0
    fi

    vault_notify_address=$(cat "$notify_file")

    if [ -z "$vault_notify_address" ]; then
        return 0
    fi

    if ! { echo "$vault_notify_address" | grep -q @; }; then
        f_say "$C_RED $vault_notify_address is not a valid email address"

        return 1
    fi

    notify_ref="$notify_ref,$vault_notify_address"
}
