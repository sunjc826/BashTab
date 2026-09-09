#!/usr/bin/env bash
# Pipeline: producer
# Fields: remote ref status from to
# Dispatch: source
# Synopsis: Push local Git commits to a remote
function __bu_bu_push_git_ref_main()
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

local remote=origin
local ref=
local is_set_upstream=false
local is_force=false
local is_tags=false
local is_dry_run=false
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --remote)# REMOTE
        # Remote name (default: origin)
        bu_parse_positional $# --hint "Remote name"
        remote=${!shift_by}
        ;;
    --ref)# REF
        # Branch or ref to push (default: current branch)
        bu_parse_positional $# --hint "Branch or ref"
        ref=${!shift_by}
        ;;
    -u|--set-upstream)# _FLAG
        # Set the remote as upstream (git push -u)
        is_set_upstream=true
        ;;
    -f|--force)# _FLAG
        # Force push (git push -f)
        is_force=true
        ;;
    --tags)# _FLAG
        # Push tags as well (git push --tags)
        is_tags=true
        ;;
    --dry-run|--what-if)# _FLAG
        # Show what would be pushed without doing it
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
Push refs to a remote (git push).

Emits JSONL records for each ref that was pushed, with the remote and status.

Output record fields: remote, ref, status, from, to
" \
        --example "Push current branch" "" \
        --example "Push with upstream" "-u" \
        --example "Push to specific remote" "--remote upstream" \
        --example "Force push" "--force" \
        --example "Push with tags" "--tags" \
        --example "Dry run" "--dry-run"
    return 0
fi

if [[ -z "$ref" ]]; then
    ref=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || true
fi

if "$is_dry_run"; then
    local -a cmd=(git push --dry-run "$remote" "$ref")
    if "$is_force"; then cmd=(git push --force --dry-run "$remote" "$ref"); fi
    bu_out_record remote="$remote" ref="$ref" status="dry-run" | bu_out --format jsonl
    "${cmd[@]}" 2>&1 || true
    bu_scope_pop_function
    return 0
fi

local -a cmd=(git push)
"$is_set_upstream" && cmd+=(-u)
"$is_force" && cmd+=(-f)
"$is_tags" && cmd+=(--tags)
cmd+=("$remote" "$ref")
if ((${#remaining_options[@]} > 0)); then cmd+=("${remaining_options[@]}"); fi

local output
output=$("${cmd[@]}" 2>&1) || {
    error_msg="$output"
    bu_autohelp
    bu_scope_pop_function
    return 1
}

# Emit push result records
local from_commit to_commit
from_commit=$(git rev-parse --short "$ref" 2>/dev/null) || true
to_commit=$from_commit
bu_out_record remote="$remote" ref="$ref" status="pushed" from="$from_commit" to="$to_commit" | bu_out --format jsonl

bu_scope_pop_function
}

__bu_bu_push_git_ref_main "$@"
