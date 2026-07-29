#!/bin/bash
# shellcheck disable=SC2329 # Tests are invoked by name through run_test.

set -u

# shellcheck source=test/test_helper.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

# shellcheck source=lib/zrb/report.sh
source "$TEST_ROOT/lib/zrb/report.sh"

DATE_COUNTER_FILE=""
C_GREEN=""
C_BLUE=""

date() {
    if [ "$1" == "+%s" ]; then
        local epoch_calls

        epoch_calls=$(<"$DATE_COUNTER_FILE")
        epoch_calls=$((epoch_calls + 1))
        echo "$epoch_calls" > "$DATE_COUNTER_FILE"

        if [ "$epoch_calls" -eq 1 ]; then
            echo 100
        else
            echo 3700
        fi

        return
    fi

    case "$2" in
        "@100")
            echo "2026-07-29 12:00"
            ;;
        "@3700")
            echo "2026-07-29 13:00"
            ;;
    esac
}

f_say() {
    :
}

test_format_duration() {
    local duration

    duration=$(zrb_report_format_duration 90061)

    assert_equal "1 day(s) 01:01:01" "$duration" "formatted duration"
}

test_write_report() {
    local test_dir
    local report_file
    local start_epoch=0

    test_dir=$(mktemp -d)
    report_file="$test_dir/report.txt"
    DATE_COUNTER_FILE="$test_dir/date-counter"
    echo 0 > "$DATE_COUNTER_FILE"

    zrb_report_begin start_epoch "$report_file" 1
    zrb_report_finish "$report_file" "$start_epoch" 1

    assert_equal $'BEGIN:\t2026-07-29 12:00\nFINISH:\t2026-07-29 13:00\nDELTA: 0 day(s) 01:00:00 (3600 sec)' "$(<"$report_file")" "report contents"

    rm -f "$report_file" "$DATE_COUNTER_FILE"
    rmdir "$test_dir"
}

failures=0

for test_name in \
    test_format_duration \
    test_write_report
do
    run_test "$test_name" || failures=$((failures + 1))
done

exit "$failures"
