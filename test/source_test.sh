#!/bin/bash

set -u

# shellcheck source=test/test_helper.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

test_sourcing_entrypoint_has_no_side_effects() {
    source "$TEST_ROOT/zrb.sh"
    declare -F zrb_main >/dev/null
}

run_test test_sourcing_entrypoint_has_no_side_effects
