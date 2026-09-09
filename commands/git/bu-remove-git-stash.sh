#!/usr/bin/env bash
# Pipeline: transform
# Requires-All: index
# Fields: index status error
# Dispatch: source
# Synopsis: Delete a Git stash
function __bu_bu_remove_git_stash_main()
{
# --is-compatible: magic flag checked by the framework at registration time.
if [[ "$1" == "--is-compatible" ]]; then
    command -v git &>/dev/null || { echo "git is required" >&2; exit 1; }
    git rev-parse --git-dir &>/dev/null || { echo "not inside a git repository" >&2; exit 1; }
    exit 0
fi
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local -a indices=()
local is_all=false
local is_dry_run=false
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --all)# _FLAG
        # Drop all stashes (git stash clear)
        is_all=true
        ;;
    --dry-run|--what-if)# _FLAG
        # Show what would be dropped without doing it
        is_dry_run=true
        ;;
    -h|--help)# _FLAG
        is_help=true
        ;;
    *)
        if [[ "$1" =~ ^[0-9]+$ ]]; then
            indices+=("$1")
        else
            break
        fi
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
Remove stashes (git stash drop / git stash clear).

Accepts stash indices as positional arguments (e.g. 0, 1, 2).
Use --all to clear all stashes.
Reads indices from stdin pipeline .index field if no positional args.

Output record fields: index, status
" \
        --example "Drop latest stash" "0" \
        --example "Drop specific stashes" "1 3" \
        --example "Clear all stashes" "--all"
    return 0
fi

# Read indices from stdin pipeline if stdin has data
if ((${#indices[@]} == 0)) && ! "$is_all" && read -t 0 2>/dev/null; then
    local line
    while IFS= read -r line; do
        local idx
        idx=$(jq -r '.index // empty' <<<"$line" 2>/dev/null) || true
        [[ -n "$idx" ]] && indices+=("$idx")
    done < <(__bu_out_strict_guard "remove-git-stash")
fi

if ((${#indices[@]} == 0)) && ! "$is_all"; then
    error_msg="No stashes specified. Provide stash indices or use --all."
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

if "$is_dry_run"; then
    if "$is_all"; then
        bu_out_record status="would-clear-all" | bu_out --format jsonl
    else
        local i
        for i in "${indices[@]}"; do
            bu_out_record index:="$i" status="would-drop" | bu_out --format jsonl
        done
    fi
    bu_scope_pop_function
    return 0
fi

if "$is_all"; then
    git stash clear 2>/dev/null || {
        error_msg="Failed to clear stashes"
        bu_autohelp
        bu_scope_pop_function
        return 1
    }
    bu_out_record status="cleared-all" | bu_out --format jsonl
else
    local i
    for i in "${indices[@]}"; do
        git stash drop "stash@{$i}" 2>/dev/null && {
            bu_out_record index:="$i" status="dropped" | bu_out --format jsonl
        } || {
            bu_out_record index:="$i" status="error" error="stash not found" | bu_out --format jsonl
        }
    done
fi

bu_scope_pop_function
}

__bu_bu_remove_git_stash_main "$@"
