#!/usr/bin/env bash
# Pipeline: producer
# Fields: path xy staged unstaged orig_path
# Dispatch: source
# Synopsis: Show the Git working-tree status
function __bu_bu_get_git_status_main()
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
local is_short=false
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
    -s|--short)# _FLAG
        # Short format (git status --short instead of --porcelain=v1)
        is_short=true
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
Show the working tree status as structured records (git status --porcelain).
Each record: path, xy (staged+unstaged status codes), staged, unstaged,
orig_path (for renames). An empty working tree produces no output.

Fields: path, xy, staged, unstaged, orig_path
" \
        --example "Working tree status" "" \
        --example "Short format" "--short"
    return 0
fi

local -a cmd=(git status --porcelain=v1)
"$is_short" && cmd=(git status --short)
if ((${#remaining_options[@]} > 0)); then cmd+=("${remaining_options[@]}"); fi

# porcelain=v1 format: XY ORIG_PATH [-> NEW_PATH]
# XY is two characters: X=staged, Y=unstaged
# parse into: staged, unstaged, path, orig_path
{
    "${cmd[@]}" 2>/dev/null | while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local xy="${line:0:2}"
        local rest="${line:3}"
        local staged="${xy:0:1}"
        local unstaged="${xy:1:1}"
        local path="$rest"
        local orig_path=
        if [[ "$rest" == *" -> "* ]]; then
            orig_path="${rest%% -> *}"
            path="${rest##* -> }"
        fi
        printf '%s\t%s\t%s\t%s\t%s\n' "$path" "$xy" "$staged" "$unstaged" "$orig_path"
    done
} | bu_out_from_tsv --columns path,xy,staged,unstaged,orig_path \
  | jq -c '.orig_path |= (if . == "" then null else . end)' \
  | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_get_git_status_main "$@"
