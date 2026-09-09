#!/usr/bin/env bash
# Pipeline: producer
# Fields: index action status
# Dispatch: source
# Synopsis: Restore files from a Git stash
function __bu_bu_restore_git_stash_main()
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

local index=0
local is_pop=true
local is_index=false
local is_dry_run=false
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --index)# _FLAG
        # Also restore the staged state (git stash pop --index)
        is_index=true
        ;;
    --apply)# _FLAG
        # Apply without removing from stash (default: pop)
        is_pop=false
        ;;
    --dry-run|--what-if)# _FLAG
        # Show what would be restored without doing it
        is_dry_run=true
        ;;
    -h|--help)# _FLAG
        is_help=true
        ;;
    *)
        if [[ "$1" =~ ^[0-9]+$ ]]; then
            index=$1
        elif [[ "$1" == stash@\{*\} ]]; then
            index="${1#stash@\{}"
            index="${index%\}}"
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
Restore stashed changes (git stash pop / git stash apply).

Default: pop (restore and remove from stash). Use --apply to keep the stash.

Emits a JSONL record with the stash index and action taken.

Output record fields: index, action (popped/applied), status
" \
        --example "Pop latest stash" "" \
        --example "Pop specific stash" "2" \
        --example "Apply without dropping" "--apply" \
        --example "Restore index (staged state)" "--index"
    return 0
fi

local action="pop"
"$is_pop" || action="apply"

if "$is_dry_run"; then
    bu_out_record index:="$index" action="$action" status="dry-run" | bu_out --format jsonl
    local -a cmd=(git stash show "stash@{$index}")
    "${cmd[@]}" 2>&1 || true
    bu_scope_pop_function
    return 0
fi

local -a cmd=(git stash)
"$is_pop" && cmd=(git stash pop) || cmd=(git stash apply)
"$is_index" && cmd+=(--index)
cmd+=("stash@{$index}")

local output
output=$("${cmd[@]}" 2>&1) || {
    if [[ "$output" == *"No stash"* ]] || [[ "$output" == *"not found"* ]]; then
        error_msg="Stash@{$index} not found"
    elif [[ "$output" == *"conflict"* ]] || [[ "$output" == *"CONFLICT"* ]]; then
        bu_out_record index:="$index" action="$action" status="conflict" | bu_out --format jsonl
        bu_scope_pop_function
        return 0
    else
        error_msg="$output"
    fi
    bu_autohelp
    bu_scope_pop_function
    return 1
}

bu_out_record index:="$index" action="$action" status="restored" | bu_out --format jsonl

bu_scope_pop_function
}

__bu_bu_restore_git_stash_main "$@"
