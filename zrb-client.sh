#!/bin/bash

ZRB_SCRIPT_PATH=${BASH_SOURCE[0]}

while [ -L "$ZRB_SCRIPT_PATH" ]; do
    ZRB_SCRIPT_DIR=$(cd -P "$(dirname "$ZRB_SCRIPT_PATH")" && pwd)
    ZRB_SCRIPT_PATH=$(readlink "$ZRB_SCRIPT_PATH")

    if [[ $ZRB_SCRIPT_PATH != /* ]]; then
        ZRB_SCRIPT_PATH="$ZRB_SCRIPT_DIR/$ZRB_SCRIPT_PATH"
    fi
done

ZRB_ROOT=$(cd -P "$(dirname "$ZRB_SCRIPT_PATH")" && pwd)

# shellcheck source=lib/zrb/version.sh
source "$ZRB_ROOT/lib/zrb/version.sh"

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
