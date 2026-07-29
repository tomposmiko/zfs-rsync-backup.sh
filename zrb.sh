#!/bin/bash
# set -x

ZRB_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

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

zrb_main() {
    zrb_config_defaults
    zrb_output_init

    f_process_args "$@"

    ################# validate global config directory #####################
    if ( ! zrb_config_set_global_paths ); then
        echo "configdir does not start with /" | mail -s "zrb.sh ERROR: $vault" "$email_notify_address"
        f_say "$C_RED configdir does not start with /"

        exit 1
    fi
    ################# validate global config directory #####################


    zrb_config_load_backup_dataset
    zrb_config_set_vault_paths "$vault"

    f_check_email_notify_address() {
        if [ -f "$global_notify_address" ]; then
            email_notify_address=$(cat "$global_notify_address")
        else
            email_notify_address="root"
        fi
    }

    f_check_email_notify_address

    vault_root="/$BACKUP_DATASET/$vault"
    vault_dataset="$BACKUP_DATASET/$vault"

    if [ -n "${data_source:-}" ]; then
        zrb_vault_create "$BACKUP_DATASET" "$vault" "$data_source" || exit 1

        exit 0
    fi

    if [ -n "${vault_to_list:-}" ]; then
        zrb_vault_list "$BACKUP_DATASET" "$vault_to_list" "$email_notify_address" || exit 1

        exit 0
    fi

    zrb_vault_validate "$vault_dataset" "$vault_root" "$backup_vault_conf" "$backup_vault_dest" "$backup_vault_log" "$vault" "$email_notify_address" || exit 1

    if ( zrb_vault_is_disabled "$backup_vault_conf" ); then
        exit 0
    fi

    zrb_vault_load_source backup_source "$backup_vault_conf" "$vault" "$email_notify_address" || exit 1
    export backup_source

    rsync_exclude_param=""
    rsync_exclude_file=""

    zrb_vault_resolve_excludes rsync_exclude_param rsync_exclude_file "${backup_exclude_param:-}" "$backup_vault_conf" || exit 1

    zrb_vault_add_notify_address email_notify_address "$backup_vault_conf" || exit 1

    f_check_placeholder() {
        # check if there is a specific file available to make sure, fs is mounted if its a network share (nfs, samba etc.)
        if ( echo "$backup_source" | grep -q -Eo ^"/" ); then
            file_placeholder=""
            [ -e "$global_placeholder" ] && file_placeholder=$(cat "$global_placeholder")
            [ -f "$backup_vault_conf/placeholder" ] && file_placeholder=$(cat "$backup_vault_conf/placeholder")

            if [ ! -e "$backup_source/$file_placeholder" ]; then
                echo "Placeholder file defined but does not exist: $backup_source/$file_placeholder !" | mail -s "zrb.sh ERROR: $vault" "$email_notify_address"
                f_say "$C_RED Placeholder file defined but does not exist: $backup_source/$file_placeholder !"
                f_say "$C_RED Filesystem is not mounted?"

                exit 1
            fi
        fi
    }

    ################ pre-run script ######################
    #if [ -f "$backup_vault_conf/pre-run.sh" ];
    #  then
    #    bash $backup_vault_conf/pre-run.sh
    #fi
    ################ pre-run script ######################

    if ( zrb_retention_is_only_mode "$expire" ); then
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

    f_pre_run_script() {
        #echo "DEBUG: backup_host - f_pre_run_script: $backup_host"
        pre_run_script="/$BACKUP_DATASET/$vault/config/pre-run.sh"

        if [ -f "$pre_run_script" ]; then
            bash "$pre_run_script"
        fi
    }

    f_post_run_script() {
        #echo "DEBUG: backup_host - f_post_run_script: $backup_host"
        post_run_script="/$BACKUP_DATASET/$vault/config/post-run.sh"

        if [ -f "$post_run_script" ]; then
            bash "$post_run_script"
        fi
    }

    ################## doing rsync ####################
    lockfile="$backup_vault_log/lock"
    file_finished="/$BACKUP_DATASET/$vault/FINISHED"
    ssh_config=$(zrb_source_ssh_config "$backup_vault_conf/ssh")

    zrb_source_check_remote_access "$backup_source" "$ssh_config" "$vault" "$email_notify_address" || exit 1
    f_check_placeholder
    zrb_lock_create "$lockfile" "$(basename "$0")" "$vault" "$email_notify_address" || exit 1

    #echo "DEBUG: backup_host - before f_pre_run_script: $backup_host"
    f_pre_run_script
    zrb_completion_begin "$file_finished" "$vault" "$email_notify_address"

    ############################### rsync ################################
    f_say "$C_GREEN VAULT:$C_BLUE $vault"

    date_start_epoch=$(date '+%s')
    date_start_human=$(date -d "@$date_start_epoch" '+%Y-%m-%d %H:%M')

    echo -e "BEGIN:\t$date_start_human" > "$backup_vault_log/report.txt"

    if [ "$QUIET_NOTIFICATIONS" -eq 1 ]; then
        zrb_rsync_run "$backup_source" "$backup_vault_dest" "$ssh_config" rsync_args > /dev/null
    else
        f_say "$C_GREEN  START:$C_BLUE $date_start_human"
        zrb_rsync_run "$backup_source" "$backup_vault_dest" "$ssh_config" rsync_args
    fi

    rsync_ret=$?
    ############################### rsync ################################

    f_post_run_script

    date_finish_epoch=$(date '+%s')
    date_finish_human=$(date -d "@$date_finish_epoch" '+%Y-%m-%d %H:%M')

    echo -e "FINISH:\t$date_finish_human" >> "$backup_vault_log/report.txt"

    if [ "$QUIET_NOTIFICATIONS" -eq 0 ]; then
        f_say "$C_GREEN  FINISH:$C_BLUE $date_finish_human"
    fi

    duetime_epoch=$(("$date_finish_epoch" - "$date_start_epoch"))
    duetime_human=$(printf '%d day(s) %02d:%02d:%02d\n' $((duetime_epoch/86400)) $((duetime_epoch/3600%24)) $((duetime_epoch/60%60)) $((duetime_epoch%60)))

    echo "DELTA: $duetime_human ($duetime_epoch sec)" >> "$backup_vault_log/report.txt"

    if [ "$QUIET_NOTIFICATIONS" -eq 0 ]; then
        f_say "$C_GREEN  DELTA:$C_BLUE $duetime_human"
    fi

    zrb_lock_remove "$lockfile"

    if [ "$rsync_ret" -ne 0 ]; then
        echo "rsync exited with non-zero status code: $rsync_ret !" | mail -s "$HOSTNAME zrb.sh ERROR: $vault" "$email_notify_address"
        f_say "$C_RED rsync exited with non-zero status code!"

        exit 1
    fi

    zrb_completion_mark_success "$file_finished" "$rsync_ret"
    ################## doing rsync ####################

    for freq_type in $FREQ_LIST; do
        zrb_snapshot_create "$vault_dataset" "$SNAPSHOT_PREFIX" "$freq_type" "$ZRB_RUN_DATE" || exit 1

        if ( zrb_retention_runs_after_snapshot "$expire" ); then
            zrb_retention_run "$vault_dataset" "$SNAPSHOT_PREFIX" "$freq_type" "$global_expire" "$backup_vault_conf/expire" "$vault" "$email_notify_address" || exit 1
        fi
    done

    echo
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    zrb_main "$@"
fi
