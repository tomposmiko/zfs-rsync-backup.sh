#!/bin/bash
# Read-only Samba share / ZRB configuration audit. Never executes backup jobs.

coverage_help() {
    cat <<'HELP'
Usage: zrb-coverage.sh [OPTIONS]
Audit Samba shares against mounted, enabled leaf ZRB vaults and exact sources.
Silent on success; cron sends failures to MAILTO. No backups or changes are made.

  --inventory FILE          Share inventory (default /tank/zrb/samba_shares.txt)
  --hosts-file FILE         Automatically collected Samba server registrations
  --config-dir DIR          Global config directory (default /etc/zrb)
  --backup-dataset DATASET  Override backup_dataset / legacy BACKUP_DATASET
  --backup-root DIR         Vault mount root (default /BACKUP_DATASET)
  --source-prefix PATH      Repeatable; defaults /data and /tank
  --ignore-host HOST        Repeatable exact exclusion
  --ignore-share SHARE      Repeatable case-insensitive exact exclusion
  --expected-host HOST      Additional expected server (normally use --hosts-file)
  --max-inventory-age AGE   Require fresh per-server headers, e.g. 36h (s/m/h/d/w)
  --host-alias OLD=CANONICAL Repeatable explicit hostname equivalence
  --path-alias OLD=CANONICAL Repeatable explicit path-prefix equivalence
  --zfs EXECUTABLE          Default /usr/sbin/zfs; only 'list' is invoked
  --verbose                Report success too
  -h, --help               Show help without querying ZFS

Exit 0: covered; 1: coverage problems; 2: audit could not run.
Checks configuration eligibility, not freshness, excludes, contents or restores.
Requires Bash 4.3+ and GNU coreutils (realpath, stat, timeout).
HELP
}

coverage_error() { printf 'ZRB COVERAGE ERROR: audit could not run\n- reason: %s\n' "$*" >&2; return 2; }

# Store complete finding blocks; the summary counts findings, not detail lines.
coverage_finding() {
    local -n findings=$1
    local block=$2 detail
    shift 2
    for detail in "$@"; do block+=$'\n- '"$detail"; done
    findings+=("$block")
}

coverage_host() { [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; }
coverage_dataset() { [[ $1 =~ ^[A-Za-z][A-Za-z0-9_.:-]*(/[A-Za-z0-9][A-Za-z0-9_.:-]*)*$ ]]; }

coverage_path() {
    local value=$1
    [[ $value == /* && $value != //* && $value != *[[:cntrl:]%]* ]] || return 1
    [[ /${value#/}/ != */./* && /${value#/}/ != */../* ]] || return 1
    while [[ $value == *//* ]]; do value=${value//\/\//\/}; done
    [[ $value == / ]] || value=${value%/}
    REPLY=$value
}

coverage_text() {
    local file=$1 size
    [[ -f $file && -r $file ]] || return 1
    if ! { size=$(stat -Lc %s -- "$file"); }; then return 1; fi
    (( size <= 1048576 )) || return 1
    # Bash cannot represent NUL bytes; reject them rather than silently ignoring them.
    if ! { cmp -s -- "$file" <(tr -d '\000' < "$file"); }; then return 1; fi
    if ! { REPLY=$(cat -- "$file"); }; then return 1; fi
}

coverage_inside() {
    local resolved
    if ! { resolved=$(realpath -m -- "$1"); }; then return 1; fi
    [[ $resolved == "$ROOT" || $resolved == "$ROOT/"* ]]
}

coverage_canonical_path() {
    local value=$1 old best=''
    for old in "${!PATH_ALIASES[@]}"; do
        if [[ $value == "$old" || $value == "$old/"* ]] && (( ${#old} > ${#best} )); then best=$old; fi
    done
    if [[ -n $best ]]; then value=${PATH_ALIASES[$best]%/}${value:${#best}}; fi
    REPLY=$value
}

coverage_main() {
    local inventory=/tank/zrb/samba_shares.txt hosts_file='' config_dir=/etc/zrb dataset='' root='' zfs=/usr/sbin/zfs max_age='' verbose=false
    local option value old new key line host share path epoch count number=0 now multiplier prefix relative vault label expected_host expected_path actual_host actual_path source_file listing mountpoint mounted extra parent best checked=0
    local -a prefixes=() errors=() entry_hosts=() entry_shares=() entry_paths=()
    local -A ignored_hosts=() ignored_shares=() expected=() epochs=() declared=() counts=() host_aliases=() path_aliases=() present=() mounts=() parents=() destinations=()
    # Dynamic scope keeps all audit state local and makes sourcing this file harmless.
    local ROOT REPLY
    local -n PATH_ALIASES=path_aliases

    while (( $# )); do
        option=$1
        case $option in
            -h|--help) coverage_help; return 0 ;;
            --verbose) verbose=true; shift; continue ;;
            --inventory|--hosts-file|--config-dir|--backup-dataset|--backup-root|--zfs|--source-prefix|--ignore-host|--ignore-share|--expected-host|--max-inventory-age|--host-alias|--path-alias)
                if (( $# < 2 )); then coverage_error "missing value for $option"; return 2; fi
                value=$2; shift 2
                if [[ -z $value ]]; then coverage_error "empty value for $option"; return 2; fi ;;
            *) coverage_error "unknown argument: $option (see --help)"; return 2 ;;
        esac
        case $option in
            --inventory) inventory=$value ;;
            --hosts-file) hosts_file=$value ;;
            --config-dir) config_dir=$value ;;
            --backup-dataset) dataset=$value; [[ -n $dataset ]] || { coverage_error 'empty backup dataset'; return 2; } ;;
            --backup-root) root=$value ;;
            --zfs) zfs=$value ;;
            --source-prefix)
                if ! { coverage_path "$value"; } || [[ $REPLY == / ]]; then coverage_error "invalid source prefix: $value"; return 2; fi
                prefixes+=("$REPLY") ;;
            --ignore-host|--expected-host)
                if ! { coverage_host "$value"; }; then coverage_error "invalid host: $value"; return 2; fi
                if [[ $option == --ignore-host ]]; then ignored_hosts[${value,,}]=1; else expected[${value,,}]=1; fi ;;
            --ignore-share) ignored_shares[${value,,}]=1 ;;
            --max-inventory-age)
                if [[ ! $value =~ ^([1-9][0-9]{0,6})([smhdw])$ ]]; then coverage_error 'use a positive age such as 36h'; return 2; fi
                case ${BASH_REMATCH[2]} in s) multiplier=1;; m) multiplier=60;; h) multiplier=3600;; d) multiplier=86400;; w) multiplier=604800;; esac
                max_age=$(( BASH_REMATCH[1] * multiplier )) ;;
            --host-alias|--path-alias)
                if [[ $value != *=* ]]; then coverage_error "invalid alias: $value"; return 2; fi
                old=${value%%=*}; new=${value#*=}
                if [[ $option == --host-alias ]]; then
                    if ! { coverage_host "$old" && coverage_host "$new"; }; then coverage_error "invalid alias: $value"; return 2; fi
                    old=${old,,}; new=${new,,}
                    if [[ $old == "$new" || -n ${host_aliases[$old]+x} ]]; then coverage_error "invalid/duplicate alias: $value"; return 2; fi
                    host_aliases[$old]=$new
                else
                    if ! { coverage_path "$old"; }; then coverage_error "invalid alias: $value"; return 2; fi
                    old=$REPLY
                    if ! { coverage_path "$new"; }; then coverage_error "invalid alias: $value"; return 2; fi
                    new=$REPLY
                    if [[ $old == "$new" || -n ${path_aliases[$old]+x} ]]; then coverage_error "invalid/duplicate alias: $value"; return 2; fi
                    path_aliases[$old]=$new
                fi ;;
        esac
    done
    # Alias targets are deliberately checked as keys to reject chains.
    # shellcheck disable=SC2302,SC2303
    for value in "${host_aliases[@]}"; do
        if [[ -n ${host_aliases[$value]+x} ]]; then coverage_error 'chained host aliases'; return 2; fi
    done
    # shellcheck disable=SC2302,SC2303
    for value in "${path_aliases[@]}"; do
        if [[ -n ${path_aliases[$value]+x} ]]; then coverage_error 'chained path aliases'; return 2; fi
    done
    if [[ -z $dataset ]]; then
        dataset=tank/zrb
        for value in backup_dataset BACKUP_DATASET; do
            if [[ -e $config_dir/$value ]]; then
                if ! { coverage_text "$config_dir/$value"; }; then coverage_error "cannot read $config_dir/$value"; return 2; fi
                dataset=$REPLY; break
            fi
        done
    fi
    if ! { coverage_dataset "$dataset"; }; then coverage_error 'invalid backup dataset configuration'; return 2; fi
    if ! { ROOT=$(realpath -m -- "${root:-/$dataset}"); }; then coverage_error 'cannot resolve backup root'; return 2; fi
    if (( ${#prefixes[@]} == 0 )); then prefixes=(/data /tank); fi
    if [[ -n $hosts_file ]]; then
        if [[ ! -f $hosts_file || ! -r $hosts_file ]]; then coverage_error "cannot read registered server list: $hosts_file"; return 2; fi
        count=0
        while IFS= read -r line || [[ -n $line ]]; do
            line=${line#"${line%%[![:space:]]*}"}; line=${line%"${line##*[![:space:]]}"}
            [[ -z $line || $line == \#* ]] && continue
            if ! { coverage_host "$line"; }; then coverage_error "invalid registered server: $line"; return 2; fi
            expected[${line,,}]=1; count=$((count + 1))
        done < "$hosts_file"
        if (( count == 0 )); then coverage_error "empty registered server list: $hosts_file"; return 2; fi
    fi
    if [[ ! -f $inventory || ! -r $inventory ]]; then coverage_error "cannot read inventory: $inventory"; return 2; fi
    if ! { now=$(date +%s); }; then coverage_error 'cannot read current time'; return 2; fi
    while IFS= read -r line || [[ -n $line ]]; do
        number=$((number + 1))
        line=${line#"${line%%[![:space:]]*}"}; line=${line%"${line##*[![:space:]]}"}
        if [[ $line == '# zrb-expected-host:'* ]]; then
            host=${line#*:}; host=${host,,}
            if { coverage_host "$host"; }; then expected[$host]=1; else coverage_finding errors "INVENTORY_ERROR: $inventory:$number" "reason: invalid expected host"; fi
        elif [[ $line == '# zrb-inventory-v1:'* ]]; then
            if [[ $line =~ ^\#\ zrb-inventory-v1:([A-Za-z0-9][A-Za-z0-9_.-]*):([0-9]{1,12}):([0-9]{1,9})$ ]]; then
                host=${BASH_REMATCH[1],,}; epoch=${BASH_REMATCH[2]}; count=${BASH_REMATCH[3]}
                if [[ -n ${epochs[$host]+x} ]]; then coverage_finding errors "INVENTORY_ERROR: $inventory:$number" "reason: duplicate header"; continue; fi
                epochs[$host]=$((10#$epoch)); declared[$host]=$((10#$count)); expected[$host]=1
            else coverage_finding errors "INVENTORY_ERROR: $inventory:$number" "reason: invalid header"; fi
        elif [[ -z $line || $line == \#* ]]; then continue
        elif [[ $line == *:*:* ]]; then
            host=${line%%:*}; value=${line#*:}; share=${value%%:*}; path=${value#*:}; host=${host,,}
            if ! { coverage_host "$host"; } || [[ -z $share || $share == *[[:cntrl:]]* ]]; then coverage_finding errors "INVENTORY_ERROR: $inventory:$number" "reason: invalid host/share"; continue; fi
            expected[$host]=1; counts[$host]=$((${counts[$host]:-0} + 1))
            if [[ -n ${ignored_hosts[$host]+x} || -n ${ignored_shares[${share,,}]+x} ]]; then continue; fi
            if ! { coverage_path "$path"; }; then coverage_finding errors "INVENTORY_ERROR: $inventory:$number" "reason: invalid concrete absolute path" "server path: $host:$path"; continue; fi
            entry_hosts+=("$host"); entry_shares+=("$share"); entry_paths+=("$REPLY")
        else coverage_finding errors "INVENTORY_ERROR: $inventory:$number" "reason: expected host:share:/absolute/path"; fi
    done < "$inventory"
    for host in "${!expected[@]}"; do
        [[ -n ${ignored_hosts[$host]+x} ]] && continue
        if [[ -n ${epochs[$host]+x} ]]; then
            epoch=${epochs[$host]}
            if (( epoch <= 0 || epoch > now + 300 )); then coverage_finding errors "INVENTORY_ERROR: $host" "reason: invalid/future generation timestamp" "inventory: $inventory"
            elif [[ -n $max_age ]] && (( now - epoch > max_age )); then coverage_finding errors "STALE_INVENTORY: $host" "inventory: $inventory" "age: $((now - epoch)) seconds" "maximum age: $max_age seconds"; fi
            if (( declared[$host] != ${counts[$host]:-0} )); then coverage_finding errors "INCOMPLETE_INVENTORY: $host" "inventory: $inventory" "declared shares: ${declared[$host]}" "received shares: ${counts[$host]:-0}"; fi
        elif [[ -n $max_age ]]; then coverage_finding errors "MISSING_INVENTORY: $host" "inventory: $inventory" "reason: no source generation header"; fi
        if (( ${counts[$host]:-0} == 0 )); then coverage_finding errors "EMPTY_HOST_INVENTORY: $host" "inventory: $inventory" "reason: no shares received"; fi
    done
    if (( ${#entry_hosts[@]} == 0 )); then coverage_finding errors "EMPTY_INVENTORY: $inventory" "reason: no expected shares remain after exclusions; coverage cannot be established"; fi
    if ! { listing=$(timeout 60 "$zfs" list -H -r -t filesystem,volume -o name,mountpoint,mounted "$dataset"); }; then coverage_error 'ZFS inventory command failed'; return 2; fi
    while IFS= read -r line; do
        if [[ $line != *$'\t'*$'\t'* ]]; then coverage_error 'malformed ZFS inventory'; return 2; fi
        key=${line%%$'\t'*}; value=${line#*$'\t'}; mountpoint=${value%%$'\t'*}; mounted=${value#*$'\t'}
        if ! { coverage_dataset "$key"; } || [[ ( $key != "$dataset" && $key != "$dataset/"* ) || -n ${present[$key]+x} || ( $mounted != yes && $mounted != no && $mounted != - ) || -z $mountpoint ]]; then coverage_error 'unexpected ZFS inventory'; return 2; fi
        present[$key]=$mounted; mounts[$key]=$mountpoint
        parent=$key
        while [[ $parent == */* ]]; do parent=${parent%/*}; parents[$parent]=1; done
    done <<< "$listing"
    if [[ -z ${present[$dataset]+x} ]]; then coverage_error 'backup root dataset absent'; return 2; fi
    for number in "${!entry_hosts[@]}"; do
        host=${entry_hosts[$number]}; share=${entry_shares[$number]}; path=${entry_paths[$number]}; label="$host/$share"; best=''
        for prefix in "${prefixes[@]}"; do
            if [[ $path == "$prefix/"* ]] && (( ${#prefix} > ${#best} )); then best=$prefix; fi
        done
        if [[ -z $best ]]; then coverage_finding errors "UNMAPPED_SOURCE: $label" "server path: $host:$path" "reason: no matching --source-prefix"; continue; fi
        relative=${path:${#best}+1}; key=$dataset/$relative; vault=$ROOT/$relative
        expected_host=${host_aliases[$host]:-$host}; coverage_canonical_path "$path"; expected_path=$REPLY
        value=$expected_host:$expected_path
        if [[ -n ${destinations[$key]+x} ]]; then
            if [[ ${destinations[$key]} != "$value" ]]; then coverage_finding errors "DESTINATION_COLLISION: $label" "server path: $host:$path" "vault dataset: $key" "conflicting source: ${destinations[$key]}"; fi
            continue
        fi
        destinations[$key]=$value; checked=$((checked + 1))
        if [[ -z ${present[$key]+x} ]]; then coverage_finding errors "MISSING_VAULT: $label" "server path: $host:$path" "vault dataset: $key"; continue; fi
        if [[ ${present[$key]} != yes || ${mounts[$key]} != "$vault" ]]; then coverage_finding errors "UNAVAILABLE_VAULT: $label" "server path: $host:$path" "vault dataset: $key" "mounted: ${present[$key]}" "mountpoint: ${mounts[$key]}" "expected mountpoint: $vault"; continue; fi
        if [[ -n ${parents[$key]+x} ]]; then coverage_finding errors "UNSCHEDULED_VAULT: $label" "server path: $host:$path" "vault dataset: $key" "reason: has child datasets; parallel-zrb.sh selects only leaf vaults"; fi
        extra=''
        for value in config data log config/DISABLE config/source; do
            if ! { coverage_inside "$vault/$value"; }; then extra="path escapes backup root: $vault/$value"; break; fi
            if [[ $value == config || $value == data || $value == log ]] && [[ ! -d $vault/$value ]]; then coverage_finding errors "MISSING_DIRECTORY: $label" "server path: $host:$path" "vault dataset: $key" "missing directory: $vault/$value"; fi
        done
        if [[ -n $extra ]]; then coverage_finding errors "SOURCE_CONFIG_ERROR: $label" "server path: $host:$path" "vault dataset: $key" "reason: $extra"; continue; fi
        if [[ -e $vault/config/DISABLE ]]; then coverage_finding errors "DISABLED_VAULT: $label" "server path: $host:$path" "vault dataset: $key" "disable marker: $vault/config/DISABLE"; fi
        source_file=$vault/config/source
        if ! { coverage_text "$source_file"; } || [[ ! $REPLY =~ ^([a-z0-9][a-z0-9.-]*@)?([a-z0-9][a-z0-9.-]*):(/.+)$ ]]; then coverage_finding errors "SOURCE_CONFIG_ERROR: $label" "server path: $host:$path" "vault dataset: $key" "source config: $source_file" "reason: invalid or unreadable source configuration"; continue; fi
        actual_host=${BASH_REMATCH[2]}; actual_path=${BASH_REMATCH[3]}
        if ! { coverage_path "$actual_path"; }; then coverage_finding errors "SOURCE_CONFIG_ERROR: $label" "server path: $host:$path" "vault dataset: $key" "source config: $source_file" "reason: invalid source path"; continue; fi
        actual_path=$REPLY; actual_host=${host_aliases[$actual_host]:-$actual_host}; coverage_canonical_path "$actual_path"; actual_path=$REPLY
        if [[ $actual_host != "$expected_host" || $actual_path != "$expected_path" ]]; then coverage_finding errors "WRONG_SOURCE: $label" "server path: $host:$path" "vault dataset: $key" "source config: $source_file" "configured source: $actual_host:$actual_path" "expected source: $expected_host:$expected_path"; fi
    done
    if (( ${#errors[@]} )); then
        printf 'ZRB COVERAGE FAILED: %s problem(s), %s expected vault(s) checked\n' "${#errors[@]}" "$checked"
        printf '\n%s\n' "${errors[@]}"
        return 1
    fi
    if [[ $verbose == true ]]; then printf 'ZRB coverage OK: %s expected vault(s) configured and eligible for parallel-zrb.sh\n' "$checked"; fi
    return 0
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    set -euo pipefail
    coverage_main "$@"
fi
