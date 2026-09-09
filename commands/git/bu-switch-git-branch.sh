#!/usr/bin/env bash
# Pipeline: producer
# Fields: name commit previous_branch dry_run
# Dispatch: source
# Synopsis: Switch to a different Git branch
function __bu_bu_switch_git_branch_main()
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
local is_create=false
local is_force=false
local is_discard=false
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
        # Branch name to switch to
        bu_parse_positional $# --hint "Branch name"
        name=${!shift_by}
        ;;
    -c|--create)# _FLAG
        # Create the branch first, then switch (git switch -c)
        is_create=true
        ;;
    -f|--force)# _FLAG
        # Force switch, discarding local changes (git switch -f)
        is_force=true
        ;;
    --discard)# _FLAG
        # Discard local changes before switching (git switch --discard-changes)
        is_discard=true
        ;;
    --dry-run|--what-if)# _FLAG
        # Show what would happen without switching
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
        if [[ -z "$name" ]]; then
            name=$1
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
Switch to a git branch (git switch).

Emits a JSONL record with the branch name and commit after switching.

Output record fields: name, commit, previous_branch
" \
        --example "Switch to branch" "feature-x" \
        --example "Switch with --name" "--name main" \
        --example "Create and switch" "--create --name feature-y" \
        --example "Force switch" "--force main"
    return 0
fi

if [[ -z "$name" ]]; then
    error_msg="Branch name is required (e.g. bu switch-git-branch main)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

# Record current branch before switching
local previous_branch
previous_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || true

if "$is_dry_run"; then
    local commit
    commit=$(git rev-parse --short "$name" 2>/dev/null) || commit="unknown"
    bu_out_record name="$name" commit="$commit" previous_branch="$previous_branch" dry_run:=true | bu_out --format jsonl
    bu_scope_pop_function
    return 0
fi

local -a cmd=(git switch)
"$is_create" && cmd=(git switch -c "$name")
"$is_force" && cmd+=(-f)
"$is_discard" && cmd+=(--discard-changes)
if ! "$is_create"; then cmd+=("$name"); fi
if ((${#remaining_options[@]} > 0)); then cmd+=("${remaining_options[@]}"); fi

"${cmd[@]}" 2>/dev/null || {
    error_msg="Failed to switch to branch: $name"
    bu_autohelp
    bu_scope_pop_function
    return 1
}

local commit
commit=$(git rev-parse --short HEAD 2>/dev/null) || true
bu_out_record name="$name" commit="$commit" previous_branch="$previous_branch" | bu_out --format jsonl

bu_scope_pop_function
}

__bu_bu_switch_git_branch_main "$@"
