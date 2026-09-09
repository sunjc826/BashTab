#!/usr/bin/env bash
# Pipeline: transform
# Requires-All: path
# Fields: path mode_before owner_before group_before mode_would_be owner_would_be group_would_be dry_run mode_after owner_after group_after error
# Dispatch: source
# Synopsis: Change file permissions and ownership
function __bu_bu_set_file_permission_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local -a paths=()
local mode=
local owner=
local group=
local is_recursive=false
local is_dry_run=false
local is_help=false
local format=auto
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --mode)# MODE
        # Permission mode: octal (755) or symbolic (u+x, g-w)
        bu_parse_positional $# --hint "Octal or symbolic mode"
        mode=${!shift_by}
        ;;
    --owner)# OWNER
        # Owner user name or UID
        bu_parse_positional $# --hint "User name or UID"
        owner=${!shift_by}
        ;;
    --group)# GROUP
        # Group name or GID
        bu_parse_positional $# --hint "Group name or GID"
        group=${!shift_by}
        ;;
    -r|--recursive)# _FLAG
        # Apply recursively to directories
        is_recursive=true
        ;;
    --dry-run|--what-if)# _FLAG
        # Show what would change without doing it
        is_dry_run=true
        ;;
    --format)# FORMAT
        bu_parse_positional $# --enum ${BU_OUT_FORMATS[@]} enum-- --hint "Output format"
        format=${!shift_by}
        ;;
    -h|--help)# _FLAG
        is_help=true
        ;;
    *)
        if bu_env_is_in_autocomplete; then
            autocompletion=("${BU_AUTOCOMPLETE_SPEC_FILE[@]}")
        fi
        paths+=("$1")
        ;;
    esac
    if "$is_help"; then break; fi
    if (( $# < shift_by )); then bu_parse_error_argn "$1" $#; break; fi
    shift "$shift_by"
done
if bu_env_is_in_autocomplete; then bu_autocomplete; return 0; fi

if "$is_help"; then
    bu_autohelp \
        --description "
Set file permissions (chmod) and ownership (chown) — PowerShell Set-Acl analog.

Accepts file paths as positional arguments. When no paths are given and stdin
is a pipe, reads JSONL records from stdin and operates on each record's .path
field:

  bu get-file /var/www | bu where '.mode | startswith(\"7\")' | bu set-file-permission --mode 755

At least one of --mode, --owner, or --group is required.  --recursive applies
changes to directories and their contents.

Output: one record per path with mode_before, mode_after, owner_before, owner_after,
group_before, group_after.
" \
        --example "Make executable" "--mode +x script.sh" \
        --example "Set octal mode" "--mode 755 bin/" \
        --example "Change owner" "--owner alice --group staff file.txt" \
        --example "Recursive" "--mode 644 --recursive src/" \
        --example "From pipeline" "(pipe file records with .path)"
    return 0
fi

if [[ -z "$mode" && -z "$owner" && -z "$group" ]]; then
    error_msg="At least one of --mode, --owner, or --group is required"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

# Read paths from stdin pipeline if none given
if ((${#paths[@]} == 0)) && read -t 0 2>/dev/null; then
    local line
    while IFS= read -r line; do
        local p
        p=$(jq -r '.path // empty' <<<"$line" 2>/dev/null) || true
        [[ -n "$p" ]] && paths+=("$p")
    done
fi

if ((${#paths[@]} == 0)); then
    error_msg="No paths specified. Provide file paths or pipe records with .path fields."
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

local p before after rc=0
{
    for p in "${paths[@]}"; do
        [[ -e "$p" && ! -L "$p" ]] || { bu_out_record path="$p" error="file not found"; rc=1; continue; }

        # Capture before state
        local mode_before owner_before group_before
        read -r mode_before owner_before group_before < <(stat -c '%a %U %G' "$p" 2>/dev/null) || true

        if "$is_dry_run"; then
            bu_out_record path="$p" mode_before="$mode_before" owner_before="$owner_before" group_before="$group_before" \
                mode_would_be="${mode:-$mode_before}" owner_would_be="${owner:-$owner_before}" group_would_be="${group:-$group_before}" \
                dry_run:=true
            continue
        fi

        # Apply mode change
        if [[ -n "$mode" ]]; then
            local -a chmod_args=()
            "$is_recursive" && chmod_args+=(-R)
            chmod "${chmod_args[@]}" "$mode" "$p" 2>/dev/null || { bu_out_record path="$p" error="chmod failed"; rc=1; continue; }
        fi

        # Apply ownership change
        if [[ -n "$owner" || -n "$group" ]]; then
            local owner_spec="${owner:-}:${group:-}"
            [[ -z "$owner" ]] && owner_spec=":${group}"
            [[ -z "$group" ]] && owner_spec="${owner}"
            local -a chown_args=()
            "$is_recursive" && chown_args+=(-R)
            chown "${chown_args[@]}" "$owner_spec" "$p" 2>/dev/null || { bu_out_record path="$p" error="chown failed"; rc=1; continue; }
        fi

        # Capture after state
        local mode_after owner_after group_after
        read -r mode_after owner_after group_after < <(stat -c '%a %U %G' "$p" 2>/dev/null) || true

        bu_out_record path="$p" \
            mode_before="$mode_before" mode_after="$mode_after" \
            owner_before="$owner_before" owner_after="$owner_after" \
            group_before="$group_before" group_after="$group_after"
    done
} | bu_out --format "$format"

bu_scope_pop_function
return $rc
}

__bu_bu_set_file_permission_main "$@"
