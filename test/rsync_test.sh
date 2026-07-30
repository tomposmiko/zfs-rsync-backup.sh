#!/bin/bash
# shellcheck disable=SC2329 # Tests are invoked by name through run_test.

set -u

# shellcheck source=test/test_helper.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

# shellcheck source=lib/zrb/rsync.sh
source "$TEST_ROOT/lib/zrb/rsync.sh"

RSYNC_TEST_STATUS=0
RSYNC_TEST_DIAGNOSTICS=""

rsync() {
    printf '%s' "$RSYNC_TEST_DIAGNOSTICS" >&2

    return "$RSYNC_TEST_STATUS"
}

test_build_args() {
    local -a args=()

    zrb_rsync_build_args args /vault/log/rsync.log /etc/zrb/exclude "--exclude-from=/tmp/shared" "--exclude-from=/vault/config/exclude"

    assert_equal "19" "${#args[@]}" "argument count" &&
        assert_equal "--log-file=/vault/log/rsync.log" "${args[15]}" "log argument" &&
        assert_equal "--exclude-from=/etc/zrb/exclude" "${args[16]}" "global exclude argument" &&
        assert_equal "--exclude-from=/tmp/shared" "${args[17]}" "additional exclude argument" &&
        assert_equal "--exclude-from=/vault/config/exclude" "${args[18]}" "vault exclude argument"
}

test_omit_empty_optional_args() {
    local -a args=()

    zrb_rsync_build_args args /vault/log/rsync.log /etc/zrb/exclude "" ""

    assert_equal "17" "${#args[@]}" "argument count without optional excludes"
}

test_status_zero_is_accepted() {
    zrb_rsync_status_is_acceptable 0
}

test_status_23_without_diagnostics_is_rejected() {
    ( ! zrb_rsync_status_is_acceptable 23 )
}

test_status_24_is_accepted() {
    zrb_rsync_status_is_acceptable 24
}

test_other_status_is_rejected() {
    ( ! zrb_rsync_status_is_acceptable 12 )
}

test_run_accepts_status_23_for_vanished_source_file() {
    local -a args=()

    RSYNC_TEST_STATUS=23
    RSYNC_TEST_DIAGNOSTICS=$'rsync: [sender] link_stat "/srv/file" failed: No such file or directory (2)\nrsync error: some files/attrs were not transferred (see previous errors) (code 23) at main.c(1338) [sender=3.2.7]\n'

    zrb_rsync_run host:/srv /vault/data "" args 2> /dev/null
}

test_run_accepts_status_23_for_changed_source_file() {
    local -a args=()

    RSYNC_TEST_STATUS=23
    RSYNC_TEST_DIAGNOSTICS=$'ERROR: media/shot.mov failed verification -- update discarded.\nrsync error: some files/attrs were not transferred (see previous errors) (code 23) at main.c(1338) [sender=3.2.7]\n'

    zrb_rsync_run host:/srv /vault/data "" args 2> /dev/null
}

test_run_rejects_status_23_for_permission_error() {
    local -a args=()
    local status

    RSYNC_TEST_STATUS=23
    RSYNC_TEST_DIAGNOSTICS=$'rsync: [sender] send_files failed to open "/srv/private": Permission denied (13)\nrsync error: some files/attrs were not transferred (see previous errors) (code 23) at main.c(1338) [sender=3.2.7]\n'

    zrb_rsync_run host:/srv /vault/data "" args 2> /dev/null
    status=$?

    assert_equal "23" "$status" "permission failure status"
}

test_run_preserves_failure_status() {
    local -a args=()
    local status

    RSYNC_TEST_STATUS=12
    RSYNC_TEST_DIAGNOSTICS=""

    zrb_rsync_run host:/srv /vault/data "" args 2> /dev/null
    status=$?

    assert_equal "12" "$status" "rsync failure status"
}

failures=0

for test_name in \
    test_build_args \
    test_omit_empty_optional_args \
    test_status_zero_is_accepted \
    test_status_23_without_diagnostics_is_rejected \
    test_status_24_is_accepted \
    test_other_status_is_rejected \
    test_run_accepts_status_23_for_vanished_source_file \
    test_run_accepts_status_23_for_changed_source_file \
    test_run_rejects_status_23_for_permission_error \
    test_run_preserves_failure_status
do
    run_test "$test_name" || failures=$((failures + 1))
done

exit "$failures"
