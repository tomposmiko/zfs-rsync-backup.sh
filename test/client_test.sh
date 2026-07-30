#!/bin/bash
# shellcheck disable=SC2329 # Tests are invoked by name through run_test.

set -u

# shellcheck source=test/test_helper.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

# shellcheck source=lib/zrb/client.sh
source "$TEST_ROOT/lib/zrb/client.sh"

APT_CALLS=0
USERADD_CALLS=0
VISUDO_STATUS=0

apt() {
    APT_CALLS=$((APT_CALLS + 1))
}

id() {
    return 0
}

useradd() {
    USERADD_CALLS=$((USERADD_CALLS + 1))
}

chown() {
    :
}

visudo() {
    return "$VISUDO_STATUS"
}

test_parse_options() {
    zrb_client_defaults
    zrb_client_parse_args --public-key-file /tmp/key.pub --user archive --dry-run

    assert_equal "/tmp/key.pub" "$CLIENT_PUBLIC_KEY_FILE" "public key file" &&
        assert_equal "archive" "$CLIENT_USER" "client user" &&
        assert_equal "1" "$CLIENT_DRY_RUN" "dry-run mode"
}

test_public_key_is_required() {
    zrb_client_defaults
    ( ! zrb_client_parse_args --user archive )
}

test_invalid_user_is_rejected() {
    zrb_client_defaults
    ( ! zrb_client_parse_args --public-key-file /tmp/key.pub --user "Invalid User" )
}

test_invalid_key_is_rejected() {
    local test_dir
    local key_file
    local public_key=""

    test_dir=$(mktemp -d)

    key_file="$test_dir/key.pub"

    echo "not-a-public-key" > "$key_file"

    ( ! zrb_client_read_public_key public_key "$key_file" )

    rm -f "$key_file"
    rmdir "$test_dir"
}

test_dry_run_does_not_apply_changes() {
    local test_dir
    local key_file
    local output

    test_dir=$(mktemp -d)

    key_file="$test_dir/key.pub"
    ZRB_CLIENT_ROOT="$test_dir/root"
    APT_CALLS=0
    USERADD_CALLS=0

    echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey backup" > "$key_file"

    output=$(zrb_client_apply backup-zrb "$key_file" 1)

    [[ $output == *"Ensure user: backup-zrb"* ]] &&
        assert_equal "0" "$APT_CALLS" "apt calls" &&
        assert_equal "0" "$USERADD_CALLS" "useradd calls" &&
        [ ! -e "$ZRB_CLIENT_ROOT" ]

    rm -f "$key_file"
    rmdir "$test_dir"
}

test_apply_is_idempotent() {
    local test_dir
    local key_file
    local authorized_keys
    local sudoers_file
    local key_count

    test_dir=$(mktemp -d)

    key_file="$test_dir/key.pub"
    ZRB_CLIENT_ROOT="$test_dir/root"
    authorized_keys="$ZRB_CLIENT_ROOT/home/backup-zrb/.ssh/authorized_keys"
    sudoers_file="$ZRB_CLIENT_ROOT/etc/sudoers.d/zrb"

    echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey backup" > "$key_file"
    mkdir -p "$ZRB_CLIENT_ROOT/home" "$ZRB_CLIENT_ROOT/etc/sudoers.d"

    zrb_client_apply backup-zrb "$key_file" 0
    zrb_client_apply backup-zrb "$key_file" 0

    key_count=$(grep -Fxc "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey backup" "$authorized_keys")

    assert_equal "1" "$key_count" "authorized key count" &&
        grep -Fq "backup-zrb ALL=(ALL:ALL) NOPASSWD:C_ZRB" "$sudoers_file"

    rm -f "$authorized_keys" "$sudoers_file" "$key_file"
    rmdir "$ZRB_CLIENT_ROOT/home/backup-zrb/.ssh" "$ZRB_CLIENT_ROOT/home/backup-zrb" "$ZRB_CLIENT_ROOT/home" "$ZRB_CLIENT_ROOT/etc/sudoers.d" "$ZRB_CLIENT_ROOT/etc" "$ZRB_CLIENT_ROOT" "$test_dir"
}

test_invalid_sudoers_is_not_installed() {
    local test_dir
    local sudoers_file

    test_dir=$(mktemp -d)

    sudoers_file="$test_dir/zrb"
    VISUDO_STATUS=1

    ( ! zrb_client_install_sudoers backup-zrb "$sudoers_file" )
    [ ! -e "$sudoers_file" ]

    VISUDO_STATUS=0
    rmdir "$test_dir"
}

failures=0

for test_name in \
    test_parse_options \
    test_public_key_is_required \
    test_invalid_user_is_rejected \
    test_invalid_key_is_rejected \
    test_dry_run_does_not_apply_changes \
    test_apply_is_idempotent \
    test_invalid_sudoers_is_not_installed
do
    run_test "$test_name" || failures=$((failures + 1))
done

exit "$failures"
