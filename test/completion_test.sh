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

test_begin_removes_existing_marker() {
    local test_dir
    local completion_file

    test_dir=$(mktemp -d)
    completion_file="$test_dir/FINISHED"
    touch "$completion_file"

    zrb_completion_begin "$completion_file" photos root

    [ ! -e "$completion_file" ]
    rmdir "$test_dir"
}

test_begin_accepts_missing_marker() {
    local test_dir
    local completion_file

    test_dir=$(mktemp -d)
    completion_file="$test_dir/FINISHED"

    zrb_completion_begin "$completion_file" photos root

    [ ! -e "$completion_file" ]
    rmdir "$test_dir"
}

test_success_creates_marker() {
    local test_dir
    local completion_file

    test_dir=$(mktemp -d)
    completion_file="$test_dir/FINISHED"

    zrb_completion_mark_success "$completion_file" 0

    [ -f "$completion_file" ]
    rm -f "$completion_file"
    rmdir "$test_dir"
}

test_failure_does_not_create_marker() {
    local test_dir
    local completion_file

    test_dir=$(mktemp -d)
    completion_file="$test_dir/FINISHED"

    zrb_completion_mark_success "$completion_file" 1

    [ ! -e "$completion_file" ]
    rmdir "$test_dir"
}

failures=0

for test_name in \
    test_begin_removes_existing_marker \
    test_begin_accepts_missing_marker \
    test_success_creates_marker \
    test_failure_does_not_create_marker
do
    run_test "$test_name" || failures=$((failures + 1))
done

exit "$failures"
