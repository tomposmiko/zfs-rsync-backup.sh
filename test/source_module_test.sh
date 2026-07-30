#!/bin/bash
# shellcheck disable=SC2329 # Tests are invoked by name through run_test.

set -u

# shellcheck source=test/test_helper.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

# shellcheck source=lib/zrb/source.sh
source "$TEST_ROOT/lib/zrb/source.sh"

SSH_TEST_STATUS=0
SSH_TEST_ARGS=""
C_RED=""

ssh() {
    SSH_TEST_ARGS=$*

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

test_remote_source_returns_path() {
    local remote_path

    remote_path=$(zrb_source_remote_path backup@example.com:/srv/data)

    assert_equal "/srv/data" "$remote_path" "remote path"
}

test_rsync_module_source_returns_host() {
    local host

    host=$(zrb_source_remote_host backup.example.com::module)

    assert_equal "backup.example.com" "$host" "rsync module host"
}

test_rsync_module_has_no_ssh_path() {
    ( ! zrb_source_remote_path backup.example.com::module )
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

    assert_equal "backup@example.com test -d /srv/data" "$SSH_TEST_ARGS" "remote directory check"
}

test_inaccessible_remote_source_fails() {
    SSH_TEST_STATUS=1
    ( ! zrb_source_check_remote_access backup@example.com:/srv/data "" photos root )
}

test_existing_local_source_without_placeholder_passes() {
    local test_dir

    test_dir=$(mktemp -d)

    zrb_source_validate_placeholder "$test_dir" "$test_dir/missing-global" "$test_dir/missing-vault" photos root

    rmdir "$test_dir"
}

test_vault_placeholder_overrides_global_placeholder() {
    local test_dir

    test_dir=$(mktemp -d)

    echo "global-marker" > "$test_dir/global-placeholder"
    echo "vault-marker" > "$test_dir/vault-placeholder"
    touch "$test_dir/vault-marker"

    zrb_source_validate_placeholder "$test_dir" "$test_dir/global-placeholder" "$test_dir/vault-placeholder" photos root

    rm -f "$test_dir/global-placeholder" "$test_dir/vault-placeholder" "$test_dir/vault-marker"
    rmdir "$test_dir"
}

test_missing_placeholder_fails() {
    local test_dir

    test_dir=$(mktemp -d)

    echo "missing-marker" > "$test_dir/placeholder"

    ( ! zrb_source_validate_placeholder "$test_dir" "$test_dir/placeholder" "$test_dir/missing-vault" photos root )

    rm -f "$test_dir/placeholder"
    rmdir "$test_dir"
}

test_remote_source_skips_placeholder_check() {
    zrb_source_validate_placeholder backup@example.com:/srv /does/not/exist /does/not/exist photos root
}

failures=0

for test_name in \
    test_local_source_has_no_remote_host \
    test_remote_source_returns_host \
    test_remote_source_returns_path \
    test_rsync_module_source_returns_host \
    test_rsync_module_has_no_ssh_path \
    test_missing_ssh_config_returns_empty \
    test_local_source_skips_ssh_check \
    test_accessible_remote_source_passes \
    test_inaccessible_remote_source_fails \
    test_existing_local_source_without_placeholder_passes \
    test_vault_placeholder_overrides_global_placeholder \
    test_missing_placeholder_fails \
    test_remote_source_skips_placeholder_check
do
    run_test "$test_name" || failures=$((failures + 1))
done

exit "$failures"
