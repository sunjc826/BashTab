#!/usr/bin/env bash
# Pipeline: producer
# Fields: name url kind
# Dispatch: source
# Synopsis: List Git remote repositories
function __bu_bu_get_git_remote_main()
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
local is_verbose=false
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
    -v|--verbose)# _FLAG
        # Show fetch and push URLs separately
        is_verbose=true
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
List git remotes as structured records (git remote -v).
Each record: name, url, kind (fetch or push).

Fields: name, url, kind
" \
        --example "All remotes" "" \
        --example "Verbose" "--verbose"
    return 0
fi

local -a cmd=(git remote -v)
if ((${#remaining_options[@]} > 0)); then cmd+=("${remaining_options[@]}"); fi

# git remote -v format:
# origin<TAB>https://github.com/user/repo.git (fetch)
# Parse with awk for reliable tab handling
"${cmd[@]}" 2>/dev/null | awk -F'\t' '{
    name = $1
    url_and_kind = $2
    # Extract URL (before the last parenthetical)
    kind = url_and_kind
    gsub(/.*\(/, "", kind)
    gsub(/\).*/, "", kind)
    url = url_and_kind
    gsub(/ \(.*/, "", url)
    if (name != "") printf "%s\t%s\t%s\n", name, url, kind
}' \
    | bu_out_from_tsv --columns name,url,kind \
  | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_get_git_remote_main "$@"
