#!/bin/bash
# shellcheck disable=SC2034 # Parsed values are state consumed by the entrypoint.

zrb_cli_require_value() {
    if [[ ! ${1:-} =~ ^[A-Za-z0-9] ]]; then
        f_say "$C_RED Missing argument!"
        return 1
    fi
}

zrb_cli_usage() {
    echo "Usage:"
    echo " $0 -v VAULT [ -p SNAPSHOT_PREFIX ] [ -f FREQUENCY ] [ -e EXPIRING ]"
    echo " $0 -a SOURCE -v VAULT"
    echo " $0 -l VAULT"
    echo
    echo "  -p|--prefix <snapshot prefix>     [zrb]"
    echo "  -v|--vault <vault>"
    echo "  -f|--freq <freq types>    hourly,[daily],weekly,monthly (comma separated list)"
    echo "  -g|--confdir <dir path>"
    echo "  -x|--exclude-file <file>  path to shared exclude file"
    echo "  -e|--expire <goal>        yes | [no] | only"
    echo "  -a|--add-vault <source>   create vault and add source"
    echo "  -l|--list <vault>         display vault"
    echo "  -q|--quiet"
    echo
}

zrb_cli_parse() {
    (($#)) || {
        zrb_cli_usage
        return 1
    }

    local parameter

    while (($#)); do
        case "$1" in
            -p|--prefix)
                parameter=${2:-}
                zrb_cli_require_value "$parameter" || return
                SNAPSHOT_PREFIX=$parameter
                shift 2
                ;;
            -v|--vault)
                parameter=${2:-}
                zrb_cli_require_value "$parameter" || return
                vault=$parameter
                shift 2
                ;;
            -e|--expire)
                parameter=${2:-}
                zrb_cli_require_value "$parameter" || return
                expire=$parameter
                shift 2
                ;;
            -f|--freq)
                parameter=${2:-}
                zrb_cli_require_value "$parameter" || return
                FREQ_LIST=${parameter//,/ }
                shift 2
                ;;
            -g|--confdir)
                parameter=${2:-}
                zrb_cli_require_value "$parameter" || return
                GLOBAL_CONFIG_DIR=$parameter
                shift 2
                ;;
            -x|--exclude-file)
                parameter=${2:-}
                zrb_cli_require_value "$parameter" || return
                backup_exclude_param=$parameter
                shift 2
                ;;
            -a|--add-vault)
                parameter=${2:-}
                zrb_cli_require_value "$parameter" || return
                data_source=$parameter
                shift 2
                ;;
            -l|--list)
                parameter=${2:-}
                zrb_cli_require_value "$parameter" || return
                vault_to_list=$parameter
                shift 2
                ;;
            -q|--quiet)
                QUIET_NOTIFICATIONS=1
                shift
                ;;
            -h|--help)
                zrb_cli_usage
                return 2
                ;;
            *)
                zrb_cli_usage
                return 1
                ;;
        esac
    done
}

# Compatibility names for callers that source the original script.
f_check_switch_param() {
    zrb_cli_require_value "$@" || exit 1
}

f_usage() {
    zrb_cli_usage

    exit 1
}

f_process_args() {
    zrb_cli_parse "$@" || exit 1
}
