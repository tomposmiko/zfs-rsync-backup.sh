#!/bin/bash
# shellcheck disable=SC2329 # Tests are invoked by name through run_test.

set -u

# shellcheck source=test/test_helper.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

# shellcheck source=lib/zrb/vault.sh
source "$TEST_ROOT/lib/zrb/vault.sh"

ZFS_TEST_STATUS=0
C_GREEN=""
C_RED=""

zfs() {
    return "$ZFS_TEST_STATUS"
}

mail() {
    :
}

f_say() {
    :
}

test_validate_existing_vault() {
    local test_dir

    test_dir=$(mktemp -d)
    mkdir "$test_dir/config" "$test_dir/data" "$test_dir/log"
    ZFS_TEST_STATUS=0

    zrb_vault_validate tank/zrb/photos "$test_dir" "$test_dir/config" "$test_dir/data" "$test_dir/log" photos root

    rmdir "$test_dir/config" "$test_dir/data" "$test_dir/log" "$test_dir"
}

test_validate_missing_dataset_fails() {
    local test_dir

    test_dir=$(mktemp -d)
    mkdir "$test_dir/config" "$test_dir/data" "$test_dir/log"
    ZFS_TEST_STATUS=1

    ( ! zrb_vault_validate tank/zrb/photos "$test_dir" "$test_dir/config" "$test_dir/data" "$test_dir/log" photos root )

    rmdir "$test_dir/config" "$test_dir/data" "$test_dir/log" "$test_dir"
}

test_disabled_vault() {
    local test_dir

    test_dir=$(mktemp -d)
    touch "$test_dir/DISABLE"

    zrb_vault_is_disabled "$test_dir"

    rm -f "$test_dir/DISABLE"
    rmdir "$test_dir"
}

test_load_source() {
    local test_dir
    local source_value=""

    test_dir=$(mktemp -d)
    echo "backup@example.com:/srv" > "$test_dir/source"

    zrb_vault_load_source source_value "$test_dir" photos root
    assert_equal "backup@example.com:/srv" "$source_value" "vault source"

    rm -f "$test_dir/source"
    rmdir "$test_dir"
}

test_resolve_parameter_exclude() {
    local test_dir
    local additional=""
    local vault_exclude=""

    test_dir=$(mktemp -d)

    zrb_vault_resolve_excludes additional vault_exclude /tmp/shared-exclude "$test_dir"
    assert_equal "--exclude-from=/tmp/shared-exclude" "$additional" "parameter exclude" &&
        assert_equal "" "$vault_exclude" "vault exclude"

    rmdir "$test_dir"
}

test_reject_conflicting_excludes() {
    local test_dir
    local additional=""
    local vault_exclude=""

    test_dir=$(mktemp -d)
    touch "$test_dir/exclude"

    ( ! zrb_vault_resolve_excludes additional vault_exclude /tmp/shared-exclude "$test_dir" )

    rm -f "$test_dir/exclude"
    rmdir "$test_dir"
}

test_add_notify_address() {
    local test_dir
    local notify_address="root"

    test_dir=$(mktemp -d)
    echo "backup@example.com" > "$test_dir/notify"

    zrb_vault_add_notify_address notify_address "$test_dir"
    assert_equal "root,backup@example.com" "$notify_address" "combined notification address"

    rm -f "$test_dir/notify"
    rmdir "$test_dir"
}

test_reject_invalid_notify_address() {
    local test_dir
    local notify_address="root"

    test_dir=$(mktemp -d)
    echo "invalid-address" > "$test_dir/notify"

    ( ! zrb_vault_add_notify_address notify_address "$test_dir" )

    rm -f "$test_dir/notify"
    rmdir "$test_dir"
}

failures=0

for test_name in \
    test_validate_existing_vault \
    test_validate_missing_dataset_fails \
    test_disabled_vault \
    test_load_source \
    test_resolve_parameter_exclude \
    test_reject_conflicting_excludes \
    test_add_notify_address \
    test_reject_invalid_notify_address
do
    run_test "$test_name" || failures=$((failures + 1))
done

exit "$failures"
