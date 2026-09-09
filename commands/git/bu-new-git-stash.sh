#!/usr/bin/env bash
# Pipeline: producer
# Fields: index message status
# Dispatch: source
# Synopsis: Stash uncommitted Git changes
function __bu_bu_new_git_stash_main()
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

local message=
local is_include_untracked=false
local is_staged=false
local is_dry_run=false
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    -m|--message)# MESSAGE
        # Stash message for identification
        bu_parse_positional $# --hint "Stash description"
        message=${!shift_by}
        ;;
    -u|--include-untracked)# _FLAG
        # Include untracked files in the stash (git stash -u)
        is_include_untracked=true
        ;;
    --staged)# _FLAG
        # Stash staged changes only (git stash --staged)
        is_staged=true
        ;;
    --dry-run|--what-if)# _FLAG
        # Show what would be stashed without doing it
        is_dry_run=true
        ;;
    -h|--help)# _FLAG
        is_help=true
        ;;
    --)
        shift
        break
        ;;
    *)
        break
        ;;
    esac
    if "$is_help"; then break; fi
    if (( $# < shift_by )); then bu_parse_error_argn "$1" $#; break; fi
    shift "$shift_by"
done
local remaining_options=("$@")
if bu_env_is_in_autocomplete; then bu_autocomplete; return 0; fi

if "$is_help"; then
    bu_autohelp \
        --description "
Stash working directory changes (git stash push).

Emits a JSONL record with the stash index and message.

Output record fields: index, message, status
" \
        --example "Stash all changes" "" \
        --example "With message" "--message 'WIP on login form'" \
        --example "Include untracked" "--include-untracked" \
        --example "Stash staged only" "--staged"
    return 0
fi

if "$is_dry_run"; then
    bu_out_record status="dry-run" | bu_out --format jsonl
    # Show what would be stashed: git stash push doesn't support --dry-run,
    # but we can show what files would be affected
    local -a show_cmd=(git diff --name-only)
    "$is_staged" && show_cmd=(git diff --staged --name-only)
    "${show_cmd[@]}" 2>/dev/null | while IFS= read -r f; do
        [[ -n "$f" ]] && printf '  %s\n' "$f"
    done
    bu_scope_pop_function
    return 0
fi

local -a cmd=(git stash push)
"$is_include_untracked" && cmd+=(-u)
"$is_staged" && cmd+=(--staged)
[[ -n "$message" ]] && cmd+=(-m "$message")
if ((${#remaining_options[@]} > 0)); then cmd+=("${remaining_options[@]}"); fi

local output
output=$("${cmd[@]}" 2>&1) || {
    # "No local changes to save" is not a real error
    if [[ "$output" == *"No local changes"* ]]; then
        bu_out_record status="nothing-to-stash" | bu_out --format jsonl
        bu_scope_pop_function
        return 0
    fi
    error_msg="$output"
    bu_autohelp
    bu_scope_pop_function
    return 1
}

# Emit the new stash entry
local index=0
bu_out_record index:="$index" message:="$message" status="stashed" | bu_out --format jsonl

bu_scope_pop_function
}

__bu_bu_new_git_stash_main "$@"
