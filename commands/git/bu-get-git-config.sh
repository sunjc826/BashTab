#!/usr/bin/env bash
# Pipeline: producer
# Fields: key value scope
# Dispatch: source
# Synopsis: Show Git configuration settings
function __bu_bu_get_git_config_main()
{
# --is-compatible: magic flag checked by the framework at registration time.
if [[ "$1" == "--is-compatible" ]]; then
    command -v git &>/dev/null || { echo "git is required" >&2; exit 1; }
    exit 0
fi
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local is_help=false
local format=auto
local scope=local
local name=
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
    --scope)# SCOPE
        # Config scope: local (repo), global (user), system
        bu_parse_positional $# --enum local global system enum-- --hint "Config scope"
        scope=${!shift_by}
        ;;
    --name)# NAME
        # Filter to a specific config key (e.g. user.name, remote.origin.url)
        bu_parse_positional $# --hint "Config key"
        name=${!shift_by}
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
List git configuration as structured records (git config --list).
Each record: key, value, scope.

Fields: key, value, scope
" \
        --example "Repo config" "" \
        --example "Global config" "--scope global" \
        --example "Specific key" "--name user.name" \
        --example "System-wide" "--scope system"
    return 0
fi

local -a cmd=(git config --list --"$scope")
[[ -n "$name" ]] && cmd=(git config --"$scope" --get "$name")
if ((${#remaining_options[@]} > 0)); then cmd+=("${remaining_options[@]}"); fi

if [[ -n "$name" ]]; then
    # Single key query: just get the value
    local value
    value=$("${cmd[@]}" 2>/dev/null) || true
    if [[ -n "$value" ]]; then
        {
            printf '%s\t%s\t%s\n' "$name" "$value" "$scope"
        } | bu_out_from_tsv --columns key,value,scope \
          | bu_out --format "$format"
    fi
else
    # List all: each line is key=value
    {
        "${cmd[@]}" 2>/dev/null | while IFS='=' read -r key value; do
            [[ -z "$key" ]] && continue
            printf '%s\t%s\t%s\n' "$key" "$value" "$scope"
        done
    } | bu_out_from_tsv --columns key,value,scope \
      | bu_out --format "$format"
fi

bu_scope_pop_function
}

__bu_bu_get_git_config_main "$@"
