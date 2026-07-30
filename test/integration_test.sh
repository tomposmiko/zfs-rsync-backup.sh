#!/bin/bash
# shellcheck disable=SC2329 # Tests are invoked by name through run_test.

set -u

# shellcheck source=test/test_helper.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

create_stub_commands() {
    local stub_dir=$1

    # shellcheck disable=SC2016 # Variables are expanded when the generated stub runs.
    printf '#!/bin/bash\ncase "$1" in\n    list)\n        exit 0\n        ;;\n    snap)\n        echo "$2" >> "$ZFS_TEST_LOG"\n        exit 0\n        ;;\n    destroy)\n        exit 0\n        ;;\nesac\n' > "$stub_dir/zfs"
    printf '#!/bin/bash\nexit 0\n' > "$stub_dir/rsync"
    printf '#!/bin/bash\ncat > /dev/null\nexit 0\n' > "$stub_dir/mail"

    # shellcheck disable=SC2016 # The generated stub expands the status when it runs.
    printf '#!/bin/bash\nexit "${SSH_TEST_STATUS:-0}"\n' > "$stub_dir/ssh"
    chmod +x "$stub_dir/zfs" "$stub_dir/rsync" "$stub_dir/mail" "$stub_dir/ssh"
}

test_complete_local_backup() {
    local test_dir
    local stub_dir
    local config_dir
    local source_dir
    local sbin_dir
    local dataset_name
    local vault_root
    local zfs_log
    local test_status=0

    test_dir=$(mktemp -d)
    stub_dir="$test_dir/bin"
    config_dir="$test_dir/config"
    source_dir="$test_dir/source"
    sbin_dir="$test_dir/sbin"
    dataset_name="${test_dir#/}/pool/zrb"
    vault_root="/$dataset_name/Projects/SZB"
    zfs_log="$test_dir/zfs.log"

    mkdir -p "$stub_dir" "$config_dir" "$source_dir" "$sbin_dir" "$vault_root/config" "$vault_root/data" "$vault_root/log"
    create_stub_commands "$stub_dir"
    ln -s "$TEST_ROOT/zrb.sh" "$sbin_dir/zrb.sh"
    echo "$dataset_name" > "$config_dir/backup_dataset"
    touch "$config_dir/exclude" "$vault_root/FINISHED" "$zfs_log"
    echo "$source_dir" > "$vault_root/config/source"
    echo "payload" > "$source_dir/file.txt"

    ZRB_COMMAND_PATH="$stub_dir:/usr/bin:/bin" ZFS_TEST_LOG="$zfs_log" "$sbin_dir/zrb.sh" --check -g "$config_dir" -v Projects/SZB > "$test_dir/check.out"

    assert_file_exists "$vault_root/FINISHED" || test_status=1
    assert_path_missing "$vault_root/RUNNING" || test_status=1
    assert_path_missing "$vault_root/FAILED" || test_status=1
    assert_path_missing "$vault_root/log/lock" || test_status=1
    assert_file_empty "$zfs_log" || test_status=1

    assert_file_contains "$test_dir/check.out" "PASS: Required command 'zfs'" || test_status=1
    assert_file_contains "$test_dir/check.out" "PASS: Backup dataset exists and is accessible: $dataset_name" || test_status=1
    assert_file_contains "$test_dir/check.out" "PASS: Vault dataset exists and is accessible: $dataset_name/Projects/SZB" || test_status=1
    assert_file_contains "$test_dir/check.out" "PASS: Vault configuration directory exists: $vault_root/config" || test_status=1
    assert_file_contains "$test_dir/check.out" "PASS: Vault destination directory exists: $vault_root/data" || test_status=1
    assert_file_contains "$test_dir/check.out" "PASS: Vault source file is readable: $vault_root/config/source" || test_status=1
    assert_file_contains "$test_dir/check.out" "PASS: Vault source is configured: $source_dir" || test_status=1
    assert_file_contains "$test_dir/check.out" "PASS: Global exclude file is readable: $config_dir/exclude" || test_status=1
    assert_file_contains "$test_dir/check.out" "PASS: Vault log directory is writable: $vault_root/log" || test_status=1
    assert_file_contains "$test_dir/check.out" "PASS: Local source and placeholder exist: $source_dir" || test_status=1
    assert_file_contains "$test_dir/check.out" "PASS: SSH validation is not required for a local source" || test_status=1
    assert_file_contains "$test_dir/check.out" "PASS: Retention validation is not required for mode 'no'" || test_status=1
    assert_file_contains "$test_dir/check.out" "PASS: Preflight check passed:" || test_status=1

    ZRB_COMMAND_PATH="$stub_dir:/usr/bin:/bin" ZFS_TEST_LOG="$zfs_log" "$sbin_dir/zrb.sh" -g "$config_dir" -v Projects/SZB > "$test_dir/zrb.out"

    assert_file_exists "$vault_root/FINISHED" || test_status=1
    assert_path_missing "$vault_root/RUNNING" || test_status=1
    assert_path_missing "$vault_root/FAILED" || test_status=1
    assert_path_missing "$vault_root/log/lock" || test_status=1
    assert_file_contains "$zfs_log" "$dataset_name/Projects/SZB@zrb_daily_" || test_status=1

    rm -rf "$test_dir"

    return "$test_status"
}

test_preflight_reports_multiple_failures() {
    local test_dir
    local stub_dir
    local config_dir
    local sbin_dir
    local dataset_name
    local vault_root
    local zfs_log
    local check_status
    local test_status=0

    test_dir=$(mktemp -d)
    stub_dir="$test_dir/bin"
    config_dir="$test_dir/config"
    sbin_dir="$test_dir/sbin"
    dataset_name="${test_dir#/}/pool/zrb"
    vault_root="/$dataset_name/Projects/SZB"
    zfs_log="$test_dir/zfs.log"

    mkdir -p "$stub_dir" "$config_dir" "$sbin_dir" "$vault_root/config" "$vault_root/data" "$vault_root/log"
    create_stub_commands "$stub_dir"
    ln -s "$TEST_ROOT/zrb.sh" "$sbin_dir/zrb.sh"
    echo "$dataset_name" > "$config_dir/backup_dataset"
    echo "invalid-address" > "$vault_root/config/notify"
    touch "$vault_root/config/exclude" "$zfs_log"

    ZRB_COMMAND_PATH="$stub_dir:/usr/bin:/bin" ZFS_TEST_LOG="$zfs_log" "$sbin_dir/zrb.sh" --check -g "$config_dir" -x "$test_dir/missing-exclude" -v Projects/SZB > "$test_dir/check.out" 2>&1
    check_status=$?

    assert_equal "1" "$check_status" "failed preflight status" || test_status=1
    assert_file_contains "$test_dir/check.out" "FAIL: Global exclude file is not readable: $config_dir/exclude" || test_status=1
    assert_file_contains "$test_dir/check.out" "FAIL: Command-line exclude file is not readable: $test_dir/missing-exclude" || test_status=1
    assert_file_contains "$test_dir/check.out" "FAIL: Command-line and vault exclude files are mutually exclusive" || test_status=1
    assert_file_contains "$test_dir/check.out" "FAIL: Vault notification address is invalid: invalid-address" || test_status=1
    assert_file_contains "$test_dir/check.out" "FAIL: Vault source file is not readable: $vault_root/config/source" || test_status=1
    assert_file_contains "$test_dir/check.out" "PASS: Hook is not configured: $vault_root/config/pre-run.sh" || test_status=1
    assert_file_contains "$test_dir/check.out" "PASS: Retention validation is not required for mode 'no'" || test_status=1
    assert_file_contains "$test_dir/check.out" "FAIL: Preflight check failed: 19 checks passed, 5 checks failed." || test_status=1
    assert_file_empty "$zfs_log" || test_status=1

    rm -rf "$test_dir"

    return "$test_status"
}

test_missing_remote_source_prevents_snapshot() {
    local test_dir
    local stub_dir
    local config_dir
    local sbin_dir
    local dataset_name
    local vault_root
    local zfs_log
    local backup_status
    local test_status=0

    test_dir=$(mktemp -d)
    stub_dir="$test_dir/bin"
    config_dir="$test_dir/config"
    sbin_dir="$test_dir/sbin"
    dataset_name="${test_dir#/}/pool/zrb"
    vault_root="/$dataset_name/NewBiz"
    zfs_log="$test_dir/zfs.log"

    mkdir -p "$stub_dir" "$config_dir" "$sbin_dir" "$vault_root/config" "$vault_root/data" "$vault_root/log"
    create_stub_commands "$stub_dir"
    ln -s "$TEST_ROOT/zrb.sh" "$sbin_dir/zrb.sh"
    echo "$dataset_name" > "$config_dir/backup_dataset"
    echo "backup@example.com:/missing/source" > "$vault_root/config/source"
    touch "$config_dir/exclude" "$zfs_log"

    ZRB_COMMAND_PATH="$stub_dir:/usr/bin:/bin" ZFS_TEST_LOG="$zfs_log" SSH_TEST_STATUS=1 "$sbin_dir/zrb.sh" -g "$config_dir" -v NewBiz > "$test_dir/zrb.out" 2>&1
    backup_status=$?

    assert_equal "1" "$backup_status" "missing remote source status" || test_status=1
    assert_file_contains "$test_dir/zrb.out" "ERROR: Remote source is inaccessible: backup@example.com:/missing/source" || test_status=1
    assert_file_empty "$zfs_log" || test_status=1
    assert_path_missing "$vault_root/log/lock" || test_status=1
    assert_path_missing "$vault_root/RUNNING" || test_status=1
    assert_path_missing "$vault_root/FAILED" || test_status=1

    rm -rf "$test_dir"

    return "$test_status"
}

run_test test_complete_local_backup
run_test test_preflight_reports_multiple_failures
run_test test_missing_remote_source_prevents_snapshot
