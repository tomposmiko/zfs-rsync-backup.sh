#!/bin/bash
# shellcheck disable=SC2329 # Tests are invoked by name through run_test.

set -u

# shellcheck source=test/test_helper.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

# shellcheck source=lib/zrb/hooks.sh
source "$TEST_ROOT/lib/zrb/hooks.sh"

test_missing_hook_succeeds() {
    zrb_hook_run /does/not/exist
}

test_hook_executes() {
    local test_dir
    local hook_file
    local output_file

    test_dir=$(mktemp -d)
    hook_file="$test_dir/hook.sh"
    output_file="$test_dir/output"

    printf "#!/bin/bash\necho executed > %q\n" "$output_file" > "$hook_file"
    zrb_hook_run "$hook_file"

    assert_equal "executed" "$(<"$output_file")" "hook output"

    rm -f "$hook_file" "$output_file"
    rmdir "$test_dir"
}

test_hook_failure_is_returned() {
    local test_dir
    local hook_file

    test_dir=$(mktemp -d)
    hook_file="$test_dir/hook.sh"

    printf "#!/bin/bash\nexit 7\n" > "$hook_file"

    zrb_hook_run "$hook_file"
    assert_equal "7" "$?" "hook failure status"

    rm -f "$hook_file"
    rmdir "$test_dir"
}

failures=0

for test_name in \
    test_missing_hook_succeeds \
    test_hook_executes \
    test_hook_failure_is_returned
do
    run_test "$test_name" || failures=$((failures + 1))
done

exit "$failures"
