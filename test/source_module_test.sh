#!/bin/bash
# shellcheck disable=SC2329 # Tests are invoked by name through run_test.

set -u

# shellcheck source=test/test_helper.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

# shellcheck source=lib/zrb/source.sh
source "$TEST_ROOT/lib/zrb/source.sh"

SSH_TEST_STATUS=0
C_RED=""

ssh() {
    return "$SSH_TEST_STATUS"
}

mail() {
    :
}

f_say() {
    :
}

test_local_source_has_no_remote_host() {
    ( ! zrb_source_remote_host /srv/data )
}

test_remote_source_returns_host() {
    local host

    host=$(zrb_source_remote_host backup@example.com:/srv/data)

    assert_equal "backup@example.com" "$host" "remote host"
}

test_rsync_module_source_returns_host() {
    local host

    host=$(zrb_source_remote_host backup.example.com::module)

    assert_equal "backup.example.com" "$host" "rsync module host"
}

test_missing_ssh_config_returns_empty() {
    local config

    config=$(zrb_source_ssh_config /does/not/exist)

    assert_equal "" "$config" "missing SSH config"
}

test_local_source_skips_ssh_check() {
    SSH_TEST_STATUS=1
    zrb_source_check_remote_access /srv/data "" photos root
}

test_accessible_remote_source_passes() {
    SSH_TEST_STATUS=0
    zrb_source_check_remote_access backup@example.com:/srv/data "" photos root
}

test_inaccessible_remote_source_fails() {
    SSH_TEST_STATUS=1
    ( ! zrb_source_check_remote_access backup@example.com:/srv/data "" photos root )
}

failures=0

for test_name in \
    test_local_source_has_no_remote_host \
    test_remote_source_returns_host \
    test_rsync_module_source_returns_host \
    test_missing_ssh_config_returns_empty \
    test_local_source_skips_ssh_check \
    test_accessible_remote_source_passes \
    test_inaccessible_remote_source_fails
do
    run_test "$test_name" || failures=$((failures + 1))
done

exit "$failures"
