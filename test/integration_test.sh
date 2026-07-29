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
    printf '#!/bin/bash\nexit 0\n' > "$stub_dir/ssh"
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
    vault_root="/$dataset_name/photos"
    zfs_log="$test_dir/zfs.log"

    mkdir -p "$stub_dir" "$config_dir" "$source_dir" "$sbin_dir" "$vault_root/config" "$vault_root/data" "$vault_root/log"
    create_stub_commands "$stub_dir"
    ln -s "$TEST_ROOT/zrb.sh" "$sbin_dir/zrb.sh"
    echo "$dataset_name" > "$config_dir/backup_dataset"
    touch "$config_dir/exclude" "$vault_root/FINISHED" "$zfs_log"
    echo "$source_dir" > "$vault_root/config/source"
    echo "payload" > "$source_dir/file.txt"

    ZRB_COMMAND_PATH="$stub_dir:/usr/bin:/bin" ZFS_TEST_LOG="$zfs_log" "$sbin_dir/zrb.sh" --check -g "$config_dir" -v photos > "$test_dir/check.out"

    if [ -f "$vault_root/FINISHED" ] && [ ! -e "$vault_root/RUNNING" ] && [ ! -e "$vault_root/FAILED" ] && [ ! -e "$vault_root/log/lock" ] && [ ! -s "$zfs_log" ] && ( grep -Fq "Preflight check passed." "$test_dir/check.out" ); then
        :
    else
        cat "$test_dir/check.out"
        test_status=1
    fi

    ZRB_COMMAND_PATH="$stub_dir:/usr/bin:/bin" ZFS_TEST_LOG="$zfs_log" "$sbin_dir/zrb.sh" -g "$config_dir" -v photos > "$test_dir/zrb.out"

    [ -f "$vault_root/FINISHED" ] &&
        [ ! -e "$vault_root/RUNNING" ] &&
        [ ! -e "$vault_root/FAILED" ] &&
        [ ! -e "$vault_root/log/lock" ] &&
        grep -Fq "$dataset_name/photos@zrb_daily_" "$zfs_log" || test_status=1

    rm -rf "$test_dir"

    return "$test_status"
}

run_test test_complete_local_backup
