#!/usr/bin/env bash
# Pipeline: consume
# Requires-All: name
# Dispatch: source
# Synopsis: Delete a Git branch
function __bu_bu_remove_git_branch_main()
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

local -a branches=()
local is_force=false
local is_remote=false
local remote=origin
local is_dry_run=false
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    -f|--force)# _FLAG
        # Force delete even if not merged (git branch -D)
        is_force=true
        ;;
    -r|--remote)# _FLAG
        # Delete a remote-tracking branch (git push --delete)
        is_remote=true
        ;;
    --remote-name)# REMOTE
        # Remote name for --remote (default: origin)
        bu_parse_positional $# --hint "Remote name"
        remote=${!shift_by}
        ;;
    --dry-run|--what-if)# _FLAG
        # Show what would be deleted without doing it
        is_dry_run=true
        ;;
    -h|--help)# _FLAG
        is_help=true
        ;;
    *)
        branches+=("$1")
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
Delete git branches (git branch -d / git push --delete).

Accepts branch names as positional arguments. When no names are given and
stdin is a pipe, reads JSONL records and deletes branches from each record's
.name field. This enables composability:

  bu get-git-branch --merged | bu where '.current != true' | bu remove-git-branch

Flags:
  --force      Force delete even if not merged (git branch -D)
  --remote     Delete from remote (git push --delete)
  --dry-run    Show what would be deleted without doing it
" \
        --example "Delete local branch" "old-feature" \
        --example "Force delete" "--force stale-branch" \
        --example "Delete remote branch" "--remote stale-branch" \
        --example "From pipeline" "(read merged branches from pipe...)"
    return 0
fi

# Read branches from stdin pipeline if no positional args and stdin has data
if ((${#branches[@]} == 0)) && read -t 0 2>/dev/null; then
    local line
    while IFS= read -r line; do
        local b
        b=$(jq -r '.name // empty' <<<"$line" 2>/dev/null) || true
        [[ -n "$b" ]] && branches+=("$b")
    done
fi

if ((${#branches[@]} == 0)); then
    error_msg="No branches specified. Provide branch names or pipe records with .name fields."
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

local b deleted=()
for b in "${branches[@]}"; do
    if "$is_dry_run"; then
        bu_out_record name="$b" status="would-delete" remote:="$is_remote" | bu_out --format jsonl
        continue
    fi
    if "$is_remote"; then
        git push "$remote" --delete "$b" 2>/dev/null && {
            bu_out_record name="$b" status="deleted" remote="$remote" | bu_out --format jsonl
            deleted+=("$b")
        } || {
            bu_out_record name="$b" status="error" remote="$remote" error="failed to delete remote branch" | bu_out --format jsonl
        }
    else
        local flag=-d
        "$is_force" && flag=-D
        git branch "$flag" "$b" 2>/dev/null && {
            bu_out_record name="$b" status="deleted" | bu_out --format jsonl
            deleted+=("$b")
        } || {
            bu_out_record name="$b" status="error" error="branch not found or not fully merged (use --force)" | bu_out --format jsonl
        }
    fi
done

bu_scope_pop_function
}

__bu_bu_remove_git_branch_main "$@"
