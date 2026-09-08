#!/usr/bin/env bash
# Pipeline: producer
# Fields: name commit message tagger tag_date
# Dispatch: source
# Synopsis: List Git tags
function __bu_bu_get_git_tag_main()
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
local pattern=
local is_annotated=false
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
    --annotated)# _FLAG
        # Show annotated tag details (message, tagger, date)
        is_annotated=true
        ;;
    -h|--help)# _FLAG
        is_help=true
        ;;
    *)
        if [[ -z "$pattern" ]]; then
            pattern=$1
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
List git tags as structured records (git tag -l, git for-each-ref refs/tags).
Each record: name, commit (short hash). With --annotated: adds message,
tagger, tag_date.

Fields: name, commit[, message, tagger, tag_date]
" \
        --example "All tags" "" \
        --example "Matching pattern" "'v1.*'" \
        --example "Annotated tags" "--annotated"
    return 0
fi

if "$is_annotated"; then
    # Annotated: use for-each-ref with tag-specific fields
    local -a cmd=(git for-each-ref refs/tags --sort=-creatordate)
    [[ -n "$pattern" ]] && cmd=(git for-each-ref "refs/tags/$pattern" --sort=-creatordate)
    if ((${#remaining_options[@]} > 0)); then cmd+=("${remaining_options[@]}"); fi

    "${cmd[@]}" \
        --format='%(refname:short)%09%(objectname:short)%09%(subject)%09%(taggername)%09%(creatordate:iso8601)' \
        2>/dev/null \
        | bu_out_from_tsv --columns name,commit,message,tagger,tag_date \
        | bu_out --format "$format"
else
    # Lightweight: just name and commit
    local -a cmd=(git tag -l)
    [[ -n "$pattern" ]] && cmd=(git tag -l "$pattern")
    if ((${#remaining_options[@]} > 0)); then cmd+=("${remaining_options[@]}"); fi

    {
        "${cmd[@]}" --format='%(refname:short)%09%(objectname:short)' 2>/dev/null
    } | bu_out_from_tsv --columns name,commit \
      | bu_out --format "$format"
fi

bu_scope_pop_function
}

__bu_bu_get_git_tag_main "$@"
