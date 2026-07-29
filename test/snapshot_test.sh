#!/bin/bash
# shellcheck disable=SC2329 # Tests are invoked by name through run_test.

set -u

# shellcheck source=test/test_helper.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

# shellcheck source=lib/zrb/snapshot.sh
source "$TEST_ROOT/lib/zrb/snapshot.sh"

ZFS_SNAPSHOT_STATUS=0
ZFS_SNAPSHOT_ARGUMENT=""

zfs() {
    if [ "$1" == snap ]; then
        ZFS_SNAPSHOT_ARGUMENT=$2
    fi

    return "$ZFS_SNAPSHOT_STATUS"
}

test_snapshot_name() {
    local name

    name=$(zrb_snapshot_name zrb daily 2026-07-29--12-30)

    assert_equal "zrb_daily_2026-07-29--12-30" "$name" "snapshot name"
}

test_snapshot_create() {
    ZFS_SNAPSHOT_STATUS=0
    zrb_snapshot_create tank/zrb/photos archive weekly 2026-07-29--12-30

    assert_equal "tank/zrb/photos@archive_weekly_2026-07-29--12-30" "$ZFS_SNAPSHOT_ARGUMENT" "snapshot argument"
}

test_snapshot_failure_is_returned() {
    ZFS_SNAPSHOT_STATUS=1
    ( ! zrb_snapshot_create tank/zrb/photos zrb daily 2026-07-29--12-30 )
}

failures=0

for test_name in \
    test_snapshot_name \
    test_snapshot_create \
    test_snapshot_failure_is_returned
do
    run_test "$test_name" || failures=$((failures + 1))
done

exit "$failures"
