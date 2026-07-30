#!/bin/bash
# shellcheck disable=SC2329 # f_say is declared dynamically for callers of this sourced module.

zrb_output_init() {
    if [[ $- == *i* ]]; then
        QUIET_NOTIFICATIONS=0
        INTERACTIVE_SESSION=1
    fi

    if [[ ${INTERACTIVE_SESSION:-0} -eq 1 ]] || [ -t 1 ]; then
        C_GREEN="\e[1;32m"
        C_YELLOW="\e[1;33m"
        C_RED="\e[1;31m"
        C_BLUE="\e[1;34m"
        C_PURPLE="\e[1;35m"
        C_CYAN="\e[1;36m"
        C_NOCOLOR="\e[0m"
    else
        C_GREEN=""
        C_YELLOW=""
        C_RED=""
        C_BLUE=""
        C_PURPLE=""
        C_CYAN=""
        C_NOCOLOR=""
    fi

    f_say() {
        printf '%b%b\n' "$1" "$C_NOCOLOR"
    }

    export QUIET_NOTIFICATIONS INTERACTIVE_SESSION
    export C_GREEN C_YELLOW C_RED C_BLUE C_PURPLE C_CYAN C_NOCOLOR
    export -f f_say
}
