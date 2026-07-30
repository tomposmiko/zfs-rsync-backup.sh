#!/bin/bash
# shellcheck disable=SC2329 # Tests are invoked by name through run_test.

set -u

# shellcheck source=test/test_helper.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

test_sourcing_entrypoint_has_no_side_effects() {
    source "$TEST_ROOT/zrb.sh"
    declare -F zrb_main >/dev/null
}

test_controlled_cleanup_marks_failed_and_removes_lock() {
    local test_dir
    local cleanup_status

    source "$TEST_ROOT/zrb.sh"

    test_dir=$(mktemp -d)

    ZRB_ACTIVE_LOCK_FILE="$test_dir/lock"
    ZRB_RUNNING_FILE="$test_dir/RUNNING"
    ZRB_FAILED_FILE="$test_dir/FAILED"
    ZRB_CLEANUP_ARMED=1

    touch "$ZRB_ACTIVE_LOCK_FILE" "$ZRB_RUNNING_FILE"

    zrb_main_cleanup 143
    cleanup_status=$?

    assert_equal "143" "$cleanup_status" "cleanup status" &&
        [ ! -e "$ZRB_ACTIVE_LOCK_FILE" ] &&
        [ ! -e "$ZRB_RUNNING_FILE" ] &&
        [ -f "$ZRB_FAILED_FILE" ]

    rm -f "$ZRB_FAILED_FILE"
    rmdir "$test_dir"
}

test_signal_handler_marks_failed_and_removes_lock() {
    local test_dir
    local signal_status

    source "$TEST_ROOT/zrb.sh"

    test_dir=$(mktemp -d)

    ZRB_ACTIVE_LOCK_FILE="$test_dir/lock"
    ZRB_RUNNING_FILE="$test_dir/RUNNING"
    ZRB_FAILED_FILE="$test_dir/FAILED"
    ZRB_CLEANUP_ARMED=1

    touch "$ZRB_ACTIVE_LOCK_FILE"

    ( zrb_main_handle_signal 130 )
    signal_status=$?

    assert_equal "130" "$signal_status" "signal status" &&
        [ ! -e "$ZRB_ACTIVE_LOCK_FILE" ] &&
        [ ! -e "$ZRB_RUNNING_FILE" ] &&
        [ -f "$ZRB_FAILED_FILE" ]

    rm -f "$ZRB_FAILED_FILE"
    rmdir "$test_dir"
}

test_repeated_signal_does_not_interrupt_cleanup() {
    local test_dir
    local signal_status

    source "$TEST_ROOT/zrb.sh"

    test_dir=$(mktemp -d)

    ZRB_ACTIVE_LOCK_FILE="$test_dir/lock"
    ZRB_RUNNING_FILE="$test_dir/RUNNING"
    ZRB_FAILED_FILE="$test_dir/FAILED"
    ZRB_CLEANUP_ARMED=1

    touch "$ZRB_ACTIVE_LOCK_FILE" "$ZRB_RUNNING_FILE"

    (
        zrb_completion_mark_failed() {
            kill -INT "$BASHPID"

            touch "$2"

            rm -f "$1"
        }

        zrb_main_handle_signal 130
    )
    signal_status=$?

    assert_equal "130" "$signal_status" "repeated signal status" &&
        [ ! -e "$ZRB_ACTIVE_LOCK_FILE" ] &&
        [ ! -e "$ZRB_RUNNING_FILE" ] &&
        [ -f "$ZRB_FAILED_FILE" ]

    rm -f "$ZRB_FAILED_FILE"
    rmdir "$test_dir"
}

failures=0

for test_name in \
    test_sourcing_entrypoint_has_no_side_effects \
    test_controlled_cleanup_marks_failed_and_removes_lock \
    test_signal_handler_marks_failed_and_removes_lock \
    test_repeated_signal_does_not_interrupt_cleanup
do
    run_test "$test_name" || failures=$((failures + 1))
done

exit "$failures"
