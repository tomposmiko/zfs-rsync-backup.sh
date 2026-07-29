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
    test_valid_hook_syntax \
    test_invalid_hook_syntax_fails \
    test_missing_required_file_fails \
    test_retention_no_mode_needs_no_config
do
    run_test "$test_name" || failures=$((failures + 1))
done

exit "$failures"
