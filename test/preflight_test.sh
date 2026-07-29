#!/bin/bash
# shellcheck disable=SC2329 # Tests are invoked by name through run_test.

set -u

# shellcheck source=test/test_helper.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

# shellcheck source=lib/zrb/source.sh
source "$TEST_ROOT/lib/zrb/source.sh"

# shellcheck source=lib/zrb/retention.sh
source "$TEST_ROOT/lib/zrb/retention.sh"

# shellcheck source=lib/zrb/preflight.sh
source "$TEST_ROOT/lib/zrb/preflight.sh"

test_pass_is_green() {
    local output

    C_GREEN=$'\e[1;32m'
    C_NOCOLOR=$'\e[0m'

    output=$(zrb_preflight_pass "Check passed")

    assert_equal $'\e[1;32mPASS: Check passed\e[0m' "$output" "green preflight result"
}

test_fail_is_red() {
    local output

    C_RED=$'\e[1;31m'
    C_NOCOLOR=$'\e[0m'

    output=$(zrb_preflight_fail "Check failed")

    assert_equal $'\e[1;31mFAIL: Check failed\e[0m' "$output" "red preflight result"
}

test_missing_command_reports_failure() {
    local output

    C_RED=""
    C_NOCOLOR=""

    output=$(zrb_preflight_commands zrb-command-that-does-not-exist 2>&1)

    assert_equal "FAIL: Missing required command: zrb-command-that-does-not-exist" "$output" "missing command result"
}

test_valid_hook_syntax() {
    local test_dir
    local hook_file

    test_dir=$(mktemp -d)
    hook_file="$test_dir/hook.sh"
    echo "echo valid" > "$hook_file"

    zrb_preflight_hook "$hook_file"

    rm -f "$hook_file"
    rmdir "$test_dir"
}

test_invalid_hook_syntax_fails() {
    local test_dir
    local hook_file

    test_dir=$(mktemp -d)
    hook_file="$test_dir/hook.sh"
    echo "if then" > "$hook_file"

    ( ! zrb_preflight_hook "$hook_file" > /dev/null 2>&1 )

    rm -f "$hook_file"
    rmdir "$test_dir"
}

test_missing_required_file_fails() {
    ( ! zrb_preflight_readable_file /does/not/exist "Required file" > /dev/null )
}

test_retention_no_mode_needs_no_config() {
    zrb_preflight_retention no daily /does/not/exist /does/not/exist
}

failures=0

for test_name in \
    test_pass_is_green \
    test_fail_is_red \
    test_missing_command_reports_failure \
    test_valid_hook_syntax \
    test_invalid_hook_syntax_fails \
    test_missing_required_file_fails \
    test_retention_no_mode_needs_no_config
do
    run_test "$test_name" || failures=$((failures + 1))
done

exit "$failures"
