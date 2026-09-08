#!/usr/bin/env bash
# Pipeline: producer
# Dispatch: source
# Synopsis: List environment variables as JSONL records
# Fields: name value
function __bu_bu_get_environment_main()
{
# --is-compatible: magic flag checked by the framework at registration time.
# Exit 0 if this command can run on the current system, non-zero otherwise.
# stderr becomes the reason shown in `bu` help.
if [[ "$1" == "--is-compatible" ]]; then
    command -v jc &>/dev/null || { echo "jc is required" >&2; exit 1; }
    command -v env &>/dev/null || { echo "env is required" >&2; exit 1; }
    exit 0
fi
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local is_help=false
local format=auto
local name=
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
    -n|--name)# NAME
        # Filter to a specific variable (e.g. HOME, PATH)
        bu_parse_positional $# --hint "Variable name"
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
        --description "Show environment variables (jc env parser wrapper). ANSI escape sequences are stripped from values." \
        --example "All variables" "" \
        --example "Single variable" "--name HOME" \
        --example "With extra flags" "-- -u /usr/bin/env"
    return 0
fi

if ! command -v jc &>/dev/null
then
    error_msg="jc is required. Install with: pip install jc"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

local -a cmd=()
if ((${#remaining_options[@]} > 0))
then
    cmd=("${remaining_options[@]}")
else
    cmd=(env)
fi

# When --name is given, pre-filter to that variable before jc parsing.
# Use cat as a no-op when name is not set.
local name_filter_cmd=(cat)
[[ -n "$name" ]] && name_filter_cmd=(grep "^${name}=")

# jc env parser emits an array of {name, value} records.
# Strip ANSI escape sequences from values (CSI: ESC[params letter,
# charset: ESC( or ESC) + single char) to prevent display corruption.
"${cmd[@]}" 2>/dev/null | "${name_filter_cmd[@]}" 2>/dev/null | jc --env 2>/dev/null | jq -c '
    if type == "array" then .[] else . end
    | .value |= gsub("\u001b\\[[0-9;?]*[a-zA-Z]"; "")
    | .value |= gsub("\u001b[()]."; "")
' 2>/dev/null | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_get_environment_main "$@"
