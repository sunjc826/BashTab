#!/usr/bin/env bash
# Pipeline: producer
# Fields: branch status before after strategy
# Dispatch: source
# Synopsis: Merge a Git branch into the current branch
function __bu_bu_merge_git_branch_main()
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

local branch=
local message=
local is_squash=false
local is_ff_only=false
local is_no_ff=false
local is_abort=false
local is_dry_run=false
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --branch)# BRANCH
        # Branch to merge into the current branch
        bu_parse_positional $# --hint "Branch name"
        branch=${!shift_by}
        ;;
    -m|--message)# MESSAGE
        # Merge commit message (for --no-ff merges)
        bu_parse_positional $# --hint "Merge message"
        message=${!shift_by}
        ;;
    --squash)# _FLAG
        # Squash all commits into one before merging
        is_squash=true
        ;;
    --ff-only)# _FLAG
        # Only fast-forward, fail if a merge commit is needed
        is_ff_only=true
        ;;
    --no-ff)# _FLAG
        # Always create a merge commit
        is_no_ff=true
        ;;
    --abort)# _FLAG
        # Abort an in-progress merge (git merge --abort)
        is_abort=true
        ;;
    --dry-run|--what-if)# _FLAG
        # Show what would be merged without doing it
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
        if [[ -z "$branch" ]]; then
            branch=$1
        else
            break
        fi
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
Merge a branch into the current branch (git merge).

Emits a JSONL record with the merge result.

Output record fields: branch, status, before, after, strategy
" \
        --example "Merge feature branch" "feature-x" \
        --example "Squash merge" "--squash --branch feature-x" \
        --example "FF-only" "--ff-only feature-x" \
        --example "Abort merge" "--abort"
    return 0
fi

if "$is_abort"; then
    local -a cmd=(git merge --abort)
    if ((${#remaining_options[@]} > 0)); then cmd+=("${remaining_options[@]}"); fi
    "${cmd[@]}" 2>/dev/null || {
        error_msg="No merge in progress to abort"
        bu_autohelp
        bu_scope_pop_function
        return 1
    }
    bu_out_record status="aborted" | bu_out --format jsonl
    bu_scope_pop_function
    return 0
fi

if [[ -z "$branch" ]]; then
    error_msg="Branch name is required (e.g. bu merge-git-branch feature-x)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

local before
before=$(git rev-parse --short HEAD 2>/dev/null) || true

if "$is_dry_run"; then
    bu_out_record branch="$branch" status="dry-run" before="$before" | bu_out --format jsonl
    local -a cmd=(git merge --no-commit --no-ff "$branch")
    "${cmd[@]}" 2>&1 || true
    git merge --abort 2>/dev/null || true
    bu_scope_pop_function
    return 0
fi

local -a cmd=(git merge)
"$is_squash" && cmd+=(--squash)
"$is_ff_only" && cmd+=(--ff-only)
"$is_no_ff" && cmd+=(--no-ff)
[[ -n "$message" ]] && cmd+=(-m "$message")
cmd+=("$branch")
if ((${#remaining_options[@]} > 0)); then cmd+=("${remaining_options[@]}"); fi

local output
output=$("${cmd[@]}" 2>&1) || {
    # git merge exits non-zero on conflicts or "already up to date"
    if [[ "$output" == *"Already up to date"* ]] || [[ "$output" == *"already up to date"* ]]; then
        local after
        after=$(git rev-parse --short HEAD 2>/dev/null) || true
        bu_out_record branch="$branch" status="up-to-date" before="$before" after="$after" | bu_out --format jsonl
        bu_scope_pop_function
        return 0
    fi
    error_msg="$output"
    bu_autohelp
    bu_scope_pop_function
    return 1
}

local after
after=$(git rev-parse --short HEAD 2>/dev/null) || true
local strategy="merge"
"$is_squash" && strategy="squash"
"$is_ff_only" && strategy="fast-forward"
bu_out_record branch="$branch" status="merged" before="$before" after="$after" strategy="$strategy" | bu_out --format jsonl

bu_scope_pop_function
}

__bu_bu_merge_git_branch_main "$@"
