#!/bin/bash
# shellcheck disable=SC2329 # Tests are invoked by name through run_test.

set -u

# shellcheck source=test/test_helper.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

# shellcheck source=lib/zrb/config.sh
source "$TEST_ROOT/lib/zrb/config.sh"

# shellcheck source=lib/zrb/output.sh
source "$TEST_ROOT/lib/zrb/output.sh"

# shellcheck source=lib/zrb/cli.sh
source "$TEST_ROOT/lib/zrb/cli.sh"

test_defaults() {
    zrb_config_defaults

    assert_equal "tank/zrb" "$BACKUP_DATASET" "default backup dataset" &&
        assert_equal "/etc/zrb" "$GLOBAL_CONFIG_DIR" "default config directory" &&
        assert_equal "zrb" "$SNAPSHOT_PREFIX" "default snapshot prefix" &&
        assert_equal "daily" "$FREQ_LIST" "default frequency"
}

test_parse_backup_options() {
    zrb_config_defaults
    zrb_output_init
    zrb_cli_parse -v photos -p archive -f daily,weekly -e yes -x custom-exclude

    assert_equal "photos" "$vault" "vault" &&
        assert_equal "archive" "$SNAPSHOT_PREFIX" "snapshot prefix" &&
        assert_equal "daily weekly" "$FREQ_LIST" "frequency list" &&
        assert_equal "yes" "$expire" "expiration mode" &&
        assert_equal "custom-exclude" "$backup_exclude_param" "exclude file"
}

test_parse_actions() {
    zrb_config_defaults
    zrb_output_init
    zrb_cli_parse -a host:/srv -v remote
    assert_equal "host:/srv" "$data_source" "data source" &&
        assert_equal "remote" "$vault" "vault"
}

test_missing_option_value_fails() {
    zrb_config_defaults
    zrb_output_init
    ( ! zrb_cli_parse -v >/dev/null 2>&1 )
}

test_unknown_option_fails() {
    zrb_config_defaults
    zrb_output_init
    ( ! zrb_cli_parse --unknown >/dev/null 2>&1 )
}

test_global_paths() {
    zrb_config_defaults
    GLOBAL_CONFIG_DIR=/srv/zrb
    zrb_config_set_global_paths

    assert_equal "/srv/zrb/exclude" "$global_exclude" "global exclude path" &&
        assert_equal "/srv/zrb/expire" "$global_expire" "global expiration path" &&
        assert_equal "/srv/zrb/placeholder" "$global_placeholder" "placeholder path"
}

test_relative_global_path_fails() {
    zrb_config_defaults
    GLOBAL_CONFIG_DIR=etc/zrb
    ( ! zrb_config_set_global_paths )
}

test_vault_paths() {
    zrb_config_defaults
    BACKUP_DATASET=pool/backups
    zrb_config_set_vault_paths photos

    assert_equal "/pool/backups/photos/data" "$backup_vault_dest" "vault data path" &&
        assert_equal "/pool/backups/photos/config" "$backup_vault_conf" "vault config path" &&
        assert_equal "/pool/backups/photos/log" "$backup_vault_log" "vault log path"
}

test_load_notify_address() {
    local test_dir
    local notify_file
    local notify_address=""

    test_dir=$(mktemp -d)
    notify_file="$test_dir/notify_address"
    echo "alerts@example.com" > "$notify_file"

    zrb_config_load_notify_address notify_address "$notify_file"
    assert_equal "alerts@example.com" "$notify_address" "notification address"

    rm -f "$notify_file"
    rmdir "$test_dir"
}

test_default_notify_address() {
    local notify_address=""

    zrb_config_load_notify_address notify_address /does/not/exist
    assert_equal "root" "$notify_address" "default notification address"
}

failures=0
for test_name in \
    test_defaults \
    test_parse_backup_options \
    test_parse_actions \
    test_missing_option_value_fails \
    test_unknown_option_fails \
    test_global_paths \
    test_relative_global_path_fails \
    test_vault_paths \
    test_load_notify_address \
    test_default_notify_address
do
    run_test "$test_name" || failures=$((failures + 1))
done

exit "$failures"
