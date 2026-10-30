#!/bin/bash
# set -x

ZRB_SCRIPT_PATH=${BASH_SOURCE[0]}

while [ -L "$ZRB_SCRIPT_PATH" ]; do
    ZRB_SCRIPT_DIR=$(cd -P "$(dirname "$ZRB_SCRIPT_PATH")" && pwd)
    ZRB_SCRIPT_PATH=$(readlink "$ZRB_SCRIPT_PATH")

    if [[ $ZRB_SCRIPT_PATH != /* ]]; then
        ZRB_SCRIPT_PATH="$ZRB_SCRIPT_DIR/$ZRB_SCRIPT_PATH"
    fi
done

ZRB_ROOT=$(cd -P "$(dirname "$ZRB_SCRIPT_PATH")" && pwd)

# shellcheck source=lib/zrb/version.sh
source "$ZRB_ROOT/lib/zrb/version.sh"

# shellcheck source=lib/zrb/config.sh
source "$ZRB_ROOT/lib/zrb/config.sh"

# shellcheck source=lib/zrb/output.sh
source "$ZRB_ROOT/lib/zrb/output.sh"

# shellcheck source=lib/zrb/cli.sh
source "$ZRB_ROOT/lib/zrb/cli.sh"

# shellcheck source=lib/zrb/lock.sh
source "$ZRB_ROOT/lib/zrb/lock.sh"

# shellcheck source=lib/zrb/completion.sh
source "$ZRB_ROOT/lib/zrb/completion.sh"

# shellcheck source=lib/zrb/source.sh
source "$ZRB_ROOT/lib/zrb/source.sh"

# shellcheck source=lib/zrb/rsync.sh
source "$ZRB_ROOT/lib/zrb/rsync.sh"

# shellcheck source=lib/zrb/vault.sh
source "$ZRB_ROOT/lib/zrb/vault.sh"

# shellcheck source=lib/zrb/snapshot.sh
source "$ZRB_ROOT/lib/zrb/snapshot.sh"

# shellcheck source=lib/zrb/retention.sh
source "$ZRB_ROOT/lib/zrb/retention.sh"

# shellcheck source=lib/zrb/hooks.sh
source "$ZRB_ROOT/lib/zrb/hooks.sh"

# shellcheck source=lib/zrb/report.sh
source "$ZRB_ROOT/lib/zrb/report.sh"

# shellcheck source=lib/zrb/preflight.sh
source "$ZRB_ROOT/lib/zrb/preflight.sh"

zrb_main_cleanup() {
    local status=$1

    if [ "${ZRB_CLEANUP_ARMED:-0}" -eq 1 ]; then
        zrb_completion_mark_failed "$ZRB_RUNNING_FILE" "$ZRB_FAILED_FILE"
        zrb_lock_remove "$ZRB_ACTIVE_LOCK_FILE"
    fi

    return "$status"
}

zrb_main_handle_signal() {
    local status=$1

    trap - EXIT
    trap '' INT TERM

    zrb_main_cleanup "$status" || true

    exit "$status"
}

zrb_main() {
    local backup_source
    local config_status
    local date_start_epoch
    local file_failed
    local file_finished
    local file_running
    local freq_type
    local hook_status
    local lockfile
    local operation_notify_address
    local parse_status
    local report_file
    local retention_preview
    local rsync_exclude_file
    local rsync_exclude_param
    local rsync_ret
    local ssh_config
    local vault_dataset
    local vault_root
    # shellcheck disable=SC2034 # The array is passed by name to the rsync module.
    local -a rsync_args=()

    zrb_config_defaults
    zrb_output_init

    if { zrb_cli_parse "$@"; }; then
        parse_status=0
    else
        parse_status=$?
    fi

    if [ "$parse_status" -eq 2 ]; then
        return 0
    fi

    if [ "$parse_status" -ne 0 ]; then
        return "$parse_status"
    fi

    ################# validate global config directory #####################
    if { zrb_config_set_global_paths; }; then
        config_status=0
    else
        config_status=$?
    fi

    if [ "$config_status" -ne 0 ]; then
        if [ "$CHECK_ONLY" -eq 0 ]; then
            echo "configdir does not start with /" | mail -s "zrb.sh ERROR: $VAULT" "$EMAIL_NOTIFY_ADDRESS" || true
        fi

        f_say "$C_RED configdir does not start with /"

        exit 1
    fi
    ################# validate global config directory #####################


    zrb_config_load_backup_dataset
    zrb_config_set_vault_paths "$VAULT"
    zrb_config_load_notify_address EMAIL_NOTIFY_ADDRESS "$GLOBAL_NOTIFY_ADDRESS"

    vault_root="/$BACKUP_DATASET/$VAULT"
    vault_dataset="$BACKUP_DATASET/$VAULT"
    operation_notify_address=$EMAIL_NOTIFY_ADDRESS

    if [ "$CHECK_ONLY" -eq 1 ]; then
        operation_notify_address=""
    fi

    if [ -n "${DATA_SOURCE:-}" ]; then
        zrb_vault_create "$BACKUP_DATASET" "$VAULT" "$DATA_SOURCE" || exit 1

        exit 0
    fi

    if [ -n "${VAULT_TO_LIST:-}" ]; then
        zrb_vault_list "$BACKUP_DATASET" "$VAULT_TO_LIST" "$EMAIL_NOTIFY_ADDRESS" || exit 1

        exit 0
    fi

    ssh_config=$(zrb_source_ssh_config "$BACKUP_VAULT_CONF/ssh")

    if [ "$CHECK_ONLY" -eq 1 ]; then
        zrb_preflight_run "$BACKUP_DATASET" "$ssh_config" "$GLOBAL_PLACEHOLDER" "$BACKUP_VAULT_CONF/placeholder" "$GLOBAL_EXCLUDE" "${BACKUP_EXCLUDE_PARAM:-}" "$BACKUP_VAULT_LOG" "$BACKUP_VAULT_CONF" "$EXPIRE_MODE" "$FREQ_LIST" "$GLOBAL_EXPIRE" || exit 1

        exit 0
    fi

    zrb_vault_validate "$vault_dataset" "$vault_root" "$BACKUP_VAULT_CONF" "$BACKUP_VAULT_DEST" "$BACKUP_VAULT_LOG" "$VAULT" "$operation_notify_address" || exit 1

    if { zrb_vault_is_disabled "$BACKUP_VAULT_CONF"; }; then
        exit 0
    fi

    zrb_vault_load_source backup_source "$BACKUP_VAULT_CONF" "$VAULT" "$operation_notify_address" || exit 1
    export backup_source

    rsync_exclude_param=""
    rsync_exclude_file=""

    zrb_vault_resolve_excludes rsync_exclude_param rsync_exclude_file "${BACKUP_EXCLUDE_PARAM:-}" "$BACKUP_VAULT_CONF" || exit 1

    zrb_vault_add_notify_address EMAIL_NOTIFY_ADDRESS "$BACKUP_VAULT_CONF" || exit 1

    if { zrb_retention_runs_without_backup "$EXPIRE_MODE"; }; then
        retention_preview=0

        if { zrb_retention_is_preview_mode "$EXPIRE_MODE"; }; then
            retention_preview=1
        fi

        for freq_type in $FREQ_LIST; do
            zrb_retention_run "$vault_dataset" "$SNAPSHOT_PREFIX" "$freq_type" "$GLOBAL_EXPIRE" "$BACKUP_VAULT_CONF/expire" "$VAULT" "$EMAIL_NOTIFY_ADDRESS" "$retention_preview" || exit 1
        done

        exit 0
    fi

    # remove old log file
    rm -f "$BACKUP_VAULT_LOG/rsync.log"

    # rsync parameters
    zrb_rsync_build_args rsync_args "$BACKUP_VAULT_LOG/rsync.log" "$GLOBAL_EXCLUDE" "$rsync_exclude_param" "$rsync_exclude_file"

    ################## doing rsync ####################
    lockfile="$BACKUP_VAULT_LOG/lock"
    file_finished="/$BACKUP_DATASET/$VAULT/FINISHED"
    file_running="/$BACKUP_DATASET/$VAULT/RUNNING"
    file_failed="/$BACKUP_DATASET/$VAULT/FAILED"
    report_file="$BACKUP_VAULT_LOG/report.txt"

    f_say "$C_GREEN    VAULT:$C_BLUE $VAULT"

    zrb_source_check_remote_access "$backup_source" "$ssh_config" "$VAULT" "$EMAIL_NOTIFY_ADDRESS" || exit 1
    zrb_source_validate_placeholder "$backup_source" "$GLOBAL_PLACEHOLDER" "$BACKUP_VAULT_CONF/placeholder" "$VAULT" "$EMAIL_NOTIFY_ADDRESS" || exit 1
    zrb_lock_create "$lockfile" "$(basename "$0")" "$VAULT" "$EMAIL_NOTIFY_ADDRESS" || exit 1

    ZRB_ACTIVE_LOCK_FILE=$lockfile
    ZRB_RUNNING_FILE=$file_running
    ZRB_FAILED_FILE=$file_failed
    ZRB_CLEANUP_ARMED=1

    trap 'zrb_main_cleanup $?' EXIT
    trap 'zrb_main_handle_signal 130' INT
    trap 'zrb_main_handle_signal 143' TERM

    zrb_completion_begin "$file_finished" "$file_running" "$file_failed" "$VAULT" "$EMAIL_NOTIFY_ADDRESS"
    if { zrb_hook_run "$BACKUP_VAULT_CONF/pre-run.sh"; }; then
        hook_status=0
    else
        hook_status=$?
    fi

    if [ "$hook_status" -ne 0 ]; then
        f_say "${C_RED:-}        ERROR:${C_NOCOLOR:-} Pre-run hook failed with status $hook_status."

        exit 1
    fi

    ############################### rsync ################################
    date_start_epoch=0
    zrb_report_begin date_start_epoch "$report_file" "$QUIET_NOTIFICATIONS"

    if [ "$QUIET_NOTIFICATIONS" -eq 1 ]; then
        if { zrb_rsync_run "$backup_source" "$BACKUP_VAULT_DEST" "$ssh_config" rsync_args > /dev/null; }; then
            rsync_ret=0
        else
            rsync_ret=$?
        fi
    else
        if { zrb_rsync_run "$backup_source" "$BACKUP_VAULT_DEST" "$ssh_config" rsync_args; }; then
            rsync_ret=0
        else
            rsync_ret=$?
        fi
    fi
    ############################### rsync ################################

    if { zrb_hook_run "$BACKUP_VAULT_CONF/post-run.sh"; }; then
        hook_status=0
    else
        hook_status=$?
    fi

    zrb_report_finish "$report_file" "$date_start_epoch" "$QUIET_NOTIFICATIONS"

    if [ "$rsync_ret" -ne 0 ]; then
        echo "rsync exited with non-zero status code: $rsync_ret !" | mail -s "$HOSTNAME zrb.sh ERROR: $VAULT" "$EMAIL_NOTIFY_ADDRESS" || true
        f_say "$C_RED rsync exited with non-zero status code!"

        exit 1
    fi

    if [ "$hook_status" -ne 0 ]; then
        f_say "${C_RED:-}        ERROR:${C_NOCOLOR:-} Post-run hook failed with status $hook_status."

        exit 1
    fi

    for freq_type in $FREQ_LIST; do
        zrb_snapshot_create "$vault_dataset" "$SNAPSHOT_PREFIX" "$freq_type" "$ZRB_RUN_DATE" || exit 1

        if { zrb_retention_runs_after_snapshot "$EXPIRE_MODE"; }; then
            zrb_retention_run "$vault_dataset" "$SNAPSHOT_PREFIX" "$freq_type" "$GLOBAL_EXPIRE" "$BACKUP_VAULT_CONF/expire" "$VAULT" "$EMAIL_NOTIFY_ADDRESS" || exit 1
        fi
    done

    zrb_completion_mark_success "$file_finished" "$file_running" "$file_failed" "$rsync_ret"
    zrb_lock_remove "$lockfile"

    ZRB_CLEANUP_ARMED=0

    trap - EXIT INT TERM
    ################## doing rsync ####################
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    set -euo pipefail

    zrb_main "$@"
fi
