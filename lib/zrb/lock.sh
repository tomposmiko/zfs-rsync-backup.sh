#!/bin/bash

zrb_lock_remove() {
    local lock_file=$1

    rm -f "$lock_file"
}

zrb_lock_process_matches() {
    local pid=$1
    local script_basename=$2
    local vault_name=$3

    # shellcheck disable=SC2009
    ps --no-headers -o args -p "$pid" | grep -q "${script_basename}.* ${vault_name}"
}

zrb_lock_create() {
    local lock_file=$1
    local script_basename=$2
    local vault_name=$3
    local notify_address=$4
    local pid_locked
    local lock_read_status

    pid_locked=$(cat "$lock_file" 2>/dev/null)
    lock_read_status=$?

    if [ "$lock_read_status" -eq 0 ]; then
        if { zrb_lock_process_matches "$pid_locked" "$script_basename" "$vault_name"; }; then
            echo "Backup job is already running!" | mail -s "zrb.sh ERROR: $vault_name" "$notify_address"
            f_say "$C_RED Backup job is already running!"

            return 1
        fi

        f_say "$C_PURPLE Stale pidfile exists...removing."
        zrb_lock_remove "$lock_file"
    fi

    echo "$$" > "$lock_file"
}
