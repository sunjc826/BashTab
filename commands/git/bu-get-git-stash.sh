#!/usr/bin/env bash
# Pipeline: producer
# Fields: index ref branch short_hash message
# Dispatch: source
# Synopsis: List Git stashes
function __bu_bu_get_git_stash_main()
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
List stashed changes as structured records (git stash list).
Each record: index, ref, branch, message.

Fields: index, ref, branch, message
" \
        --example "All stashes" ""
    return 0
fi

local -a cmd=(git stash list)
if ((${#remaining_options[@]} > 0)); then cmd+=("${remaining_options[@]}"); fi

# git stash list format: "stash@{0}: WIP on main: abc1234 Fix bug"
# Parse into: index, ref, branch, message
{
    "${cmd[@]}" 2>/dev/null | while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local ref="${line%%:*}"           # stash@{0}
        local index="${ref#stash@\{}"     # 0
        index="${index%\}}"
        local rest="${line#*: }"          # WIP on main: abc1234 Fix bug
        local wip="${rest%%:*}"           # WIP on main
        local branch="${wip#* on }"       # main
        local message="${rest#*: }"       # abc1234 Fix bug
        # message might be "abc1234 Fix bug" — split on first space to get short hash
        local short_hash="${message%% *}"
        local msg="${message#* }"
        [[ "$msg" == "$message" ]] && msg=
        printf '%s\t%s\t%s\t%s\t%s\n' "$index" "$ref" "$branch" "$short_hash" "$msg"
    done
} | bu_out_from_tsv --columns index,ref,branch,short_hash,message \
  | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_get_git_stash_main "$@"
