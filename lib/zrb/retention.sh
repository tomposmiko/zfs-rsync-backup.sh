#!/bin/bash
# shellcheck disable=SC2034 # Retention settings are loaded dynamically and accessed by indirect name.

zrb_retention_is_only_mode() {
    local mode=$1

    [ "$mode" == "only" ]
}

zrb_retention_runs_after_snapshot() {
    local mode=$1

    [ "$mode" == "yes" ]
}

zrb_retention_apply() {
    local dataset=$1
    local prefix=$2
    local frequency=$3
    local retention_period=$4
    local minimum_count=$5
    local expiration_epoch
    local snapshot_output
    local full_snapshot_name
    local snapshot_name
    local snapshot_timestamp
    local snapshot_epoch
    local remaining_count
    local -a matching_snapshots=()

    if [[ ! $minimum_count =~ ^[0-9]+$ ]]; then
        return 1
    fi

    expiration_epoch=$(date "+%s" -d "$retention_period ago") || return 1
    snapshot_output=$(zfs list -t snap -r -H "$dataset" -o name -s name) || return 1

    while IFS= read -r full_snapshot_name; do
        snapshot_name=${full_snapshot_name#*@}

        if [[ $snapshot_name != "${prefix}_${frequency}_"* ]]; then
            continue
        fi

        snapshot_timestamp=${snapshot_name#"${prefix}_${frequency}_"}

        if [[ ! $snapshot_timestamp =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}--[0-9]{2}-[0-9]{2}$ ]]; then
            continue
        fi

        matching_snapshots+=("$snapshot_name")
    done <<< "$snapshot_output"

    remaining_count=${#matching_snapshots[@]}

    for snapshot_name in "${matching_snapshots[@]}"; do
        if [ "$remaining_count" -le "$minimum_count" ]; then
            break
        fi

        snapshot_timestamp=${snapshot_name#"${prefix}_${frequency}_"}
        snapshot_timestamp=${snapshot_timestamp/--/ }
        snapshot_timestamp=${snapshot_timestamp%-*}:${snapshot_timestamp##*-}
        snapshot_epoch=$(date "+%s" -d "$snapshot_timestamp") || return 1

        if [ "$snapshot_epoch" -ge "$expiration_epoch" ]; then
            continue
        fi

        f_say "$C_GREEN  ${dataset}@${snapshot_name}"

        if ! { zfs destroy "${dataset}@${snapshot_name}"; }; then
            return 1
        fi

        remaining_count=$((remaining_count - 1))
    done
}

zrb_retention_load_config() {
    local period_target_name=$1
    local minimum_target_name=$2
    local frequency=$3
    local global_config=$4
    local vault_config=$5
    local -n period_ref=$period_target_name
    local -n minimum_ref=$minimum_target_name
    local retention_name="expire_${frequency}"
    local minimum_name="least_keep_count_${frequency}"
    local expire_hourly
    local expire_daily
    local expire_weekly
    local expire_monthly
    local least_keep_count_hourly
    local least_keep_count_daily
    local least_keep_count_weekly
    local least_keep_count_monthly

    if [ ! -f "$global_config" ]; then
        return 1
    fi

    # shellcheck disable=SC1090
    source "$global_config"

    if [ -f "$vault_config" ]; then
        # shellcheck disable=SC1090
        source "$vault_config"
    fi

    period_ref=${!retention_name:-}
    minimum_ref=${!minimum_name:-}

    if [ -z "$period_ref" ] || [[ ! $minimum_ref =~ ^[0-9]+$ ]]; then
        return 1
    fi
}

zrb_retention_run() {
    local dataset=$1
    local prefix=$2
    local frequency=$3
    local global_config=$4
    local vault_config=$5
    local vault_name=$6
    local notify_address=$7
    local retention_period=""
    local minimum_count=""
    local config_status

    zrb_retention_load_config retention_period minimum_count "$frequency" "$global_config" "$vault_config"
    config_status=$?

    if [ "$config_status" -ne 0 ]; then
        echo "Invalid retention configuration for frequency '$frequency'." | mail -s "zrb.sh ERROR: $vault_name" "$notify_address"
        f_say "$C_RED Invalid retention configuration for frequency '$frequency'."

        return 1
    fi

    zrb_retention_apply "$dataset" "$prefix" "$frequency" "$retention_period" "$minimum_count"
}
