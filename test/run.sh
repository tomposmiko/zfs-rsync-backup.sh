#!/bin/bash

set -u

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TEST_FAILURES=0

for TEST_FILE in "$TEST_DIR"/*_test.sh; do
    bash "$TEST_FILE" || TEST_FAILURES=$((TEST_FAILURES + 1))
done

exit "$TEST_FAILURES"
