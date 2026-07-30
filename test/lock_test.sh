#!/bin/bash
# shellcheck disable=SC2329 # Tests are invoked by name through run_test.

set -u

# shellcheck source=test/test_helper.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

# shellcheck source=lib/zrb/lock.sh
source "$TEST_ROOT/lib/zrb/lock.sh"

C_RED=""
C_YELLOW=""

f_say() {
    :
}

mail() {
    :
}

test_create_new_lock() {
    local test_dir
    local lock_file

    test_dir=$(mktemp -d)

    lock_file="$test_dir/lock"

    zrb_lock_create "$lock_file" lock_test.sh photos root
    assert_equal "$$" "$(<"$lock_file")" "new lock PID"

    zrb_lock_remove "$lock_file"
    rmdir "$test_dir"
}

test_replace_stale_lock() {
    local test_dir
    local lock_file

    test_dir=$(mktemp -d)

    lock_file="$test_dir/lock"

    echo 99999999 > "$lock_file"

    zrb_lock_create "$lock_file" zrb.sh photos root
    assert_equal "$$" "$(<"$lock_file")" "replacement lock PID"

    zrb_lock_remove "$lock_file"
    rmdir "$test_dir"
}

test_reject_active_lock() {
    local test_dir
    local lock_file
    local active_pid

    test_dir=$(mktemp -d)

    lock_file="$test_dir/lock"

    bash -c 'while :; do sleep 1; done' zrb.sh photos &
    active_pid=$!
    echo "$active_pid" > "$lock_file"

    if { zrb_lock_create "$lock_file" zrb.sh photos root; }; then
        kill "$active_pid"
        wait "$active_pid" 2>/dev/null

        return 1
    fi

    assert_equal "$active_pid" "$(<"$lock_file")" "active lock PID"

    kill "$active_pid"
    wait "$active_pid" 2>/dev/null
    zrb_lock_remove "$lock_file"
    rmdir "$test_dir"
}

failures=0

for test_name in \
    test_create_new_lock \
    test_replace_stale_lock \
    test_reject_active_lock
do
    run_test "$test_name" || failures=$((failures + 1))
done

exit "$failures"
