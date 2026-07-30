# Shell style

Use four spaces for each indentation level.

Do not wrap lines at 80 characters. Keep a logical statement or sentence on one line unless the language syntax or readability of a genuinely structured expression requires multiple lines.

Keep `then` on the same line as `if` or `elif`:

```bash
if [ "$status" -ne 0 ]; then
    handle_error
fi
```

Run command-based conditions directly. Use a subshell only when the command must be isolated from the caller:

```bash
if zfs create "$dataset"; then
    initialize_vault
fi

if [ -n "$vault" ]; then
    validate_vault
fi
```

Do not run functions that assign caller state inside a subshell. Capture their status before testing it:

```bash
load_config retention_period minimum_count
config_status=$?

if [ "$config_status" -ne 0 ]; then
    handle_error
fi
```

Separate logical units with a blank line. Keep related assignments together, and keep directives attached to the command they describe:

```bash
snapshot_count=${!minimum_count}

# shellcheck disable=SC2013
for snapshot in $snapshots; do
    process_snapshot "$snapshot"
done
```

Add a blank line before a terminal `exit` when output or notification precedes it:

```bash
f_say "$C_RED Backup failed"

exit 1
```

Use direct numeric comparisons instead of negated equality:

```bash
if [ "$status" -ne 0 ]; then
    handle_error
fi
```
