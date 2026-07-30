#!/bin/bash
# shellcheck disable=SC2329 # Tests are invoked by name through run_test.

set -u

# shellcheck source=test/test_helper.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

test_active_commands_report_version() {
    local zrb_version
    local parallel_version
    local client_version

    zrb_version=$("$TEST_ROOT/zrb.sh" --version)
    parallel_version=$("$TEST_ROOT/parallel-zrb.sh" --version)
    client_version=$("$TEST_ROOT/zrb-client.sh" --version)

    assert_equal "zrb 0.6" "$zrb_version" "zrb version" &&
        assert_equal "parallel-zrb 0.6" "$parallel_version" "parallel version" &&
        assert_equal "zrb-client 0.6" "$client_version" "client version"
}

run_test test_active_commands_report_version
