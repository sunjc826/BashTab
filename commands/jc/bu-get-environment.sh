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
local -a names=()
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
        # Variable name or pattern, e.g. HOME or 'LC_*' (repeatable)
        bu_parse_positional $# --glob --stdout compgen -e stdout-- --hint "Variable name or pattern"
        names+=("${!shift_by}")
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
        --example "Locale variables" "--name 'LC_*' --name LANG" \
        --example "With extra flags" "-- -u /usr/bin/env"
    return 0
fi

if ! command -v jc &>/dev/null
then
    error_msg="jc is required. Install with: pip install jc"
    bu_autohelp
    return 1
fi

local -a cmd=()
if ((${#remaining_options[@]} > 0))
then
    cmd=("${remaining_options[@]}")
else
    cmd=(env)
fi

# jc env parser emits an array of {name, value} records.
# Strip ANSI escape sequences from values (CSI: ESC[params letter,
# charset: ESC( or ESC) + single char) to prevent display corruption.
# Each record comes back as "name<TAB>json" so --name can filter in this
# shell (seen must survive for the missing-name report).
local -a lines=()
mapfile -t lines < <("${cmd[@]}" 2>/dev/null | jc --env 2>/dev/null | jq -r '
    if type == "array" then .[] else . end
    | .value |= gsub("\u001b\\[[0-9;?]*[a-zA-Z]"; "")
    | .value |= gsub("\u001b[()]."; "")
    | "\(.name)\t\(tojson)"
' 2>/dev/null)

local line var_name
local -a records=()
local -A seen=()
for line in "${lines[@]}"
do
    var_name=${line%%$'\t'*}
    bu_glob_match "$var_name" "${names[@]}" || continue
    seen[$var_name]=1
    records+=("${line#*$'\t'}")
done
if ((${#records[@]}))
then
    printf '%s\n' "${records[@]}"
fi | bu_out --format "$format"

local exit_code=0
bu_glob_report_missing "environment variable" seen "${names[@]}" || exit_code=1

bu_scope_pop_function
return "$exit_code"
}

__bu_bu_get_environment_main "$@"
