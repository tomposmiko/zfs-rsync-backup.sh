#!/bin/bash

ZRB_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=lib/zrb/client.sh
source "$ZRB_ROOT/lib/zrb/client.sh"

zrb_client_main() {
    local parse_status

    zrb_client_defaults

    zrb_client_parse_args "$@"
    parse_status=$?

    if [ "$parse_status" -eq 2 ]; then
        return 0
    fi

    if [ "$parse_status" -ne 0 ]; then
        zrb_client_usage

        return "$parse_status"
    fi

    zrb_client_apply "$CLIENT_USER" "$CLIENT_PUBLIC_KEY_FILE" "$CLIENT_DRY_RUN"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    zrb_client_main "$@"
fi
