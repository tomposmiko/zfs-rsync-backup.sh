#!/bin/bash

ZRB_SCRIPT_PATH=${BASH_SOURCE[0]}

while [ -L "$ZRB_SCRIPT_PATH" ]; do
    ZRB_SCRIPT_DIR=$(cd -P "$(dirname "$ZRB_SCRIPT_PATH")" && pwd)
    ZRB_SCRIPT_PATH=$(readlink "$ZRB_SCRIPT_PATH")

    if [[ $ZRB_SCRIPT_PATH != /* ]]; then
        ZRB_SCRIPT_PATH="$ZRB_SCRIPT_DIR/$ZRB_SCRIPT_PATH"
    fi
done

ZRB_ROOT=$(cd -P "$(dirname "$ZRB_SCRIPT_PATH")" && pwd)

# shellcheck source=lib/zrb/config.sh
source "$ZRB_ROOT/lib/zrb/config.sh"

# shellcheck source=lib/zrb/output.sh
source "$ZRB_ROOT/lib/zrb/output.sh"

# shellcheck source=lib/zrb/lock.sh
source "$ZRB_ROOT/lib/zrb/lock.sh"

# shellcheck source=lib/zrb/parallel.sh
source "$ZRB_ROOT/lib/zrb/parallel.sh"

zrb_parallel_main() {
    local parse_status
    local lock_file
    local vaults_file
    local run_status
    local script_basename

    zrb_config_defaults
    zrb_parallel_defaults
    zrb_output_init

    zrb_parallel_parse_args "$@"
    parse_status=$?

    if [ "$parse_status" -eq 2 ]; then
        return 0
    fi

    if [ "$parse_status" -ne 0 ]; then
        return "$parse_status"
    fi

    zrb_config_load_backup_dataset

    script_basename=${0##*/}
    lock_file="/var/run/${script_basename}.lock"
    vaults_file=$(mktemp /tmp/zrb-vaults.XXXXXX) || return 1
    ZRB_PARALLEL_VAULTS_FILE=$vaults_file

    trap zrb_parallel_cleanup_temp EXIT

    zrb_parallel_lock_create "$lock_file" "$script_basename" || return 1

    if ! { zrb_parallel_list_vaults "$BACKUP_DATASET" > "$vaults_file"; }; then
        zrb_lock_remove "$lock_file"

        return 1
    fi

    zrb_parallel_print_timestamp "BEGIN: "
    echo

    zrb_parallel_run_jobs "$vaults_file" "$PARALLEL_JOBS" "$FREQ_LIST"
    run_status=$?

    echo
    zrb_parallel_print_timestamp "FINISH: "

    zrb_lock_remove "$lock_file"

    return "$run_status"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    zrb_parallel_main "$@"
fi
