#!/bin/bash

set -u

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
failures=0

for test_file in "$TEST_DIR"/*_test.sh; do
    bash "$test_file" || failures=$((failures + 1))
done

exit "$failures"
