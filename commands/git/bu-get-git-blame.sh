#!/usr/bin/env bash
# Pipeline: producer
# Fields: line_number commit author author_date line
# Dispatch: source
# Synopsis: Show line-by-line Git authorship information
function __bu_bu_get_git_blame_main()
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
local path=
local revision=
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
    -r|--revision)# REVISION
        # Blame at a specific revision (default: HEAD)
        bu_parse_positional $# --hint "Revision (commit, tag, branch)"
        revision=${!shift_by}
        ;;
    -h|--help)# _FLAG
        is_help=true
        ;;
    *)
        if bu_env_is_in_autocomplete; then
            autocompletion=("${BU_AUTOCOMPLETE_SPEC_FILE[@]}")
        fi
        if [[ -z "$path" ]]; then
            path=$1
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
Show line-by-line authorship (git blame --line-porcelain).
Each record: line_number, commit, author, author_date, line.

Fields: line_number, commit, author, author_date, line
" \
        --example "Blame a file" "src/main.c" \
        --example "At a revision" "--revision HEAD~5 src/main.c"
    return 0
fi

if [[ -z "$path" ]]; then
    error_msg="Missing required file path (e.g. bu get-git-blame src/main.c)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

local -a cmd=(git blame --line-porcelain)
[[ -n "$revision" ]] && cmd+=("$revision")
cmd+=("$path")
if ((${#remaining_options[@]} > 0)); then cmd+=("${remaining_options[@]}"); fi

# git blame --line-porcelain outputs blocks of headers then a TAB-indented line.
# Block: commit hash line, then key value pairs, then TAB + content line.
# We extract: commit, author, author-time, and the tab-indented line.
"${cmd[@]}" 2>/dev/null | awk '
    BEGIN { commit=""; author=""; author_date="" }
    /^[0-9a-f]{40} / {
        # first line of block: commit_hash line_number final_line_number
        commit = substr($0, 1, 40)
        line_num = $2
        next
    }
    /^author /   { author = substr($0, 8) }
    /^author-time / { author_date = substr($0, 13) }
    /^\t/ {
        # The actual source line (tab-indented)
        line = substr($0, 2)
        printf "%s\t%s\t%s\t%s\t%s\n", line_num, commit, author, author_date, line
        commit=""; author=""; author_date=""; line_num=""
    }
' 2>/dev/null \
    | bu_out_from_tsv --columns line_number,commit,author,author_date,line \
    | jq -c '.line_number |= tonumber | .author_date |= tonumber' \
    | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_get_git_blame_main "$@"
