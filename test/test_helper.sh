#!/bin/bash
# shellcheck disable=SC2034 # TEST_ROOT is consumed by scripts that source this helper.

TEST_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ASSERTION_FAILED=0

fail() {
    TEST_ASSERTION_FAILED=1
    echo "FAIL: $*" >&2

    return 1
}

assert_equal() {
    local expected=$1
    local actual=$2
    local message=${3:-"values differ"}

    [[ $actual == "$expected" ]] || fail "$message: expected '$expected', got '$actual'"
}

assert_file_exists() {
    local file_path=$1

    [ -f "$file_path" ] || fail "Expected file to exist: $file_path"
}

assert_path_missing() {
    local path=$1

    [ ! -e "$path" ] || fail "Expected path to be absent: $path"
}

assert_file_empty() {
    local file_path=$1

    [ ! -s "$file_path" ] || fail "Expected file to be empty: $file_path"
}

assert_file_contains() {
    local file_path=$1
    local expected=$2

    ( grep -Fq "$expected" "$file_path" ) || fail "Expected '$file_path' to contain: $expected"
}

run_test() {
    local name=$1

    if ( TEST_ASSERTION_FAILED=0; "$name"; test_status=$?; [ "$TEST_ASSERTION_FAILED" -eq 0 ] && [ "$test_status" -eq 0 ] ); then
        echo "ok - $name"
    else
        echo "not ok - $name"
        return 1
    fi
}
