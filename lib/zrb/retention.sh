#!/bin/bash

zrb_retention_is_only_mode() {
    local mode=$1

    [ "$mode" == "only" ]
}

zrb_retention_runs_after_snapshot() {
    local mode=$1

    [ "$mode" == "yes" ]
}

zrb_retention_value_is_valid() {
    local key=$1
    local value=$2

    case "$key" in
        expire_hourly|expire_daily|expire_weekly|expire_monthly)
            [[ $value =~ ^[1-9][0-9]*[[:space:]]+(hour|hours|day|days|week|weeks|month|months|year|years)$ ]]
            ;;
        least_keep_count_hourly|least_keep_count_daily|least_keep_count_weekly|least_keep_count_monthly)
            [[ $value =~ ^[0-9]+$ ]]
            ;;
        *)
            return 1
            ;;
    esac
}

zrb_retention_parse_config() {
    local config_file=$1
    local retention_name=$2
    local minimum_name=$3
    local period_target_name=$4
    local minimum_target_name=$5
    local -n period_ref=$period_target_name
    local -n minimum_ref=$minimum_target_name
    local line
    local key
    local value

    while IFS= read -r line || [ -n "$line" ]; do
        line=${line%$'\r'}

        if [[ $line =~ ^[[:space:]]*$ ]] || [[ $line =~ ^[[:space:]]*# ]]; then
            continue
        fi

        if [[ ! $line =~ ^[[:space:]]*([a-z_]+)[[:space:]]*=(.*)$ ]]; then
            return 1
        fi

        key=${BASH_REMATCH[1]}
        value=${BASH_REMATCH[2]}
        value=${value#"${value%%[![:space:]]*}"}
        value=${value%"${value##*[![:space:]]}"}

        if [[ $value == \"*\" ]] && [ "${#value}" -ge 2 ]; then
            value=${value:1:${#value}-2}
        elif [[ $value == \'*\' ]] && [ "${#value}" -ge 2 ]; then
            value=${value:1:${#value}-2}
        elif [[ $value == *\"* ]] || [[ $value == *\'* ]]; then
            return 1
        fi

        if ! { zrb_retention_value_is_valid "$key" "$value"; }; then
            return 1
        fi

        if [ "$key" == "$retention_name" ]; then
            period_ref=$value
        elif [ "$key" == "$minimum_name" ]; then
            minimum_ref=$value
        fi
    done < "$config_file"
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

        f_say "$C_GREEN        EXPIRED:${C_BLUE:-} ${dataset}@${snapshot_name}"

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

    if [ ! -f "$global_config" ]; then
        return 1
    fi

    zrb_retention_parse_config "$global_config" "$retention_name" "$minimum_name" "$period_target_name" "$minimum_target_name" || return 1

    if [ -f "$vault_config" ]; then
        zrb_retention_parse_config "$vault_config" "$retention_name" "$minimum_name" "$period_target_name" "$minimum_target_name" || return 1
    fi

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
