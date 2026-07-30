#!/bin/bash
# shellcheck disable=SC2034 # Parsed values are state consumed by the parallel entrypoint.

zrb_parallel_defaults() {
    PARALLEL_JOBS=4
}

zrb_parallel_usage() {
    echo "Usage:"
    echo "    $0                    run daily backups with four parallel jobs"
    echo "    $0 -f <freq>          hourly,daily,weekly,monthly (comma separated list)"
    echo "    $0 -j <num>           number of parallel jobs"
    echo "    $0 --version          display version"
    echo
}

zrb_parallel_parse_args() {
    local parameter

    while (($#)); do
        case "$1" in
            -f|--freq)
                parameter=${2:-}

                if [[ ! $parameter =~ ^[A-Za-z0-9] ]]; then
                    f_say "$C_RED Missing argument!"

                    return 1
                fi

                FREQ_LIST=$parameter
                shift 2
                ;;
            -j|--jobs)
                parameter=${2:-}

                if [[ ! $parameter =~ ^[1-9][0-9]*$ ]]; then
                    f_say "$C_RED Invalid number of parallel jobs!"

                    return 1
                fi

                PARALLEL_JOBS=$parameter
                shift 2
                ;;
            -h|--help)
                zrb_parallel_usage

                return 2
                ;;
            -V|--version)
                zrb_version_print parallel-zrb

                return 2
                ;;
            *)
                zrb_parallel_usage

                return 1
                ;;
        esac
    done
}

zrb_parallel_list_vaults() {
    local backup_dataset=$1
    local dataset_output
    local candidate
    local other
    local has_child
    local -a datasets=()

    if ! { zfs list -H -s name -o name "$backup_dataset" > /dev/null; }; then
        f_say "$C_RED    Unable to access the ZFS dataset: '$backup_dataset'"

        return 1
    fi

    dataset_output=$(zfs list -r -H -s name -o name "$backup_dataset") || return 1
    mapfile -t datasets <<< "$dataset_output"

    for candidate in "${datasets[@]}"; do
        if [ "$candidate" == "$backup_dataset" ] || [ -z "$candidate" ]; then
            continue
        fi

        has_child=0

        for other in "${datasets[@]}"; do
            if [[ $other == "$candidate/"* ]]; then
                has_child=1

                break
            fi
        done

        if [ "$has_child" -eq 0 ]; then
            echo "${candidate#"$backup_dataset/"}"
        fi
    done
}

zrb_parallel_lock_create() {
    local lock_file=$1
    local script_basename=$2
    local pid_locked
    local lock_status

    exec {ZRB_PARALLEL_LOCK_FD}<>"$lock_file" || return 1
    flock -n "$ZRB_PARALLEL_LOCK_FD"
    lock_status=$?

    if [ "$lock_status" -ne 0 ]; then
        exec {ZRB_PARALLEL_LOCK_FD}>&-

        unset ZRB_PARALLEL_LOCK_FD

        f_say "$C_RED $script_basename is already running!"

        return 1
    fi

    pid_locked=$(<"$lock_file")

    if [ -n "$pid_locked" ]; then
        f_say "$C_PURPLE Stale pidfile exists; replacing it."
    fi

    printf '%s\n' "$$" > "$lock_file"
}

zrb_parallel_lock_remove() {
    local lock_file=$1

    rm -f "$lock_file"

    if [ -n "${ZRB_PARALLEL_LOCK_FD:-}" ]; then
        flock -u "$ZRB_PARALLEL_LOCK_FD"
        exec {ZRB_PARALLEL_LOCK_FD}>&-

        unset ZRB_PARALLEL_LOCK_FD
    fi
}

zrb_parallel_run_jobs() {
    local vaults_file=$1
    local parallel_jobs=$2
    local frequency_list=$3
    local -a command=(
        parallel
        -j
        "$parallel_jobs"
        -a
        "$vaults_file"
        zrb.sh
        -e
        yes
        -f
        "$frequency_list"
        -v
        "{1}"
    )

    "${command[@]}"
}

zrb_parallel_print_timestamp() {
    local label=$1

    echo -n "$label"
    date "+%Y-%m-%d %H:%M %Z"
}

zrb_parallel_cleanup_temp() {
    if [ -n "${ZRB_PARALLEL_VAULTS_FILE:-}" ]; then
        rm -f "$ZRB_PARALLEL_VAULTS_FILE"
    fi
}
