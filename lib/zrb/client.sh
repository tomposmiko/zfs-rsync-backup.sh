#!/bin/bash
# shellcheck disable=SC2034 # Parsed values are state consumed by the client entrypoint.

zrb_client_defaults() {
    CLIENT_USER="backup-zrb"
    CLIENT_PUBLIC_KEY_FILE=""
    CLIENT_DRY_RUN=0
}

zrb_client_usage() {
    echo "Usage:"
    echo "    $0 --public-key-file <file> [--user <name>] [--dry-run]"
    echo
    echo "    --public-key-file <file>    SSH public key to authorize"
    echo "    --user <name>               backup account name [backup-zrb]"
    echo "    --dry-run                   display planned changes without applying them"
    echo "    -V, --version               display version"
    echo
}

zrb_client_parse_args() {
    local parameter

    while (($#)); do
        case "$1" in
            --public-key-file)
                parameter=${2:-}

                if [ -z "$parameter" ]; then
                    return 1
                fi

                CLIENT_PUBLIC_KEY_FILE=$parameter
                shift 2
                ;;
            --user)
                parameter=${2:-}

                if [[ ! $parameter =~ ^[a-z_][a-z0-9_-]*$ ]]; then
                    return 1
                fi

                CLIENT_USER=$parameter
                shift 2
                ;;
            --dry-run)
                CLIENT_DRY_RUN=1
                shift
                ;;
            -V|--version)
                zrb_version_print zrb-client

                return 2
                ;;
            -h|--help)
                zrb_client_usage

                return 2
                ;;
            *)
                zrb_client_usage

                return 1
                ;;
        esac
    done

    if [ -z "$CLIENT_PUBLIC_KEY_FILE" ]; then
        return 1
    fi
}

zrb_client_read_public_key() {
    local target_name=$1
    local public_key_file=$2
    local -n public_key_ref=$target_name

    if [ ! -f "$public_key_file" ]; then
        return 1
    fi

    public_key_ref=$(<"$public_key_file")

    if [[ ! $public_key_ref =~ ^(ssh-(ed25519|rsa)|ecdsa-[^[:space:]]+)[[:space:]]+[A-Za-z0-9+/=]+([[:space:]].*)?$ ]]; then
        return 1
    fi
}

zrb_client_print_plan() {
    local client_user=$1
    local client_home=$2
    local authorized_keys=$3
    local sudoers_file=$4

    echo "Install packages: sudo rsync"
    echo "Ensure user: $client_user"
    echo "Ensure home: $client_home"
    echo "Ensure authorized key in: $authorized_keys"
    echo "Validate and install sudoers policy: $sudoers_file"
}

zrb_client_install_packages() {
    apt install -y sudo rsync
}

zrb_client_ensure_user() {
    local client_user=$1
    local client_home=$2

    if { id -u "$client_user" > /dev/null 2>&1; }; then
        return 0
    fi

    useradd -m -U -s /bin/bash -d "$client_home" "$client_user"
}

zrb_client_ensure_authorized_key() {
    local client_user=$1
    local client_home=$2
    local public_key=$3
    local ssh_dir="$client_home/.ssh"
    local authorized_keys="$ssh_dir/authorized_keys"
    local -a ownership_args=(
        -o
        "$client_user"
        -g
        "$client_user"
    )

    if [ -n "${ZRB_CLIENT_ROOT:-}" ]; then
        ownership_args=()
    fi

    install -m 0700 "${ownership_args[@]}" -d "$ssh_dir" || return 1

    if [ ! -f "$authorized_keys" ]; then
        install -m 0600 "${ownership_args[@]}" /dev/null "$authorized_keys" || return 1
    fi

    if ! { grep -Fqx "$public_key" "$authorized_keys"; }; then
        echo "$public_key" >> "$authorized_keys" || return 1
    fi

    chmod 0600 "$authorized_keys" || return 1
    chown "$client_user:$client_user" "$authorized_keys"
}

zrb_client_install_sudoers() {
    local client_user=$1
    local sudoers_file=$2
    local temporary_file

    temporary_file=$(mktemp /tmp/zrb-sudoers.XXXXXX) || return 1

    printf "Cmnd_Alias C_ZRB = /usr/bin/rsync --server --sender -vlHogDtpre.iLsfxC --numeric-ids --inplace . //\n%s ALL=(ALL:ALL) NOPASSWD:C_ZRB\n" "$client_user" > "$temporary_file"

    if ! { visudo -cf "$temporary_file"; }; then
        rm -f "$temporary_file"

        return 1
    fi

    if ! { install -m 0440 "$temporary_file" "$sudoers_file"; }; then
        rm -f "$temporary_file"

        return 1
    fi

    rm -f "$temporary_file"
}

zrb_client_apply() {
    local client_user=$1
    local public_key_file=$2
    local dry_run=$3
    local root_prefix=${ZRB_CLIENT_ROOT:-}
    local client_home="$root_prefix/home/$client_user"
    local authorized_keys="$client_home/.ssh/authorized_keys"
    local sudoers_file="$root_prefix/etc/sudoers.d/zrb"
    local public_key=""

    zrb_client_read_public_key public_key "$public_key_file" || return 1

    if [ "$dry_run" -eq 1 ]; then
        zrb_client_print_plan "$client_user" "$client_home" "$authorized_keys" "$sudoers_file"

        return 0
    fi

    zrb_client_install_packages || return 1
    zrb_client_ensure_user "$client_user" "$client_home" || return 1
    zrb_client_ensure_authorized_key "$client_user" "$client_home" "$public_key" || return 1
    zrb_client_install_sudoers "$client_user" "$sudoers_file"
}
