#!/bin/bash
# shellcheck disable=SC2329 # Tests are invoked by name through run_test.

set -u

# shellcheck source=test/test_helper.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

# shellcheck source=lib/zrb/source.sh
source "$TEST_ROOT/lib/zrb/source.sh"

# shellcheck source=lib/zrb/retention.sh
source "$TEST_ROOT/lib/zrb/retention.sh"

# shellcheck source=lib/zrb/vault.sh
source "$TEST_ROOT/lib/zrb/vault.sh"

# shellcheck source=lib/zrb/preflight.sh
source "$TEST_ROOT/lib/zrb/preflight.sh"

test_pass_is_green() {
    local output

    C_GREEN=$'\e[1;32m'
    C_NOCOLOR=$'\e[0m'

    output=$(zrb_preflight_pass "Check passed")

    assert_equal $'\e[1;32mPASS\e[0m: Check passed' "$output" "green preflight result"
}

test_fail_is_red() {
    local output

    C_RED=$'\e[1;31m'
    C_NOCOLOR=$'\e[0m'

    output=$(zrb_preflight_fail "Check failed")

    assert_equal $'\e[1;31mFAIL\e[0m: Check failed' "$output" "red preflight result"
}

test_missing_command_reports_failure() {
    local output

    C_RED=""
    C_NOCOLOR=""

    output=$(zrb_preflight_commands zrb-command-that-does-not-exist 2>&1)

    assert_equal "FAIL: Missing required command: zrb-command-that-does-not-exist" "$output" "missing command result"
}

test_command_check_reports_all_results() {
    local output
    local status

    output=$(zrb_preflight_commands bash zrb-missing-command-one zrb-missing-command-two 2>&1)
    status=$?

    [[ $output == *"PASS: Required command 'bash'"* ]] || fail "Expected the available command result"
    [[ $output == *"FAIL: Missing required command: zrb-missing-command-one"* ]] || fail "Expected the first missing command result"
    [[ $output == *"FAIL: Missing required command: zrb-missing-command-two"* ]] || fail "Expected the second missing command result"

    assert_equal "1" "$status" "aggregated command check status"
}

test_success_summary_reports_count() {
    local output

    ZRB_PREFLIGHT_PASS_COUNT=4
    ZRB_PREFLIGHT_FAIL_COUNT=0

    output=$(zrb_preflight_summary 0)

    assert_equal $'\nPASS: Preflight check passed: 4 checks passed.' "$output" "successful preflight summary"
}

test_failure_summary_reports_counts() {
    local output

    ZRB_PREFLIGHT_PASS_COUNT=3
    ZRB_PREFLIGHT_FAIL_COUNT=2

    output=$(zrb_preflight_summary 1)

    assert_equal $'\nFAIL: Preflight check failed: 3 checks passed, 2 checks failed.' "$output" "failed preflight summary"
}

test_conflicting_excludes_fail() {
    local test_dir
    local parameter_exclude_file
    local vault_exclude_file

    test_dir=$(mktemp -d)

    parameter_exclude_file="$test_dir/parameter-exclude"
    vault_exclude_file="$test_dir/vault-exclude"

    touch "$parameter_exclude_file" "$vault_exclude_file"

    ( ! zrb_preflight_excludes "$parameter_exclude_file" "$vault_exclude_file" > /dev/null )

    rm -f "$parameter_exclude_file" "$vault_exclude_file"
    rmdir "$test_dir"
}

test_invalid_notify_address_fails() {
    local test_dir
    local notify_file

    test_dir=$(mktemp -d)

    notify_file="$test_dir/notify"

    echo "invalid-address" > "$notify_file"

    ( ! zrb_preflight_notify_address "$notify_file" > /dev/null )

    rm -f "$notify_file"
    rmdir "$test_dir"
}

test_retention_values_survive_validation() {
    local test_dir
    local global_config
    local output

    test_dir=$(mktemp -d)

    global_config="$test_dir/expire"

    echo 'expire_daily="2 weeks"' > "$global_config"
    echo 'least_keep_count_daily=3' >> "$global_config"

    output=$(zrb_preflight_retention yes daily "$global_config" "$test_dir/vault-expire")

    assert_equal "PASS: Retention configuration is valid for 'daily': period '2 weeks', minimum '3'" "$output" "retention preflight values"

    rm -f "$global_config"
    rmdir "$test_dir"
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
    test_command_check_reports_all_results \
    test_success_summary_reports_count \
    test_failure_summary_reports_counts \
    test_conflicting_excludes_fail \
    test_invalid_notify_address_fails \
    test_retention_values_survive_validation \
    test_valid_hook_syntax \
    test_invalid_hook_syntax_fails \
    test_missing_required_file_fails \
    test_retention_no_mode_needs_no_config
do
    run_test "$test_name" || failures=$((failures + 1))
done

exit "$failures"
