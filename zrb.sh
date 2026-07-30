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

    zrb_main_cleanup "$status"

    exit "$status"
}

zrb_main() {
    local config_status
    local parse_status

    zrb_config_defaults
    zrb_output_init

    zrb_cli_parse "$@"
    parse_status=$?

    if [ "$parse_status" -eq 2 ]; then
        return 0
    fi

    if [ "$parse_status" -ne 0 ]; then
        return "$parse_status"
    fi

    ################# validate global config directory #####################
    zrb_config_set_global_paths
    config_status=$?

    if [ "$config_status" -ne 0 ]; then
        if [ "$CHECK_ONLY" -eq 0 ]; then
            echo "configdir does not start with /" | mail -s "zrb.sh ERROR: $vault" "$email_notify_address"
        fi

        f_say "$C_RED configdir does not start with /"

        exit 1
    fi
    ################# validate global config directory #####################


    zrb_config_load_backup_dataset
    zrb_config_set_vault_paths "$vault"
    zrb_config_load_notify_address email_notify_address "$global_notify_address"

    vault_root="/$BACKUP_DATASET/$vault"
    vault_dataset="$BACKUP_DATASET/$vault"
    operation_notify_address=$email_notify_address

    if [ "$CHECK_ONLY" -eq 1 ]; then
        operation_notify_address=""
    fi

    if [ -n "${data_source:-}" ]; then
        zrb_vault_create "$BACKUP_DATASET" "$vault" "$data_source" || exit 1

        exit 0
    fi

    if [ -n "${vault_to_list:-}" ]; then
        zrb_vault_list "$BACKUP_DATASET" "$vault_to_list" "$email_notify_address" || exit 1

        exit 0
    fi

    ssh_config=$(zrb_source_ssh_config "$backup_vault_conf/ssh")

    if [ "$CHECK_ONLY" -eq 1 ]; then
        zrb_preflight_run "$BACKUP_DATASET" "$ssh_config" "$global_placeholder" "$backup_vault_conf/placeholder" "$global_exclude" "${backup_exclude_param:-}" "$backup_vault_log" "$backup_vault_conf" "$expire" "$FREQ_LIST" "$global_expire" || exit 1

        exit 0
    fi

    zrb_vault_validate "$vault_dataset" "$vault_root" "$backup_vault_conf" "$backup_vault_dest" "$backup_vault_log" "$vault" "$operation_notify_address" || exit 1

    if { zrb_vault_is_disabled "$backup_vault_conf"; }; then
        exit 0
    fi

    zrb_vault_load_source backup_source "$backup_vault_conf" "$vault" "$operation_notify_address" || exit 1
    export backup_source

    rsync_exclude_param=""
    rsync_exclude_file=""

    zrb_vault_resolve_excludes rsync_exclude_param rsync_exclude_file "${backup_exclude_param:-}" "$backup_vault_conf" || exit 1

    zrb_vault_add_notify_address email_notify_address "$backup_vault_conf" || exit 1

    if { zrb_retention_is_only_mode "$expire"; }; then
        for freq_type in $FREQ_LIST; do
            zrb_retention_run "$vault_dataset" "$SNAPSHOT_PREFIX" "$freq_type" "$global_expire" "$backup_vault_conf/expire" "$vault" "$email_notify_address" || exit 1
        done

        exit 0
    fi

    # remove old log file
    rm -f "$backup_vault_log/rsync.log"

    # rsync parameters
    # shellcheck disable=SC2034 # The array is passed by name to the rsync module.
    rsync_args=()
    zrb_rsync_build_args rsync_args "$backup_vault_log/rsync.log" "$global_exclude" "$rsync_exclude_param" "$rsync_exclude_file"

    ################## doing rsync ####################
    lockfile="$backup_vault_log/lock"
    file_finished="/$BACKUP_DATASET/$vault/FINISHED"
    file_running="/$BACKUP_DATASET/$vault/RUNNING"
    file_failed="/$BACKUP_DATASET/$vault/FAILED"
    report_file="$backup_vault_log/report.txt"

    f_say "$C_GREEN    VAULT:$C_BLUE $vault"

    zrb_source_check_remote_access "$backup_source" "$ssh_config" "$vault" "$email_notify_address" || exit 1
    zrb_source_validate_placeholder "$backup_source" "$global_placeholder" "$backup_vault_conf/placeholder" "$vault" "$email_notify_address" || exit 1
    zrb_lock_create "$lockfile" "$(basename "$0")" "$vault" "$email_notify_address" || exit 1

    ZRB_ACTIVE_LOCK_FILE=$lockfile
    ZRB_RUNNING_FILE=$file_running
    ZRB_FAILED_FILE=$file_failed
    ZRB_CLEANUP_ARMED=1

    trap 'zrb_main_cleanup $?' EXIT
    trap 'zrb_main_handle_signal 130' INT
    trap 'zrb_main_handle_signal 143' TERM

    zrb_completion_begin "$file_finished" "$file_running" "$file_failed" "$vault" "$email_notify_address"
    zrb_hook_run "$backup_vault_conf/pre-run.sh"

    ############################### rsync ################################
    date_start_epoch=0
    zrb_report_begin date_start_epoch "$report_file" "$QUIET_NOTIFICATIONS"

    if [ "$QUIET_NOTIFICATIONS" -eq 1 ]; then
        zrb_rsync_run "$backup_source" "$backup_vault_dest" "$ssh_config" rsync_args > /dev/null
    else
        zrb_rsync_run "$backup_source" "$backup_vault_dest" "$ssh_config" rsync_args
    fi

    rsync_ret=$?
    ############################### rsync ################################

    zrb_hook_run "$backup_vault_conf/post-run.sh"
    zrb_report_finish "$report_file" "$date_start_epoch" "$QUIET_NOTIFICATIONS"

    if [ "$rsync_ret" -ne 0 ]; then
        echo "rsync exited with non-zero status code: $rsync_ret !" | mail -s "$HOSTNAME zrb.sh ERROR: $vault" "$email_notify_address"
        f_say "$C_RED rsync exited with non-zero status code!"

        exit 1
    fi

    zrb_completion_mark_success "$file_finished" "$file_running" "$file_failed" "$rsync_ret"
    zrb_lock_remove "$lockfile"
    ZRB_CLEANUP_ARMED=0

    trap - EXIT INT TERM
    ################## doing rsync ####################

    for freq_type in $FREQ_LIST; do
        zrb_snapshot_create "$vault_dataset" "$SNAPSHOT_PREFIX" "$freq_type" "$ZRB_RUN_DATE" || exit 1

        if { zrb_retention_runs_after_snapshot "$expire"; }; then
            zrb_retention_run "$vault_dataset" "$SNAPSHOT_PREFIX" "$freq_type" "$global_expire" "$backup_vault_conf/expire" "$vault" "$email_notify_address" || exit 1
        fi
    done
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    zrb_main "$@"
fi
