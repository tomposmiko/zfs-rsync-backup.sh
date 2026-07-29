#!/bin/bash
# shellcheck disable=SC2034 # Retention values are populated through nameref validation.

zrb_preflight_pass() {
    ZRB_PREFLIGHT_PASS_COUNT=$((${ZRB_PREFLIGHT_PASS_COUNT:-0} + 1))

    printf '%bPASS%b: %s\n' "${C_GREEN:-}" "${C_NOCOLOR:-}" "$1"
}

zrb_preflight_fail() {
    ZRB_PREFLIGHT_FAIL_COUNT=$((${ZRB_PREFLIGHT_FAIL_COUNT:-0} + 1))

    printf '%bFAIL%b: %s\n' "${C_RED:-}" "${C_NOCOLOR:-}" "$1"
}

zrb_preflight_summary() {
    local status=$1

    printf '\n'

    if [ "$status" -eq 0 ]; then
        printf '%bPASS%b: Preflight check passed: %d checks passed.\n' "${C_GREEN:-}" "${C_NOCOLOR:-}" "$ZRB_PREFLIGHT_PASS_COUNT"
    else
        printf '%bFAIL%b: Preflight check failed: %d checks passed, %d checks failed.\n' "${C_RED:-}" "${C_NOCOLOR:-}" "$ZRB_PREFLIGHT_PASS_COUNT" "$ZRB_PREFLIGHT_FAIL_COUNT"
    fi

    printf '\n'
}

zrb_preflight_commands() {
    local command_name
    local check_status=0

    for command_name in "$@"; do
        if ( ! command -v "$command_name" > /dev/null 2>&1 ); then
            zrb_preflight_fail "Missing required command: $command_name"
            check_status=1
        else
            zrb_preflight_pass "Required command '$command_name'"
        fi
    done

    return "$check_status"
}

zrb_preflight_readable_file() {
    local file_path=$1
    local label=$2

    if [ ! -r "$file_path" ]; then
        zrb_preflight_fail "$label is not readable: $file_path"

        return 1
    fi

    zrb_preflight_pass "$label is readable: $file_path"
}

zrb_preflight_writable_directory() {
    local directory_path=$1
    local label=$2

    if [ ! -d "$directory_path" ] || [ ! -w "$directory_path" ]; then
        zrb_preflight_fail "$label is not writable: $directory_path"

        return 1
    fi

    zrb_preflight_pass "$label is writable: $directory_path"
}

zrb_preflight_directory() {
    local directory_path=$1
    local label=$2

    if [ ! -d "$directory_path" ]; then
        zrb_preflight_fail "$label does not exist: $directory_path"

        return 1
    fi

    zrb_preflight_pass "$label exists: $directory_path"
}

zrb_preflight_dataset() {
    local dataset_name=$1
    local label=$2

    if ( ! command -v zfs > /dev/null 2>&1 ); then
        return 1
    fi

    if ( ! zfs list -s name "$dataset_name" > /dev/null 2>&1 ); then
        zrb_preflight_fail "$label does not exist or is not accessible: $dataset_name"

        return 1
    fi

    zrb_preflight_pass "$label exists and is accessible: $dataset_name"
}

zrb_preflight_source() {
    local target_name=$1
    local source_file=$2
    local -n source_ref=$target_name

    source_ref=""

    if ( ! zrb_preflight_readable_file "$source_file" "Vault source file" ); then
        return 1
    fi

    source_ref=$(<"$source_file")

    if [ -z "$source_ref" ]; then
        zrb_preflight_fail "Vault source file is empty: $source_file"

        return 1
    fi

    zrb_preflight_pass "Vault source is configured: $source_ref"
}

zrb_preflight_excludes() {
    local parameter_exclude_file=$1
    local vault_exclude_file=$2
    local check_status=0

    if [ -n "$parameter_exclude_file" ]; then
        zrb_preflight_readable_file "$parameter_exclude_file" "Command-line exclude file" || check_status=1
    else
        zrb_preflight_pass "Command-line exclude file is not configured"
    fi

    if [ -f "$vault_exclude_file" ]; then
        zrb_preflight_readable_file "$vault_exclude_file" "Vault exclude file" || check_status=1
    else
        zrb_preflight_pass "Vault exclude file is not configured"
    fi

    if [ -n "$parameter_exclude_file" ] && [ -f "$vault_exclude_file" ]; then
        zrb_preflight_fail "Command-line and vault exclude files are mutually exclusive"
        check_status=1
    fi

    return "$check_status"
}

zrb_preflight_notify_address() {
    local notify_file=$1
    local notify_address

    if [ ! -f "$notify_file" ]; then
        zrb_preflight_pass "Vault notification address is not configured"

        return 0
    fi

    notify_address=$(<"$notify_file")

    if [ -z "$notify_address" ]; then
        zrb_preflight_pass "Vault notification address is not configured"

        return 0
    fi

    if [[ $notify_address != *@* ]]; then
        zrb_preflight_fail "Vault notification address is invalid: $notify_address"

        return 1
    fi

    zrb_preflight_pass "Vault notification address is valid: $notify_address"
}

zrb_preflight_hook() {
    local hook_file=$1

    if [ -f "$hook_file" ]; then
        if ( ! bash -n "$hook_file" ); then
            zrb_preflight_fail "Hook syntax is invalid: $hook_file"

            return 1
        fi

        zrb_preflight_pass "Hook syntax is valid: $hook_file"
    else
        zrb_preflight_pass "Hook is not configured: $hook_file"
    fi
}

zrb_preflight_retention() {
    local mode=$1
    local frequency_list=$2
    local global_config=$3
    local vault_config=$4
    local frequency
    local retention_period
    local minimum_count
    local check_status=0

    if [ "$mode" == "no" ]; then
        zrb_preflight_pass "Retention validation is not required for mode 'no'"

        return 0
    fi

    for frequency in $frequency_list; do
        retention_period=""
        minimum_count=""

        if ( ! zrb_retention_load_config retention_period minimum_count "$frequency" "$global_config" "$vault_config" ); then
            zrb_preflight_fail "Invalid retention configuration for frequency '$frequency'."
            check_status=1
        else
            zrb_preflight_pass "Retention configuration is valid for '$frequency': period '$retention_period', minimum '$minimum_count'"
        fi
    done

    return "$check_status"
}

zrb_preflight_run() {
    local backup_dataset=$1
    local ssh_config=$2
    local global_placeholder_file=$3
    local vault_placeholder_file=$4
    local global_exclude_file=$5
    local parameter_exclude_file=$6
    local vault_log=$7
    local vault_config=$8
    local expiration_mode=$9
    local frequency_list=${10}
    local global_retention_file=${11}
    local vault_root=${vault_config%/config}
    local vault_data="$vault_root/data"
    local vault_dataset=${vault_root#/}
    local source_file="$vault_config/source"
    local source_path=""
    local placeholder_path=""
    local remote_host=""
    local check_status=0
    local source_status=0

    ZRB_PREFLIGHT_PASS_COUNT=0
    ZRB_PREFLIGHT_FAIL_COUNT=0

    zrb_preflight_commands bash date grep mail ps rsync ssh zfs || check_status=1
    zrb_preflight_dataset "$backup_dataset" "Backup dataset" || check_status=1
    zrb_preflight_dataset "$vault_dataset" "Vault dataset" || check_status=1
    zrb_preflight_directory "$vault_root" "Vault directory" || check_status=1
    zrb_preflight_directory "$vault_config" "Vault configuration directory" || check_status=1
    zrb_preflight_directory "$vault_data" "Vault destination directory" || check_status=1
    zrb_preflight_directory "$vault_log" "Vault log directory" || check_status=1
    zrb_preflight_readable_file "$global_exclude_file" "Global exclude file" || check_status=1

    zrb_preflight_excludes "$parameter_exclude_file" "$vault_config/exclude" || check_status=1
    zrb_preflight_notify_address "$vault_config/notify" || check_status=1
    zrb_preflight_writable_directory "$vault_log" "Vault log directory" || check_status=1
    zrb_preflight_source source_path "$source_file" || source_status=1

    if [ "$source_status" -ne 0 ]; then
        check_status=1
    else
        zrb_source_placeholder_path placeholder_path "$source_path" "$global_placeholder_file" "$vault_placeholder_file" || check_status=1

        if [ -n "$placeholder_path" ] && [ ! -e "$placeholder_path" ]; then
            zrb_preflight_fail "Placeholder does not exist: $placeholder_path"
            check_status=1
        elif [ -n "$placeholder_path" ]; then
            zrb_preflight_pass "Local source and placeholder exist: $placeholder_path"
        else
            zrb_preflight_pass "Placeholder validation is not required for a remote source"
        fi

        if ( ! zrb_source_remote_accessible "$source_path" "$ssh_config" ); then
            zrb_preflight_fail "Remote source is not accessible: $source_path"
            check_status=1
        else
            remote_host=$(zrb_source_remote_host "$source_path") || true

            if [ -n "$remote_host" ]; then
                zrb_preflight_pass "Remote source is accessible through SSH: $remote_host"
            else
                zrb_preflight_pass "SSH validation is not required for a local source"
            fi
        fi
    fi

    zrb_preflight_hook "$vault_config/pre-run.sh" || check_status=1
    zrb_preflight_hook "$vault_config/post-run.sh" || check_status=1
    zrb_preflight_retention "$expiration_mode" "$frequency_list" "$global_retention_file" "$vault_config/expire" || check_status=1

    if [ "$check_status" -ne 0 ]; then
        zrb_preflight_summary "$check_status"

        return 1
    fi

    zrb_preflight_summary "$check_status"
}
