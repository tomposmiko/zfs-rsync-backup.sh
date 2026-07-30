#!/bin/bash

zrb_lock_remove() {
    local lock_file=$1

    rm -f "$lock_file"

    if [ -n "${ZRB_LOCK_FD:-}" ]; then
        flock -u "$ZRB_LOCK_FD"
        exec {ZRB_LOCK_FD}>&-

        unset ZRB_LOCK_FD
    fi
}

zrb_lock_create() {
    local lock_file=$1
    local vault_name=$3
    local notify_address=$4
    local pid_locked
    local lock_status

    exec {ZRB_LOCK_FD}<>"$lock_file" || return 1
    flock -n "$ZRB_LOCK_FD"
    lock_status=$?

    if [ "$lock_status" -ne 0 ]; then
        exec {ZRB_LOCK_FD}>&-

        unset ZRB_LOCK_FD

        echo "Backup job is already running!" | mail -s "zrb.sh ERROR: $vault_name" "$notify_address"
        f_say "$C_RED Backup job is already running!"

        return 1
    fi

    pid_locked=$(<"$lock_file")

    if [ -n "$pid_locked" ]; then
        f_say "${C_YELLOW:-}        WARNING:${C_NOCOLOR:-} Stale pidfile exists; replacing it."
    fi

    printf '%s\n' "$$" > "$lock_file"
}
