#!/bin/bash
# shellcheck disable=SC2329 # Tests are invoked by name through run_test.

set -u

# shellcheck source=test/test_helper.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

# shellcheck source=lib/zrb/output.sh
source "$TEST_ROOT/lib/zrb/output.sh"

test_noninteractive_messages_use_separate_lines() {
    local output

    INTERACTIVE_SESSION=0
    QUIET_NOTIFICATIONS=1

    output=$(
        zrb_output_init
        f_say "first message"
        f_say "second message"
    )

    assert_equal $'first message\nsecond message' "$output" "noninteractive message lines"
}

run_test test_noninteractive_messages_use_separate_lines
