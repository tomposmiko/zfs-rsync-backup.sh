#!/bin/bash
# shellcheck disable=SC2329 # Tests are invoked by name through run_test.

set -u

# shellcheck source=test/test_helper.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

# shellcheck source=lib/zrb/retention.sh
source "$TEST_ROOT/lib/zrb/retention.sh"

ZFS_LIST_STATUS=0
ZFS_DESTROY_STATUS=0
ZFS_LIST_OUTPUT=""
ZFS_DESTROY_LOG=""
C_GREEN=""
C_RED=""

zfs() {
    case "$1" in
        list)
            echo "$ZFS_LIST_OUTPUT"

            return "$ZFS_LIST_STATUS"
            ;;
        destroy)
            echo "$2" >> "$ZFS_DESTROY_LOG"

            return "$ZFS_DESTROY_STATUS"
            ;;
    esac
}

date() {
    local date_value=${3:-}

    case "$date_value" in
        "14 days ago")
            echo 2000
            ;;
        "2024-01-01 00:00")
            echo 1000
            ;;
        "2024-01-02 00:00")
            echo 1500
            ;;
        "2024-02-01 00:00")
            echo 3000
            ;;
        *)
            return 1
            ;;
    esac
}

mail() {
    :
}

f_say() {
    :
}

setup_destroy_log() {
    ZFS_DESTROY_LOG=$(mktemp)
    ZFS_LIST_STATUS=0
    ZFS_DESTROY_STATUS=0
}

cleanup_destroy_log() {
    rm -f "$ZFS_DESTROY_LOG"
}

test_expiration_modes() {
    zrb_retention_is_only_mode only &&
        ( ! zrb_retention_is_only_mode yes ) &&
        ( ! zrb_retention_is_only_mode no ) &&
        zrb_retention_runs_after_snapshot yes &&
        ( ! zrb_retention_runs_after_snapshot only ) &&
        ( ! zrb_retention_runs_after_snapshot no )
}

test_expire_old_snapshots_above_minimum() {
    setup_destroy_log
    ZFS_LIST_OUTPUT=$'tank/zrb/photos@zrb_daily_2024-01-01--00-00\ntank/zrb/photos@zrb_daily_2024-01-02--00-00\ntank/zrb/photos@zrb_daily_2024-02-01--00-00'

    zrb_retention_apply tank/zrb/photos zrb daily "14 days" 1

    assert_equal $'tank/zrb/photos@zrb_daily_2024-01-01--00-00\ntank/zrb/photos@zrb_daily_2024-01-02--00-00' "$(<"$ZFS_DESTROY_LOG")" "expired snapshots"
    cleanup_destroy_log
}

test_keep_minimum_count() {
    setup_destroy_log
    ZFS_LIST_OUTPUT=$'tank/zrb/photos@zrb_daily_2024-01-01--00-00\ntank/zrb/photos@zrb_daily_2024-01-02--00-00'

    zrb_retention_apply tank/zrb/photos zrb daily "14 days" 2

    assert_equal "" "$(<"$ZFS_DESTROY_LOG")" "minimum retained snapshots"
    cleanup_destroy_log
}

test_expired_snapshot_output() {
    local output

    setup_destroy_log
    ZFS_LIST_OUTPUT="tank/zrb/photos@zrb_daily_2024-01-01--00-00"

    output=$(
        f_say() {
            printf '%s\n' "$1"
        }

        zrb_retention_apply tank/zrb/photos zrb daily "14 days" 0
    )

    assert_equal "        EXPIRED: tank/zrb/photos@zrb_daily_2024-01-01--00-00" "$output" "expired snapshot output"

    cleanup_destroy_log
}

test_ignore_new_unrelated_and_malformed_snapshots() {
    setup_destroy_log
    ZFS_LIST_OUTPUT=$'tank/zrb/photos@manual_daily_2024-01-01--00-00\ntank/zrb/photos@zrb_weekly_2024-01-01--00-00\ntank/zrb/photos@zrb_daily_invalid\ntank/zrb/photos@zrb_daily_2024-02-01--00-00'

    zrb_retention_apply tank/zrb/photos zrb daily "14 days" 0

    assert_equal "" "$(<"$ZFS_DESTROY_LOG")" "ignored snapshots"
    cleanup_destroy_log
}

test_destroy_failure_is_returned() {
    setup_destroy_log
    ZFS_LIST_OUTPUT="tank/zrb/photos@zrb_daily_2024-01-01--00-00"
    ZFS_DESTROY_STATUS=1

    ( ! zrb_retention_apply tank/zrb/photos zrb daily "14 days" 0 )
    cleanup_destroy_log
}

test_list_failure_is_returned() {
    setup_destroy_log
    ZFS_LIST_STATUS=1

    ( ! zrb_retention_apply tank/zrb/photos zrb daily "14 days" 0 )
    cleanup_destroy_log
}

test_vault_config_overrides_global_config() {
    local test_dir
    local global_config
    local vault_config

    setup_destroy_log
    test_dir=$(mktemp -d)

    global_config="$test_dir/global"
    vault_config="$test_dir/vault"
    ZFS_LIST_OUTPUT=$'tank/zrb/photos@zrb_daily_2024-01-01--00-00\ntank/zrb/photos@zrb_daily_2024-01-02--00-00'

    echo 'expire_daily="14 days"' > "$global_config"
    echo 'least_keep_count_daily="2"' >> "$global_config"
    echo 'least_keep_count_daily="1"' > "$vault_config"

    zrb_retention_run tank/zrb/photos zrb daily "$global_config" "$vault_config" photos root

    assert_equal "tank/zrb/photos@zrb_daily_2024-01-01--00-00" "$(<"$ZFS_DESTROY_LOG")" "vault retention override"

    rm -f "$global_config" "$vault_config"
    rmdir "$test_dir"
    cleanup_destroy_log
}

test_all_frequency_configurations() {
    local test_dir
    local global_config
    local frequency

    setup_destroy_log
    test_dir=$(mktemp -d)

    global_config="$test_dir/global"
    ZFS_LIST_OUTPUT=""

    for frequency in hourly daily weekly monthly; do
        echo "expire_${frequency}=\"14 days\"" >> "$global_config"
        echo "least_keep_count_${frequency}=\"0\"" >> "$global_config"
    done

    for frequency in hourly daily weekly monthly; do
        zrb_retention_run tank/zrb/photos zrb "$frequency" "$global_config" "$test_dir/missing-vault-config" photos root || return 1
    done

    rm -f "$global_config"
    rmdir "$test_dir"
    cleanup_destroy_log
}

test_shell_code_in_config_is_rejected() {
    local test_dir
    local global_config
    local marker_file
    local retention_period=""
    local minimum_count=""

    test_dir=$(mktemp -d)

    global_config="$test_dir/global"
    marker_file="$test_dir/executed"

    # shellcheck disable=SC2016 # The command substitution must remain literal in the generated configuration.
    printf 'expire_daily="$(touch %s)"\n' "$marker_file" > "$global_config"

    echo 'least_keep_count_daily="1"' >> "$global_config"

    ( ! zrb_retention_load_config retention_period minimum_count daily "$global_config" "$test_dir/missing-vault-config" )
    assert_path_missing "$marker_file"

    rm -f "$global_config"
    rmdir "$test_dir"
}

test_unknown_config_key_is_rejected() {
    local test_dir
    local global_config
    local retention_period=""
    local minimum_count=""

    test_dir=$(mktemp -d)

    global_config="$test_dir/global"

    echo 'expire_daily="14 days"' > "$global_config"
    echo 'least_keep_count_daily="1"' >> "$global_config"
    echo 'run_after_expiration="dangerous-command"' >> "$global_config"

    ( ! zrb_retention_load_config retention_period minimum_count daily "$global_config" "$test_dir/missing-vault-config" )

    rm -f "$global_config"
    rmdir "$test_dir"
}

failures=0

for test_name in \
    test_expiration_modes \
    test_expire_old_snapshots_above_minimum \
    test_keep_minimum_count \
    test_expired_snapshot_output \
    test_ignore_new_unrelated_and_malformed_snapshots \
    test_destroy_failure_is_returned \
    test_list_failure_is_returned \
    test_vault_config_overrides_global_config \
    test_all_frequency_configurations \
    test_shell_code_in_config_is_rejected \
    test_unknown_config_key_is_rejected
do
    run_test "$test_name" || failures=$((failures + 1))
done

exit "$failures"
