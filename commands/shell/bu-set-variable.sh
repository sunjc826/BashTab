#!/usr/bin/env bash
# Pipeline: transform
# Requires-All: name
# Fields: name type value set exported readonly error
# Dispatch: source
# Synopsis: Set a shell or environment variable
# Completion helper: currently set variable names.
__bu_bu_set_variable_complete_names()
{
    BU_RET=()
    local n
    while IFS= read -r n
    do
        [[ -n "$n" ]] && BU_RET+=("$n")
    done < <(compgen -A variable)
}

function __bu_bu_set_variable_main()
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
local -a values=()
local var_type=string
local is_export=false
local is_readonly=false
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
    --type)# TYPE
        # Variable type (string, integer, array, assoc)
        bu_parse_positional $# --enum string integer array assoc enum-- --hint "Variable type"
        var_type=${!shift_by}
        ;;
    --export)# _FLAG
        # Export the variable to the environment
        is_export=true
        ;;
    --readonly)# _FLAG
        # Mark the variable as read-only
        is_readonly=true
        ;;
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
        # Variable name (repeatable)
        bu_parse_positional $# --ret __bu_bu_set_variable_complete_names ret-- --hint "Variable name"
        names+=("${!shift_by}")
        ;;
    --value)# VALUE
        # Variable value (repeatable; pairs with --name by position)
        bu_parse_positional $# --hint "Variable value"
        values+=("${!shift_by}")
        ;;
    -h|--help)# _FLAG
        # Print help
        is_help=true
        ;;
    *)
        if bu_env_is_in_autocomplete && [[ "$1" != -* ]]
        then
            if ((${#names[@]} == ${#values[@]}))
            then
                autocompletion=(--ret __bu_bu_set_variable_complete_names ret-- --hint "Variable name")
            else
                autocompletion=(--hint "Variable value")
            fi
            bu_autocomplete
            return 0
        fi
        if ((${#names[@]} == ${#values[@]}))
        then
            names+=("$1")
        else
            values+=("$1")
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
Set shell variables (PowerShell Set-Variable analog, structured declare -g).
Runs sourced in the current shell. Unmatched names get the last-seen value.
Flags control type (--type array for arrays, --type integer for integers),
export (--export), and readonly (--readonly). Emits one record per variable.

Accepts pipeline input from get-variable (reads .name and .value fields).
" \
        --example "Simple string" "MY_VAR hello" \
        --example "Integer" "--type integer --name COUNT --value 42" \
        --example "Exported" "API_KEY secret --export" \
        --example "Pipeline from get-variable" ""
    return 0
fi

# Pipeline input: when no names are given and stdin is a pipe,
# read JSONL records and extract .name and .value.
if ((${#names[@]} == 0)) && [[ ! -t 0 ]]
then
    local _name _value
    while IFS=$'\t' read -r _name _value
    do
        [[ -n "$_name" ]] || continue
        names+=("$_name")
        values+=("${_value:-}")
    done < <(jq -r '[.name, (.value // "")] | @tsv' 2>/dev/null)
fi

# Align names and values: if more names than values, last value repeats.
if ((${#names[@]} == 0))
then
    error_msg="Missing required variable name (e.g. bu set-variable MY_VAR hello)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

local records_file
records_file=$(mktemp)
bu_scope_add_cleanup rm -f "$records_file"

local rc=0
local i name value declare_args
{
    for i in "${!names[@]}"
    do
        name=${names[$i]}
        value=${values[$i]:-}
        declare_args=(-g)

        case "$var_type" in
        integer) declare_args+=(-i) ;;
        array)   declare_args+=(-a) ;;
        assoc)   declare_args+=(-A) ;;
        esac

        "$is_export" && declare_args+=(-x)
        "$is_readonly" && declare_args+=(-r)

        if "$is_what_if"
        then
            bu_log_info "What if: declare ${declare_args[*]} $name=${value@Q}"
            continue
        fi

        case "$var_type" in
        array)
            # Split value by commas or newlines into array elements
            local -a _arr=()
            local _elem
            while IFS= read -r _elem
            do
                [[ -n "$_elem" ]] && _arr+=("$_elem")
            done < <(echo "$value" | tr ',' '\n')
            if err=$(declare "${declare_args[@]}" "$name" 2>&1)
            then
                eval "$name=("\"\${_arr[@]}\"")" 2>/dev/null
                bu_out_record name="$name" type="$var_type" set:=true exported:="$is_export" readonly:="$is_readonly"
            else
                bu_out_record name="$name" type="$var_type" set:=false error="declare failed (invalid name or readonly conflict)"
                rc=1
            fi
            ;;
        assoc)
            # Value is "key1:val1,key2:val2"
            if err=$(declare -A -g "$name" 2>&1)
            then
                local _pair _k _v
                while IFS= read -r _pair
                do
                    _k=${_pair%%:*}
                    _v=${_pair#*:}
                    [[ -n "$_k" ]] && eval "$name[\"\$_k\"]=\"\$_v\"" 2>/dev/null
                done < <(echo "$value" | tr ',' '\n')
                bu_out_record name="$name" type="$var_type" set:=true exported:="$is_export" readonly:="$is_readonly"
            else
                bu_out_record name="$name" type="$var_type" set:=false error="$err"
                rc=1
            fi
            ;;
        *)
            if err=$(declare "${declare_args[@]}" "$name"="$value" 2>&1)
            then
                bu_out_record name="$name" type="$var_type" value="$value" set:=true exported:="$is_export" readonly:="$is_readonly"
            else
                bu_out_record name="$name" type="$var_type" set:=false error="$err"
                rc=1
            fi
            ;;
        esac
    done
} > "$records_file"

bu_out --format "$format" < "$records_file"

bu_scope_pop_function
return $rc
}

__bu_bu_set_variable_main "$@"
