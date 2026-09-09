#!/usr/bin/env bash
# Pipeline: transform
# Requires-All: name
# Fields: name status remote error
# Dispatch: source
# Synopsis: Delete a Git tag
function __bu_bu_remove_git_tag_main()
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

local -a tags=()
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
    -r|--remote)# _FLAG
        # Also delete from remote (git push --delete)
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
        tags+=("$1")
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
Delete git tags (git tag -d / git push --delete).

Accepts tag names as positional arguments. When no names are given and stdin
is a pipe, reads JSONL records and deletes tags from each record's .name field.

  bu get-git-tag | bu where '.name | test(\"rc\")' | bu remove-git-tag

Flags:
  --remote     Also delete from remote (git push --delete TAG)
  --dry-run    Show what would be deleted without doing it
" \
        --example "Delete local tag" "v0.1-beta" \
        --example "Delete with remote" "--remote v0.1-beta" \
        --example "From pipeline" "(pipe tag names from get-git-tag)"
    return 0
fi

# Read tags from stdin pipeline if stdin has data
if ((${#tags[@]} == 0)) && read -t 0 2>/dev/null; then
    local line
    while IFS= read -r line; do
        local t
        t=$(jq -r '.name // empty' <<<"$line" 2>/dev/null) || true
        [[ -n "$t" ]] && tags+=("$t")
    done < <(__bu_out_strict_guard "remove-git-tag")
fi

if ((${#tags[@]} == 0)); then
    error_msg="No tags specified. Provide tag names or pipe records with .name fields."
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

local t
for t in "${tags[@]}"; do
    if "$is_dry_run"; then
        bu_out_record name="$t" status="would-delete" remote:="$is_remote" | bu_out --format jsonl
        continue
    fi

    # Delete locally
    git tag -d "$t" 2>/dev/null || {
        bu_out_record name="$t" status="error" error="tag not found" | bu_out --format jsonl
        continue
    }

    # Delete remotely if requested
    if "$is_remote"; then
        git push "$remote" --delete "$t" 2>/dev/null && {
            bu_out_record name="$t" status="deleted" remote="$remote" | bu_out --format jsonl
        } || {
            bu_out_record name="$t" status="deleted-local" remote="$remote" error="remote tag not found or no permission" | bu_out --format jsonl
        }
    else
        bu_out_record name="$t" status="deleted" | bu_out --format jsonl
    fi
done

bu_scope_pop_function
}

__bu_bu_remove_git_tag_main "$@"
