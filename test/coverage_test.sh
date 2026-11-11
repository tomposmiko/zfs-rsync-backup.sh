#!/bin/bash
# Tests are invoked by name in isolated Bash processes.
# shellcheck disable=SC2329
set -euo pipefail

# Standalone tests also run against Puppet's installed copy via this override.
COVERAGE_SCRIPT=${ZRB_COVERAGE_SCRIPT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/zrb-coverage.sh}
TEST_DIR=$(mktemp -d)
trap 'rm -rf -- "$TEST_DIR"' EXIT

setup_fixture() {
    CASE_DIR=$TEST_DIR/$1
    mkdir -p "$CASE_DIR/backup/Projects/ABCD/"{config,data,log} "$CASE_DIR/config"
    VAULT=$CASE_DIR/backup/Projects/ABCD
    printf '%s\n' 'samba11:ABCD:/data/Projects/ABCD' > "$CASE_DIR/inventory"
    printf '%s\n' 'backup-zrb@samba11:/data/Projects/ABCD' > "$VAULT/config/source"
    printf 'tank/zrb\t%s\tyes\ntank/zrb/Projects/ABCD\t%s\tyes\n' "$CASE_DIR/backup" "$VAULT" > "$CASE_DIR/listing"
    cat > "$CASE_DIR/zfs" <<'FAKE'
#!/bin/bash
printf '%s\n' "$@" > "${0%/*}/zfs.args"
cat "${0%/*}/listing"
FAKE
    chmod +x "$CASE_DIR/zfs"
}

check_result() {
    local expected=$1 fragment=$2 status=0
    shift 2
    if OUTPUT=$(bash "$COVERAGE_SCRIPT" --inventory "$CASE_DIR/inventory" --backup-root "$CASE_DIR/backup" --config-dir "$CASE_DIR/config" --zfs "$CASE_DIR/zfs" "$@" 2>&1); then status=0; else status=$?; fi
    if [[ $status != "$expected" || ( -n $fragment && $OUTPUT != *"$fragment"* ) ]]; then
        printf 'Expected status=%s fragment=%s; got status=%s: %s\n' "$expected" "$fragment" "$status" "$OUTPUT" >&2
        return 1
    fi
}

healthy() {
    local before after
    before=$(stat -c '%s:%y' "$VAULT/config/source")
    check_result 0 ''
    [[ -z $OUTPUT ]]
    after=$(stat -c '%s:%y' "$VAULT/config/source")
    [[ $before == "$after" ]]
    [[ $(cat "$CASE_DIR/zfs.args") == $'list\n-H\n-r\n-t\nfilesystem,volume\n-o\nname,mountpoint,mounted\ntank/zrb' ]]
    [[ $(find "$VAULT" -mindepth 1 -maxdepth 1 | wc -l) == 3 ]]
}
missing_vault() {
    printf '%s\n' 'samba12:EFGH:/tank/Projects/EFGH' >> "$CASE_DIR/inventory"
    check_result 1 'samba12/EFGH: missing vault'
    [[ $OUTPUT == $'ZRB COVERAGE FAILED: 1 problem(s), 2 expected vault(s) checked\n\nsamba12/EFGH: missing vault\n- server path: samba12:/tank/Projects/EFGH\n- vault dataset: tank/zrb/Projects/EFGH' ]]
    [[ $OUTPUT != */config/source* ]]
}
multiple_findings() {
    rm -- "$VAULT/config/source"
    touch "$VAULT/config/DISABLE"
    printf 'tank/zrb/Projects/ABCD/volume\t-\t-\n' >> "$CASE_DIR/listing"
    check_result 1 'source configuration error'
    [[ $OUTPUT == 'ZRB COVERAGE FAILED: 3 problem(s), 1 expected vault(s) checked'* ]]
    [[ $OUTPUT == *$'\n\nsamba11/ABCD: disabled vault\n- server path: samba11:/data/Projects/ABCD\n- vault dataset: tank/zrb/Projects/ABCD\n- disable marker: '* ]]
    [[ $OUTPUT == *$'\n\nsamba11/ABCD: source configuration error\n'* && $OUTPUT == *$'\n\nsamba11/ABCD: unscheduled vault\n'* ]]
}
wrong_sources() {
    local source
    for source in 'samba12:/data/Projects/ABCD' 'samba11:/data/Projects/ABCD-other' $'samba11:/data/Projects/ABCD\nsamba11:/data/Projects/ABCD'; do
        printf '%s\n' "$source" > "$VAULT/config/source"
        check_result 1 ''
    done
    for source in 'user_name@samba11:/data/Projects/ABCD' 'USER@samba11:/data/Projects/ABCD' 'user@SAMBA11:/data/Projects/ABCD'; do
        printf '%s\n' "$source" > "$VAULT/config/source"
        check_result 1 'source configuration error'
    done
    printf '%s\n' 'samba11:/data/Projects/ABCD/' > "$VAULT/config/source"
    check_result 0 ''
}
aliases() {
    printf '%s\n' 'backup@samba11.example:/tank/Projects/ABCD' > "$VAULT/config/source"
    check_result 1 'incorrect source'
    [[ $OUTPUT == *$'\n- configured source: samba11.example:/tank/Projects/ABCD\n- expected source: samba11:/data/Projects/ABCD' ]]
    check_result 0 '' --host-alias samba11.example=samba11 --path-alias /data=/tank
    check_result 2 chained --host-alias a=b --host-alias b=c
    check_result 2 chained --path-alias /a=/b --path-alias /b=/c
    check_result 2 duplicate --host-alias a=b --host-alias a=c
}
duplicate_share() {
    printf '%s\n' 'samba11:Alias:/data/Projects/ABCD' >> "$CASE_DIR/inventory"
    check_result 0 '1 expected vault(s)' --verbose
}
collision() {
    printf '%s\n' 'samba12:ABCD:/data/Projects/ABCD' >> "$CASE_DIR/inventory"
    check_result 1 'destination collision'
    [[ $OUTPUT == *$'samba12/ABCD: destination collision\n- server path: samba12:/data/Projects/ABCD\n- vault dataset: tank/zrb/Projects/ABCD\n- conflicting source: samba11:/data/Projects/ABCD' ]]
}
exclusions() {
    printf '%s\n' 'samba-dfs:Projects:/data/dfs/Projects' 'samba11:R2D2:/data/R2D2' >> "$CASE_DIR/inventory"
    check_result 1 'missing vault'
    check_result 0 '' --ignore-host samba-dfs --ignore-share r2d2
    check_result 1 'missing vault' --ignore-host samba-dfs --ignore-share R2D
}
fully_excluded() { check_result 1 'empty inventory' --ignore-host samba11; }
repository_share_exclusion() {
    printf '%s\n' 'deadline:DeadlineRepository:/data/DeadlineRepository' >> "$CASE_DIR/inventory"
    check_result 1 'deadline/DeadlineRepository: missing vault'
    check_result 0 '' --ignore-share DeadlineRepository
    check_result 0 '' --ignore-share deadlinerepository
    printf '%s\n' 'samba12:DeadlineRepository:/data/OtherRepository' >> "$CASE_DIR/inventory"
    check_result 0 '' --ignore-share DeadlineRepository
    printf '%s\n' 'deadline:DeadlineRepositoryArchive:/data/RepositoryArchive' >> "$CASE_DIR/inventory"
    check_result 1 'deadline/DeadlineRepositoryArchive: missing vault' --ignore-share DeadlineRepository
}
invalid_inventory() {
    local row
    for row in '' '# comments' 'samba11:bad:/data/../etc' 'samba11:bad:relative/path' 'samba11:bad:/data/%U' 'bad-row'; do
        printf '%s\n' "$row" > "$CASE_DIR/inventory"
        check_result 1 ''
    done
    printf '%s\n' 'samba11:bad:/opt/data' > "$CASE_DIR/inventory"
    check_result 1 'unmapped source'
}
automatic_servers() {
    local now
    now=$(date +%s)
    printf '%s\n' samba11 samba12 > "$CASE_DIR/hosts"
    printf '# zrb-inventory-v1:samba11:%s:1\nsamba11:ABCD:/data/Projects/ABCD\n' "$now" > "$CASE_DIR/inventory"
    check_result 1 'samba12: missing inventory' --hosts-file "$CASE_DIR/hosts" --max-inventory-age 36h
    [[ $OUTPUT == *'samba12: empty share inventory'* ]]
    mkdir -p "$CASE_DIR/backup/Projects/EFGH/"{config,data,log}
    printf '%s\n' 'samba12:/tank/Projects/EFGH' > "$CASE_DIR/backup/Projects/EFGH/config/source"
    printf 'tank/zrb/Projects/EFGH\t%s/backup/Projects/EFGH\tyes\n' "$CASE_DIR" >> "$CASE_DIR/listing"
    printf '# zrb-inventory-v1:samba12:%s:1\nsamba12:EFGH:/tank/Projects/EFGH\n' "$now" >> "$CASE_DIR/inventory"
    check_result 0 '' --hosts-file "$CASE_DIR/hosts" --max-inventory-age 36h
}
invalid_server_list() {
    local text
    check_result 2 '' --hosts-file "$CASE_DIR/hosts"
    for text in '' '# no servers' 'invalid;command'; do
        printf '%s\n' "$text" > "$CASE_DIR/hosts"
        check_result 2 '' --hosts-file "$CASE_DIR/hosts"
    done
    printf '%s\n' samba11 samba-dfs > "$CASE_DIR/hosts"
    check_result 0 '' --hosts-file "$CASE_DIR/hosts" --ignore-host samba-dfs
}
heartbeats() {
    local now
    now=$(date +%s)
    printf '# zrb-inventory-v1:samba11:%s:1\nsamba11:ABCD:/data/Projects/ABCD\n' "$now" > "$CASE_DIR/inventory"
    check_result 0 '' --max-inventory-age 36h
    printf '# zrb-inventory-v1:samba11:%s:1\nsamba11:ABCD:/data/Projects/ABCD\n' "$((now - 200000))" > "$CASE_DIR/inventory"
    check_result 1 'stale inventory' --max-inventory-age 36h
    printf '# zrb-inventory-v1:samba11:%s:2\nsamba11:ABCD:/data/Projects/ABCD\n' "$now" > "$CASE_DIR/inventory"
    check_result 1 'incomplete inventory'
    printf '%s\n' 'samba11:ABCD:/data/Projects/ABCD' > "$CASE_DIR/inventory"
    check_result 1 'missing inventory' --max-inventory-age 36h
    check_result 1 'samba12: empty share inventory' --expected-host samba12
    printf '# zrb-inventory-v1:samba11:%s:1\n' "$((now + 1000))" >> "$CASE_DIR/inventory"
    check_result 1 invalid/future
}
fresh_zero_share_inventory() {
    local now
    now=$(date +%s)
    printf '%s\n' samba10 samba11 > "$CASE_DIR/hosts"
    printf '# zrb-inventory-v1:samba10:%s:0\n# zrb-inventory-v1:samba11:%s:1\nsamba11:ABCD:/data/Projects/ABCD\n' "$now" "$now" > "$CASE_DIR/inventory"
    check_result 0 '' --hosts-file "$CASE_DIR/hosts" --max-inventory-age 36h
    [[ -z $OUTPUT ]]
    # No vault is required when every registered server confirms zero shares.
    printf '# zrb-inventory-v1:samba10:%s:0\n# zrb-inventory-v1:samba11:%s:0\n' "$now" "$now" > "$CASE_DIR/inventory"
    check_result 0 '0 expected vault(s)' --hosts-file "$CASE_DIR/hosts" --max-inventory-age 36h --verbose
}
unverified_zero_share_inventory() {
    local now
    now=$(date +%s)
    printf '# zrb-inventory-v1:samba10:%s:0\n' "$((now - 200000))" > "$CASE_DIR/inventory"
    check_result 1 'samba10: stale inventory' --max-inventory-age 36h
    printf '# zrb-inventory-v1:samba10:%s:0\n' "$((now + 1000))" > "$CASE_DIR/inventory"
    check_result 1 invalid/future --max-inventory-age 36h
    printf '# zrb-inventory-v1:samba10:%s:0\n' "$now" > "$CASE_DIR/inventory"
    check_result 1 'samba10: empty share inventory'
    # A verified empty server must not hide a second server with no export.
    check_result 1 'samba12: missing inventory' --expected-host samba12 --max-inventory-age 36h
    printf '%s\n' '# zrb-expected-host:samba10' > "$CASE_DIR/inventory"
    check_result 1 'samba10: missing inventory' --max-inventory-age 36h
}
inconsistent_zero_share_inventory() {
    local now
    now=$(date +%s)
    printf '# zrb-inventory-v1:samba11:%s:0\nsamba11:ABCD:/data/Projects/ABCD\n' "$now" > "$CASE_DIR/inventory"
    check_result 1 'samba11: incomplete inventory' --max-inventory-age 36h
    [[ $OUTPUT == *$'- declared shares: 0\n- received shares: 1'* ]]
    printf '# zrb-inventory-v1:samba11:%s:1\n' "$now" > "$CASE_DIR/inventory"
    check_result 1 'samba11: incomplete inventory' --max-inventory-age 36h
}
mounts() {
    printf 'tank/zrb\t%s\tyes\ntank/zrb/Projects/ABCD\t%s\tno\n' "$CASE_DIR/backup" "$VAULT" > "$CASE_DIR/listing"
    check_result 1 'unavailable vault'
    printf 'tank/zrb\t%s\tyes\ntank/zrb/Projects/ABCD\t/elsewhere\tyes\n' "$CASE_DIR/backup" > "$CASE_DIR/listing"
    check_result 1 'unavailable vault'
}
directories() {
    rmdir "$VAULT/data"
    check_result 1 'missing directory'
    rm -- "$VAULT/config/source"
    ln -s "$CASE_DIR/outside" "$VAULT/config/source"
    check_result 1 'escapes backup root'
}
dataset_config() {
    local name
    for name in backup_dataset BACKUP_DATASET; do
        printf '%s\n' tank/zrb > "$CASE_DIR/config/$name"
        check_result 0 ''
        printf '%s\n' 'tank/zrb;id' > "$CASE_DIR/config/$name"
        check_result 2 'invalid backup dataset'
        rm -- "$CASE_DIR/config/$name"
    done
}
zfs_failure() {
    printf '#!/bin/bash\nexit 1\n' > "$CASE_DIR/zfs"
    check_result 2 'audit could not run'
}
malformed_zfs() {
    local row
    for row in '' 'bad' $'another/pool\t/a\tyes' $'tank/zrb\t/a\tinvalid' $'tank/zrb\t/a\tyes\textra'; do
        printf '%s\n' "$row" > "$CASE_DIR/listing"
        check_result 2 ''
    done
}
share_names_with_spaces() {
    printf '%s\n' 'samba11:Company Files:/data/Projects/ABCD' > "$CASE_DIR/inventory"
    check_result 0 ''
    check_result 1 'empty inventory' --ignore-share 'company files'
}

nul_source() {
    printf 'samba11:/data/Projects/ABCD\000\n' > "$VAULT/config/source"
    check_result 1 'source configuration error'
}
help_and_source_safety() {
    bash "$COVERAGE_SCRIPT" --help > "$CASE_DIR/help"
    [[ ! -e $CASE_DIR/zfs.args ]]
    bash -c 'set +e +u; set +o pipefail; before=$-; source "$1"; [[ $- == "$before" ]]; [[ $(set -o | grep pipefail) == *off ]]' _ "$COVERAGE_SCRIPT"
    check_result 2 '' --unknown
    check_result 2 '' --inventory
    check_result 2 '' --max-inventory-age 0d
}

FAILED=0
for TEST in healthy missing_vault multiple_findings wrong_sources aliases duplicate_share collision exclusions fully_excluded repository_share_exclusion invalid_inventory automatic_servers invalid_server_list heartbeats fresh_zero_share_inventory unverified_zero_share_inventory inconsistent_zero_share_inventory mounts directories dataset_config zfs_failure malformed_zfs share_names_with_spaces nul_source help_and_source_safety; do
    setup_fixture "$TEST"
    export COVERAGE_SCRIPT CASE_DIR VAULT
    # Explicit subprocess preserves errexit inside each test and every assertion.
    if bash -euo pipefail -c "$(declare -f); $TEST"; then
        printf 'ok - coverage %s\n' "$TEST"
    else
        printf 'not ok - coverage %s\n' "$TEST" >&2
        FAILED=1
    fi
done
exit "$FAILED"
