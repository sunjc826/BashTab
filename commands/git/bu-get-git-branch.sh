#!/usr/bin/env bash
# Pipeline: producer
# Fields: name commit upstream track date subject current
# Dispatch: source
# Synopsis: List Git branches
function __bu_bu_get_git_branch_main()
{
# --is-compatible: magic flag checked by the framework at registration time.
# Exit 0 if this command can run on the current system, non-zero otherwise.
# stderr becomes the reason shown in `bu` help.
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

local is_help=false
local format=auto
local is_all=false
local is_merged=false
local is_no_merged=false
local sort_field=
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --format)# FORMAT
        # Output format
        bu_parse_positional $# --enum ${BU_OUT_FORMATS[@]} enum-- --hint "Output format"
        format=${!shift_by}
        ;;
    -a|--all)# _FLAG
        # Include remote-tracking branches
        is_all=true
        ;;
    --merged)# _FLAG
        # Only branches whose tips are reachable from HEAD
        is_merged=true
        ;;
    --no-merged)# _FLAG
        # Only branches whose tips are not reachable from HEAD
        is_no_merged=true
        ;;
    --sort)# FIELD
        # Sort field (default: -committerdate)
        bu_parse_positional $# --enum refname committerdate authordate upstream enum-- --hint "Sort field"
        sort_field=${!shift_by}
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
    if "$is_help"
    then
        break
    fi
    if (( $# < shift_by ))
    then
        bu_parse_error_argn "$1" $#
        break
    fi
    shift "$shift_by"
done
local remaining_options=("$@")
if bu_env_is_in_autocomplete
then
    bu_autocomplete
    return 0
fi

if "$is_help"
then
    bu_autohelp \
        --description "
List git branches as structured records (git for-each-ref, no pager).
Each record: name, current (boolean), commit, upstream, track (ahead/behind),
date, subject. Sorted by most recent commit first.
" \
        --example "Local branches" "" \
        --example "Including remotes" "--all" \
        --example "Merged branches" "--merged" \
        --example "Unmerged branches" "--no-merged"
    return 0
fi

local -a ref_patterns=(refs/heads)
"$is_all" && ref_patterns+=(refs/remotes)

# Resolve --merged / --no-merged to target commit
local merge_target=
if "$is_merged" || "$is_no_merged"
then
    local -a merge_args=(--merged)
    "$is_no_merged" && merge_args=(--no-merged)
    # Find branches matching merge criteria, then use their ref patterns
    local merged_refs
    merged_refs=$(git branch "${merge_args[@]}" --format='%(refname)' 2>/dev/null) || true
    if [[ -n "$merged_refs" ]]
    then
        mapfile -t ref_patterns <<<"$merged_refs"
    else
        # No branches match — produce empty output
        bu_scope_pop_function
        return 0
    fi
fi

# Determine sort order
local sort_arg=-committerdate
[[ -n "$sort_field" ]] && sort_arg=-"$sort_field"

# TSV per branch; current marker comes from %(HEAD)
git for-each-ref "${ref_patterns[@]}" --sort="$sort_arg" \
    --format='%(refname:short)%09%(HEAD)%09%(objectname:short)%09%(upstream:short)%09%(upstream:track)%09%(committerdate:iso8601)%09%(subject)' \
    2>/dev/null \
    | bu_out_from_tsv --columns name,head,commit,upstream,track,date,subject \
    | jq -c '.current = (.head == "*") | del(.head) | .upstream |= (if . == "" then null else . end) | .track |= (if . == "" then null else . end)' \
    | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_get_git_branch_main "$@"
