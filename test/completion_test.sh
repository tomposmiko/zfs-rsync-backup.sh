#!/bin/bash
# shellcheck disable=SC2329 # Tests are invoked by name through run_test.

set -u

# shellcheck source=test/test_helper.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

# shellcheck source=lib/zrb/completion.sh
source "$TEST_ROOT/lib/zrb/completion.sh"

C_RED=""

f_say() {
    :
}

mail() {
    :
}

test_begin_marks_running() {
    local test_dir
    local finished_file
    local running_file
    local failed_file

    test_dir=$(mktemp -d)
    finished_file="$test_dir/FINISHED"
    running_file="$test_dir/RUNNING"
    failed_file="$test_dir/FAILED"
    touch "$finished_file"

    zrb_completion_begin "$finished_file" "$running_file" "$failed_file" photos root

    [ ! -e "$finished_file" ] && [ -f "$running_file" ] && [ ! -e "$failed_file" ]

    rm -f "$running_file"
    rmdir "$test_dir"
}

test_abandoned_run_becomes_failed() {
    local test_dir
    local finished_file
    local running_file
    local failed_file

    test_dir=$(mktemp -d)
    finished_file="$test_dir/FINISHED"
    running_file="$test_dir/RUNNING"
    failed_file="$test_dir/FAILED"
    touch "$running_file"

    zrb_completion_begin "$finished_file" "$running_file" "$failed_file" photos root

    [ -f "$running_file" ] && [ -f "$failed_file" ] && [ ! -e "$finished_file" ]

    rm -f "$running_file" "$failed_file"
    rmdir "$test_dir"
}

test_success_clears_running_and_failed() {
    local test_dir
    local finished_file
    local running_file
    local failed_file

    test_dir=$(mktemp -d)
    finished_file="$test_dir/FINISHED"
    running_file="$test_dir/RUNNING"
    failed_file="$test_dir/FAILED"
    touch "$running_file" "$failed_file"

    zrb_completion_mark_success "$finished_file" "$running_file" "$failed_file" 0

    [ -f "$finished_file" ] && [ ! -e "$running_file" ] && [ ! -e "$failed_file" ]

    rm -f "$finished_file"
    rmdir "$test_dir"
}

test_controlled_failure_marks_failed() {
    local test_dir
    local running_file
    local failed_file

    test_dir=$(mktemp -d)
    running_file="$test_dir/RUNNING"
    failed_file="$test_dir/FAILED"
    touch "$running_file"

    zrb_completion_mark_failed "$running_file" "$failed_file"

    [ ! -e "$running_file" ] && [ -f "$failed_file" ]

    rm -f "$failed_file"
    rmdir "$test_dir"
}

test_failed_status_does_not_mark_success() {
    local test_dir
    local finished_file
    local running_file
    local failed_file

    test_dir=$(mktemp -d)
    finished_file="$test_dir/FINISHED"
    running_file="$test_dir/RUNNING"
    failed_file="$test_dir/FAILED"
    touch "$running_file"

    zrb_completion_mark_success "$finished_file" "$running_file" "$failed_file" 1

    [ ! -e "$finished_file" ] && [ -f "$running_file" ]

    rm -f "$running_file"
    rmdir "$test_dir"
}

failures=0

for test_name in \
    test_begin_marks_running \
    test_abandoned_run_becomes_failed \
    test_success_clears_running_and_failed \
    test_controlled_failure_marks_failed \
    test_failed_status_does_not_mark_success
do
    run_test "$test_name" || failures=$((failures + 1))
done

exit "$failures"
