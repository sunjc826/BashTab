#!/usr/bin/env bash
# Pipeline: producer
# Fields: name type attributes value length
# Dispatch: source
# Synopsis: List shell and environment variables
function __bu_bu_get_variable_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local filter=
local format=auto
local is_help=false
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
    -h|--help)# _FLAG
        # Print help
        is_help=true
        ;;
    *)
        if bu_env_is_in_autocomplete && [[ "$1" != -* ]]
        then
            # Name positional: complete from currently set variable names
            autocompletion=(--ret __bu_bu_get_variable_complete_names ret-- --hint "Variable name (glob)")
        fi
        if [[ -z "$filter" ]]
        then
            filter=$1
        else
            bu_parse_error_enum "$1"
        fi
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
if bu_env_is_in_autocomplete
then
    bu_autocomplete
    return 0
fi

if "$is_help"
then
    bu_autohelp \
        --description "
List shell variables as records (PowerShell Get-Variable, structured declare -p).
Runs in the current shell. Each record: name, type (string, integer,
array, assoc), attributes (declare letters, e.g. rx for readonly+export),
value (scalars only), and length (arrays/associative arrays only). Give a
glob to filter by name.
" \
        --example "Everything" "" \
        --example "One variable" "HOME" \
        --example "BashTab settings" "'BU_*'"
    return 0
fi

local n decl attrs type value
local -n _bu_get_variable_ref
{
    while IFS= read -r n
    do
        [[ -n "$filter" && "$n" != $filter ]] && continue
        decl=$(declare -p "$n" 2>/dev/null) || continue
        attrs=
        [[ "$decl" =~ ^declare\ -([a-zA-Z]+)\  ]] && attrs=${BASH_REMATCH[1]}
        type=string
        case "$attrs" in
        *A*) type=assoc ;;
        *a*) type=array ;;
        *i*) type=integer ;;
        esac
        case "$type" in
        array|assoc)
            _bu_get_variable_ref=$n
            bu_out_record name="$n" type="$type" attributes="$attrs" value:=null length:="${#_bu_get_variable_ref[@]}"
            ;;
        *)
            value=${!n-}
            bu_out_record name="$n" type="$type" attributes="$attrs" value="$value"
            ;;
        esac
    done < <(compgen -A variable)
} | bu_out --format "$format"

bu_scope_pop_function
}

# Completion helper: currently set variable names.
__bu_bu_get_variable_complete_names()
{
    BU_RET=()
    local n
    while IFS= read -r n
    do
        [[ -n "$n" ]] && BU_RET+=("$n")
    done < <(compgen -A variable)
}

__bu_bu_get_variable_main "$@"
