#!/bin/bash
# shellcheck disable=SC2034 # TEST_ROOT is consumed by scripts that source this helper.

TEST_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

fail() {
    echo "FAIL: $*" >&2
    return 1
}

assert_equal() {
    local expected=$1
    local actual=$2
    local message=${3:-"values differ"}

    [[ $actual == "$expected" ]] || fail "$message: expected '$expected', got '$actual'"
}

run_test() {
    local name=$1

    if ( "$name" ); then
        echo "ok - $name"
    else
        echo "not ok - $name"
        return 1
    fi
}
