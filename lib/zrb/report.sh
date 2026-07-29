#!/bin/bash
# shellcheck disable=SC2034 # Nameref assignments provide outputs to callers.

zrb_report_format_duration() {
    local duration_seconds=$1

    printf "%d day(s) %02d:%02d:%02d\n" "$((duration_seconds / 86400))" "$((duration_seconds / 3600 % 24))" "$((duration_seconds / 60 % 60))" "$((duration_seconds % 60))"
}

zrb_report_begin() {
    local target_name=$1
    local report_file=$2
    local quiet_notifications=$3
    local -n start_epoch_ref=$target_name
    local start_human

    start_epoch_ref=$(date "+%s")
    start_human=$(date -d "@$start_epoch_ref" "+%Y-%m-%d %H:%M")

    printf "BEGIN:\t%s\n" "$start_human" > "$report_file"

    if [ "$quiet_notifications" -eq 0 ]; then
        f_say "$C_GREEN  START:$C_BLUE $start_human"
    fi
}

zrb_report_finish() {
    local report_file=$1
    local start_epoch=$2
    local quiet_notifications=$3
    local finish_epoch
    local finish_human
    local duration_epoch
    local duration_human

    finish_epoch=$(date "+%s")
    finish_human=$(date -d "@$finish_epoch" "+%Y-%m-%d %H:%M")

    printf "FINISH:\t%s\n" "$finish_human" >> "$report_file"

    if [ "$quiet_notifications" -eq 0 ]; then
        f_say "$C_GREEN  FINISH:$C_BLUE $finish_human"
    fi

    duration_epoch=$((finish_epoch - start_epoch))
    duration_human=$(zrb_report_format_duration "$duration_epoch")

    echo "DELTA: $duration_human ($duration_epoch sec)" >> "$report_file"

    if [ "$quiet_notifications" -eq 0 ]; then
        f_say "$C_GREEN  DELTA:$C_BLUE $duration_human"
    fi
}
