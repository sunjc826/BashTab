#!/usr/bin/env bash
# Pipeline: producer
# Fields: name commit from switched_to dry_run
# Dispatch: source
# Synopsis: Create a new Git branch
function __bu_bu_new_git_branch_main()
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

local name=
local from=
local is_switch=false
local is_force=false
local is_dry_run=false
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --name)# NAME
        # Branch name (required)
        bu_parse_positional $# --hint "Branch name"
        name=${!shift_by}
        ;;
    --from)# REF
        # Starting point (branch, tag, commit). Default: HEAD
        bu_parse_positional $# --hint "Starting ref"
        from=${!shift_by}
        ;;
    -s|--switch)# _FLAG
        # Switch to the new branch after creating it
        is_switch=true
        ;;
    -f|--force)# _FLAG
        # Force create even if branch already exists (git branch -f)
        is_force=true
        ;;
    --dry-run|--what-if)# _FLAG
        # Show what would be done without doing it
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
Create a new git branch (git branch / git switch -c).

Emits a JSONL record with the branch name, commit, and whether it was switched to.

Output record fields: name, commit, switched_to (bool)
" \
        --example "Create branch" "--name feature-x" \
        --example "Create and switch" "--name feature-x --switch" \
        --example "From a specific ref" "--name hotfix --from main" \
        --example "Force overwrite" "--name feature-x --force"
    return 0
fi

if [[ -z "$name" ]]; then
    error_msg="--name is required (e.g. bu new-git-branch --name feature-x)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

if "$is_dry_run"; then
    local target="${from:-HEAD}"
    local commit
    commit=$(git rev-parse --short "$target" 2>/dev/null) || commit="unknown"
    bu_out_record name="$name" commit="$commit" from="$target" switched_to:=false dry_run:=true | bu_out --format jsonl
    bu_scope_pop_function
    return 0
fi

if "$is_switch"; then
    # git switch -c (or git checkout -b)
    local -a cmd=(git switch -c "$name")
    "$is_force" && cmd=(git checkout -B "$name")
    [[ -n "$from" ]] && cmd+=("$from")
    if ((${#remaining_options[@]} > 0)); then cmd+=("${remaining_options[@]}"); fi
    "${cmd[@]}" 2>/dev/null || {
        error_msg="Failed to create and switch to branch: $name"
        bu_autohelp
        bu_scope_pop_function
        return 1
    }
else
    local -a cmd=(git branch)
    "$is_force" && cmd+=(-f)
    cmd+=("$name")
    [[ -n "$from" ]] && cmd+=("$from")
    if ((${#remaining_options[@]} > 0)); then cmd+=("${remaining_options[@]}"); fi
    "${cmd[@]}" 2>/dev/null || {
        error_msg="Failed to create branch: $name"
        bu_autohelp
        bu_scope_pop_function
        return 1
    }
fi

local commit
commit=$(git rev-parse --short "$name" 2>/dev/null) || true
bu_out_record name="$name" commit="$commit" switched_to:="$is_switch" | bu_out --format jsonl

bu_scope_pop_function
}

__bu_bu_new_git_branch_main "$@"
