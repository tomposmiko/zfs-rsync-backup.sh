#!/bin/bash
# shellcheck disable=SC2034 # This sourced module initializes state consumed by zrb.sh.

zrb_config_defaults() {
    BACKUP_DATASET="tank/zrb"
    PATH=${ZRB_COMMAND_PATH:-"/root/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"}
    ZRB_RUN_DATE=$(date "+%Y-%m-%d--%H-%M")

    GLOBAL_CONFIG_DIR="/etc/zrb"
    SNAPSHOT_PREFIX="zrb"
    FREQ_LIST="daily"
    expire="no"
    QUIET_NOTIFICATIONS=1
    INTERACTIVE_SESSION=0
    CHECK_ONLY=0
    email_notify_address="root"

    export PATH
}

zrb_config_set_global_paths() {
    [[ $GLOBAL_CONFIG_DIR == /* ]] || return 1

    global_exclude="$GLOBAL_CONFIG_DIR/exclude"
    global_expire="$GLOBAL_CONFIG_DIR/expire"
    global_placeholder="$GLOBAL_CONFIG_DIR/placeholder"
    global_notify_address="$GLOBAL_CONFIG_DIR/notify_address"
}

zrb_config_load_backup_dataset() {
    local dataset_file="$GLOBAL_CONFIG_DIR/backup_dataset"
    local legacy_dataset_file="$GLOBAL_CONFIG_DIR/BACKUP_DATASET"

    if [[ -f $dataset_file ]]; then
        BACKUP_DATASET=$(<"$dataset_file")
    elif [[ -f $legacy_dataset_file ]]; then
        BACKUP_DATASET=$(<"$legacy_dataset_file")
    fi

    export BACKUP_DATASET
}

zrb_config_load_notify_address() {
    local target_name=$1
    local notify_file=$2
    local -n notify_ref=$target_name

    if [ -f "$notify_file" ]; then
        notify_ref=$(<"$notify_file")
    else
        notify_ref="root"
    fi
}

zrb_config_set_vault_paths() {
    local vault_name=$1

    backup_vault_dest="/$BACKUP_DATASET/$vault_name/data"
    backup_vault_conf="/$BACKUP_DATASET/$vault_name/config"
    backup_vault_log="/$BACKUP_DATASET/$vault_name/log"

    export backup_vault_dest backup_vault_conf backup_vault_log
}
