#!/bin/bash
# shellcheck disable=SC2329 # Tests are invoked by name through run_test.

set -u

# shellcheck source=test/test_helper.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

# shellcheck source=lib/zrb/snapshot.sh
source "$TEST_ROOT/lib/zrb/snapshot.sh"

ZFS_SNAPSHOT_STATUS=0
ZFS_LIST_STATUS=1
ZFS_SNAPSHOT_ARGUMENT=""
C_YELLOW=""
C_NOCOLOR=""

zfs() {
    case "$1" in
        list)
            return "$ZFS_LIST_STATUS"
            ;;
        snap)
            ZFS_SNAPSHOT_ARGUMENT=$2

            return "$ZFS_SNAPSHOT_STATUS"
            ;;
    esac
}

f_say() {
    printf '%s\n' "$1"
}

test_snapshot_name() {
    local name

    name=$(zrb_snapshot_name zrb daily 2026-07-29--12-30)

    assert_equal "zrb_daily_2026-07-29--12-30" "$name" "snapshot name"
}

test_snapshot_create() {
    ZFS_LIST_STATUS=1
    ZFS_SNAPSHOT_STATUS=0

    zrb_snapshot_create tank/zrb/photos archive weekly 2026-07-29--12-30

    assert_equal "tank/zrb/photos@archive_weekly_2026-07-29--12-30" "$ZFS_SNAPSHOT_ARGUMENT" "snapshot argument"
}

test_existing_snapshot_is_skipped() {
    local output
    local output_file

    ZFS_LIST_STATUS=0
    ZFS_SNAPSHOT_STATUS=0
    ZFS_SNAPSHOT_ARGUMENT=""

    output_file=$(mktemp)

    zrb_snapshot_create tank/zrb/photos zrb daily 2026-07-29--12-30 > "$output_file"
    output=$(<"$output_file")

    assert_equal "        WARNING: Snapshot already exists: tank/zrb/photos@zrb_daily_2026-07-29--12-30" "$output" "existing snapshot warning" &&
        assert_equal "" "$ZFS_SNAPSHOT_ARGUMENT" "existing snapshot is not created"

    rm -f "$output_file"
}

test_snapshot_failure_is_returned() {
    ZFS_LIST_STATUS=1
    ZFS_SNAPSHOT_STATUS=1

    ( ! zrb_snapshot_create tank/zrb/photos zrb daily 2026-07-29--12-30 )
}

failures=0

for test_name in \
    test_snapshot_name \
    test_snapshot_create \
    test_existing_snapshot_is_skipped \
    test_snapshot_failure_is_returned
do
    run_test "$test_name" || failures=$((failures + 1))
done

exit "$failures"
