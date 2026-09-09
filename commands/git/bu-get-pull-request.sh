#!/usr/bin/env bash
# Pipeline: producer
# Dispatch: source
# Synopsis: List GitHub pull requests via the gh CLI
# Fields: number title state author branch base is_draft url updated_at
function __bu_bu_get_pull_request_main()
{
# --is-compatible: magic flag checked by the framework at registration time.
if [[ "$1" == "--is-compatible" ]]; then
    command -v gh &>/dev/null || { echo "gh (GitHub CLI) is required" >&2; exit 1; }
    exit 0
fi

local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local repo=
local state=
local is_mine=false
local limit=
local format=auto
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --state)# STATE
        # Filter by PR state
        bu_parse_positional $# --enum open closed merged all enum-- --hint "PR state"
        state=${!shift_by}
        ;;
    --mine)# _FLAG
        # Only PRs authored by the current user (@me)
        is_mine=true
        ;;
    --limit)# LIMIT
        # Maximum number of PRs to return
        bu_parse_positional $# --hint "Number of PRs"
        limit=${!shift_by}
        ;;
    --format)# FORMAT
        # Output format
        bu_parse_positional $# --enum ${BU_OUT_FORMATS[@]} enum-- --hint "Output format"
        format=${!shift_by}
        ;;
    -h|--help)# _FLAG
        # Print help
        is_help=true
        ;;
    *)
        if bu_env_is_in_autocomplete && [[ "$1" != -* ]]
        then
            autocompletion=(--stdout bu_repo_names stdout-- --hint "Repo name (registered) or OWNER/REPO")
        fi
        if [[ -z "$repo" ]]
        then
            repo=$1
        else
            bu_parse_error_enum "$1"
        fi
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

if bu_env_is_in_autocomplete
then
    bu_autocomplete
    return 0
fi

if "$is_help"
then
    bu_autohelp \
        --description "
List pull requests via the gh CLI (JSONL records). --repo may be a registered
repo name (resolved through the repo registry, exporting GH_HOST when the host
differs from github.com) or a literal OWNER/REPO slug; without --repo gh uses
the current directory.
" \
        --example "PRs in the current repo" "" \
        --example "Open PRs in a registered repo" "myrepo --state open" \
        --example "My open PRs, latest 10" "--mine --state open --limit 10"
    return 0
fi

# Resolve a registered repo name to slug+host; fall back to literal slug.
local repo_spec=
local gh_host=
if [[ -n "$repo" ]]
then
    if bu_repo_resolve_slug "$repo" 2>/dev/null
    then
        repo_spec=$BU_RET
        gh_host=${BU_RET_MAP[host]}
    else
        repo_spec=$repo
    fi
fi

local -a gh_args=(pr list --json 'number,title,state,author,headRefName,baseRefName,isDraft,url,updatedAt')
if [[ -n "$repo_spec" ]]
then
    gh_args+=(--repo "$repo_spec")
fi
[[ -n "$state" ]] && gh_args+=(--state "$state")
if "$is_mine"
then
    gh_args+=(--author '@me')
fi
[[ -n "$limit" ]] && gh_args+=(--limit "$limit")

{
    if [[ -n "$gh_host" && "$gh_host" != github.com ]]
    then
        GH_HOST="$gh_host" gh "${gh_args[@]}"
    else
        gh "${gh_args[@]}"
    fi
} | "$BU_OUT_JQ" -c '.[] | {number, title, state, author: (.author.login? // ""), branch: .headRefName, base: .baseRefName, is_draft: .isDraft, url, updated_at: .updatedAt}' \
  | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_get_pull_request_main "$@"
