#!/bin/bash
# shellcheck disable=SC2034 # Retention values are populated through nameref validation.

zrb_preflight_pass() {
    printf '%bPASS%b: %s\n' "${C_GREEN:-}" "${C_NOCOLOR:-}" "$1"
}

zrb_preflight_fail() {
    printf '%bFAIL%b: %s\n' "${C_RED:-}" "${C_NOCOLOR:-}" "$1"
}

zrb_preflight_commands() {
    local command_name

    for command_name in "$@"; do
        if ( ! command -v "$command_name" > /dev/null 2>&1 ); then
            zrb_preflight_fail "Missing required command: $command_name"

            return 1
        fi

        zrb_preflight_pass "Required command '$command_name'"
    done
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

    if [ "$mode" == "no" ]; then
        zrb_preflight_pass "Retention validation is not required for mode 'no'"

        return 0
    fi

    for frequency in $frequency_list; do
        retention_period=""
        minimum_count=""

        if ( ! zrb_retention_load_config retention_period minimum_count "$frequency" "$global_config" "$vault_config" ); then
            zrb_preflight_fail "Invalid retention configuration for frequency '$frequency'."

            return 1
        fi

        zrb_preflight_pass "Retention configuration is valid for '$frequency': period '$retention_period', minimum '$minimum_count'"
    done
}

zrb_preflight_run() {
    local source_path=$1
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
    local placeholder_path=""
    local remote_host=""

    zrb_preflight_commands bash date grep mail ps rsync ssh zfs || return 1
    zrb_preflight_readable_file "$global_exclude_file" "Global exclude file" || return 1

    if [ -n "$parameter_exclude_file" ]; then
        zrb_preflight_readable_file "$parameter_exclude_file" "Exclude file" || return 1
    else
        zrb_preflight_pass "Command-line exclude file is not configured"
    fi

    zrb_preflight_writable_directory "$vault_log" "Vault log directory" || return 1
    zrb_source_placeholder_path placeholder_path "$source_path" "$global_placeholder_file" "$vault_placeholder_file" || return 1

    if [ -n "$placeholder_path" ] && [ ! -e "$placeholder_path" ]; then
        zrb_preflight_fail "Placeholder does not exist: $placeholder_path"

        return 1
    fi

    if [ -n "$placeholder_path" ]; then
        zrb_preflight_pass "Local source and placeholder exist: $placeholder_path"
    else
        zrb_preflight_pass "Placeholder validation is not required for a remote source"
    fi

    if ( ! zrb_source_remote_accessible "$source_path" "$ssh_config" ); then
        zrb_preflight_fail "Remote source is not accessible: $source_path"

        return 1
    fi

    remote_host=$(zrb_source_remote_host "$source_path") || true

    if [ -n "$remote_host" ]; then
        zrb_preflight_pass "Remote source is accessible through SSH: $remote_host"
    else
        zrb_preflight_pass "SSH validation is not required for a local source"
    fi

    zrb_preflight_hook "$vault_config/pre-run.sh" || return 1
    zrb_preflight_hook "$vault_config/post-run.sh" || return 1
    zrb_preflight_retention "$expiration_mode" "$frequency_list" "$global_retention_file" "$vault_config/expire" || return 1

    printf '\nPreflight check passed.\n\n'
}
