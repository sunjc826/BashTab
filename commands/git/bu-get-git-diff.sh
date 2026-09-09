#!/usr/bin/env bash
# Pipeline: producer
# Fields: path added deleted status orig_path
# Dispatch: source
# Synopsis: Show Git working-tree differences
function __bu_bu_get_git_diff_main()
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

local is_help=false
local format=auto
local is_staged=false
local is_stat=false
local ref=
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --format)# FORMAT
        bu_parse_positional $# --enum ${BU_OUT_FORMATS[@]} enum-- --hint "Output format"
        format=${!shift_by}
        ;;
    --staged)# _FLAG
        # Show staged changes (git diff --staged)
        is_staged=true
        ;;
    --stat)# _FLAG
        # Show diffstat summary instead of file-level changes (+N -M lines)
        is_stat=true
        ;;
    -h|--help)# _FLAG
        is_help=true
        ;;
    *)
        if [[ -z "$ref" ]]; then
            ref=$1
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
Show changes between commits, the working tree, and the index as structured
records.

Without arguments: unstaged changes vs HEAD.
With --staged: staged changes vs HEAD.
With a ref: diff from that ref to HEAD (e.g. HEAD~3, main, abc1234).
Pipe remaining arguments after -- through to git diff.

File-level mode (default): one record per changed file.
Fields: status, path[, orig_path (for renames)]

--stat mode: one record per changed file with add/del counts.
Fields: path, added, deleted
" \
        --example "Unstaged changes" "" \
        --example "Staged changes" "--staged" \
        --example "Diff from a ref" "HEAD~3" \
        --example "Diffstat" "--stat" \
        --example "Staged diffstat" "--staged --stat"
    return 0
fi

if "$is_stat"; then
    # --stat / --numstat mode: lines added/deleted per file
    local -a cmd=(git diff --numstat)
    "$is_staged" && cmd=(git diff --staged --numstat)
    [[ -n "$ref" ]] && cmd=(git diff "$ref" --numstat)
    if ((${#remaining_options[@]} > 0)); then cmd+=("${remaining_options[@]}"); fi

    # numstat format: added<TAB>deleted<TAB>path
    {
        "${cmd[@]}" 2>/dev/null | while IFS=$'\t' read -r added deleted path; do
            [[ -z "$path" ]] && continue
            printf '%s\t%s\t%s\n' "$path" "$added" "$deleted"
        done
    } | bu_out_from_tsv --columns path,added,deleted \
      | bu_out --format "$format"
else
    # --name-status mode: per-file status codes
    local -a cmd=(git diff --name-status)
    "$is_staged" && cmd=(git diff --staged --name-status)
    [[ -n "$ref" ]] && cmd=(git diff "$ref" --name-status)
    if ((${#remaining_options[@]} > 0)); then cmd+=("${remaining_options[@]}"); fi

    # name-status format: STATUS<TAB>PATH [<TAB>ORIG_PATH for renames]
    # Status codes: A=added, M=modified, D=deleted, R=renamed, C=copied, T=changed, U=unmerged, X=unknown
    {
        "${cmd[@]}" 2>/dev/null | while IFS=$'\t' read -r status path orig_path; do
            [[ -z "$path" ]] && continue
            printf '%s\t%s\t%s\n' "$status" "$path" "$orig_path"
        done
    } | bu_out_from_tsv --columns status,path,orig_path \
      | jq -c '.orig_path |= (if . == "" then null else . end)' \
      | bu_out --format "$format"
fi

bu_scope_pop_function
}

__bu_bu_get_git_diff_main "$@"
