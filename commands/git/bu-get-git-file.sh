#!/usr/bin/env bash
# Pipeline: producer
# Fields: path revision line_number line
# Dispatch: source
# Synopsis: List files tracked by Git
function __bu_bu_get_git_file_main()
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
local revision=HEAD
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
        # Git revision (commit hash, branch, tag, HEAD~N). Default: HEAD
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
Show the contents of a file at a specific git revision as line records
(PowerShell Get-Content analog for git). Each record: path, revision,
line_number, line.

Fields: path, revision, line_number, line
" \
        --example "Current version" "src/main.c" \
        --example "At a revision" "--revision abc1234 src/main.c" \
        --example "Previous commit" "--revision HEAD~1 src/main.c"
    return 0
fi

if [[ -z "$path" ]]; then
    error_msg="Missing required file path (e.g. bu get-git-file src/main.c)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

local -a cmd=(git show "$revision:$path")
if ((${#remaining_options[@]} > 0)); then cmd+=("${remaining_options[@]}"); fi

"${cmd[@]}" 2>/dev/null | awk -v path="$path" -v rev="$revision" '
    { printf "%s\t%s\t%d\t%s\n", path, rev, NR, $0 }
' | bu_out_from_tsv --columns path,revision,line_number,line \
  | jq -c '.line_number |= tonumber' \
  | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_get_git_file_main "$@"
