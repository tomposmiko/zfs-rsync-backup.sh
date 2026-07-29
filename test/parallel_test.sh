#!/bin/bash
# shellcheck disable=SC2329 # Tests are invoked by name through run_test.

set -u

# shellcheck source=test/test_helper.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

# shellcheck source=lib/zrb/lock.sh
source "$TEST_ROOT/lib/zrb/lock.sh"

# shellcheck source=lib/zrb/parallel.sh
source "$TEST_ROOT/lib/zrb/parallel.sh"

ZFS_TEST_STATUS=0
ZFS_TEST_OUTPUT=""
PARALLEL_TEST_STATUS=0
PARALLEL_ARGS_FILE=""
C_RED=""
C_PURPLE=""

zfs() {
    if [ "$ZFS_TEST_STATUS" -ne 0 ]; then
        return "$ZFS_TEST_STATUS"
    fi

    if [ "$1" == list ] && [[ " $* " == *" -r "* ]]; then
        echo "$ZFS_TEST_OUTPUT"
    fi
}

parallel() {
    printf "%s\n" "$@" > "$PARALLEL_ARGS_FILE"

    return "$PARALLEL_TEST_STATUS"
}

f_say() {
    :
}

test_parse_options() {
    FREQ_LIST=daily
    PARALLEL_JOBS=4

    zrb_parallel_parse_args -f daily,weekly -j 8

    assert_equal "daily,weekly" "$FREQ_LIST" "frequency list" &&
        assert_equal "8" "$PARALLEL_JOBS" "parallel jobs"
}

test_reject_invalid_job_count() {
    ( ! zrb_parallel_parse_args -j 0 )
}

test_list_leaf_vaults() {
    local vaults

    ZFS_TEST_STATUS=0
    ZFS_TEST_OUTPUT=$'tank/zrb\ntank/zrb/alpha\ntank/zrb/group\ntank/zrb/group/beta'

    vaults=$(zrb_parallel_list_vaults tank/zrb)

    assert_equal $'alpha\ngroup/beta' "$vaults" "leaf vaults"
}

test_list_failure_is_returned() {
    ZFS_TEST_STATUS=1
    ( ! zrb_parallel_list_vaults tank/zrb )
}

test_replace_stale_parallel_lock() {
    local test_dir
    local lock_file

    test_dir=$(mktemp -d)
    lock_file="$test_dir/lock"
    echo 99999999 > "$lock_file"

    zrb_parallel_lock_create "$lock_file" parallel-zrb.sh
    assert_equal "$$" "$(<"$lock_file")" "parallel lock PID"

    zrb_lock_remove "$lock_file"
    rmdir "$test_dir"
}

test_parallel_command() {
    local test_dir
    local vaults_file

    test_dir=$(mktemp -d)
    vaults_file="$test_dir/vaults"
    PARALLEL_ARGS_FILE="$test_dir/args"
    PARALLEL_TEST_STATUS=0
    echo photos > "$vaults_file"

    zrb_parallel_run_jobs "$vaults_file" 6 daily,weekly

    assert_equal $'-j\n6\n-a\n'"$vaults_file"$'\nzrb.sh\n-e\nyes\n-f\ndaily,weekly\n-v\n{1}' "$(<"$PARALLEL_ARGS_FILE")" "Parallel arguments"

    rm -f "$vaults_file" "$PARALLEL_ARGS_FILE"
    rmdir "$test_dir"
}

test_parallel_failure_is_returned() {
    local test_dir
    local vaults_file
    local status

    test_dir=$(mktemp -d)
    vaults_file="$test_dir/vaults"
    PARALLEL_ARGS_FILE="$test_dir/args"
    PARALLEL_TEST_STATUS=9
    echo photos > "$vaults_file"

    zrb_parallel_run_jobs "$vaults_file" 4 daily
    status=$?

    assert_equal "9" "$status" "Parallel failure status"

    rm -f "$vaults_file" "$PARALLEL_ARGS_FILE"
    rmdir "$test_dir"
}

test_temp_cleanup() {
    local temp_file

    temp_file=$(mktemp)
    ZRB_PARALLEL_VAULTS_FILE=$temp_file

    zrb_parallel_cleanup_temp

    [ ! -e "$temp_file" ]
}

failures=0

for test_name in \
    test_parse_options \
    test_reject_invalid_job_count \
    test_list_leaf_vaults \
    test_list_failure_is_returned \
    test_replace_stale_parallel_lock \
    test_parallel_command \
    test_parallel_failure_is_returned \
    test_temp_cleanup
do
    run_test "$test_name" || failures=$((failures + 1))
done

exit "$failures"
