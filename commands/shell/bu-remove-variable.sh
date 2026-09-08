#!/usr/bin/env bash
# Pipeline: consume
# Requires-All: name
# Dispatch: source
# Synopsis: Unset a shell variable
# Completion helper: currently set variable names.
__bu_bu_remove_variable_complete_names()
{
    BU_RET=()
    local n
    while IFS= read -r n
    do
        [[ -n "$n" ]] && BU_RET+=("$n")
    done < <(compgen -A variable)
}

function __bu_bu_remove_variable_main()
{
set -e
local -r invocation_dir=$PWD
local script_name
local script_dir
case "$BASH_SOURCE" in
*/*)
    script_name=${BASH_SOURCE##*/}
    script_dir=${BASH_SOURCE%/*}
    ;;
*)
    script_name=$BASH_SOURCE
    script_dir=.
    ;;
esac
pushd "$script_dir" &>/dev/null
script_dir=$PWD

if [[ -z "$COMP_CWORD" ]]
then
# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_DIR"/bu_entrypoint.sh
fi

bu_exit_handler_setup
bu_scope_push_function
bu_scope_add_cleanup bu_popd_silent
bu_run_log_command "$@"

local -a names=()
local is_what_if=false
local format=auto
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --what-if)# _FLAG
        # Show what would happen without changing anything
        is_what_if=true
        ;;
    --format)# FORMAT
        # Output format
        bu_parse_positional $# --enum ${BU_OUT_FORMATS[@]} enum-- --hint "Output format"
        format=${!shift_by}
        ;;
    --name)# NAME
        # Variable name (repeatable; also accepts pipeline input)
        bu_parse_positional $# --ret __bu_bu_remove_variable_complete_names ret-- --hint "Variable name"
        names+=("${!shift_by}")
        ;;
    -h|--help)# _FLAG
        # Print help
        is_help=true
        ;;
    *)
        if bu_env_is_in_autocomplete
        then
            autocompletion=(--ret __bu_bu_remove_variable_complete_names ret-- --hint "Variable name")
        fi
        names+=("$1")
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
Remove shell variables (PowerShell Remove-Variable analog, structured unset).
Runs sourced in the current shell. Each variable is unset individually;
readonly variables cause a failure for that record but processing continues.
Emits one record per variable: name, removed (boolean).

Accepts pipeline input from get-variable (reads .name field).
" \
        --example "One variable" "MY_TEMP" \
        --example "Multiple variables" "VAR1 VAR2 VAR3" \
        --example "Dry run" "MY_VAR --what-if" \
        --example "Pipeline from get-variable" ""
    return 0
fi

# Pipeline input: when no names are given and stdin is a pipe,
# read JSONL records and extract .name.
if ((${#names[@]} == 0)) && [[ ! -t 0 ]]
then
    local _n
    while IFS= read -r _n
    do
        [[ -n "$_n" ]] && names+=("$_n")
    done < <(__bu_out_strict_guard "remove-variable" | jq -r '.name // empty' 2>/dev/null)
fi

if ((${#names[@]} == 0))
then
    error_msg="Missing required variable name (e.g. bu remove-variable MY_TEMP)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

local records_file
records_file=$(mktemp)
bu_scope_add_cleanup rm -f "$records_file"

local rc=0
local name
{
    for name in "${names[@]}"
    do
        if "$is_what_if"
        then
            bu_log_info "What if: unset $name"
            continue
        fi
        if unset "$name" 2>/dev/null
        then
            bu_out_record name="$name" removed:=true
        else
            bu_out_record name="$name" removed:=false error="unset failed (readonly or not found)"
            rc=1
        fi
    done
} > "$records_file"

bu_out --format "$format" < "$records_file"

bu_scope_pop_function
return $rc
}

__bu_bu_remove_variable_main "$@"
