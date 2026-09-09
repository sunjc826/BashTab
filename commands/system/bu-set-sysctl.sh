#!/usr/bin/env bash
# Pipeline: transform
# Requires-All: name
# Fields: name old_value new_value set error
# Dispatch: source
# Synopsis: Set a kernel parameter
# Completion helper: sysctl parameter names from the live system.
__bu_bu_set_sysctl_complete_names()
{
    BU_RET=()
    local n
    while IFS= read -r n
    do
        [[ -n "$n" ]] && BU_RET+=("$n")
    done < <( sysctl -aN 2>/dev/null )
}

function __bu_bu_set_sysctl_main()
{
set -e
# --is-compatible: magic flag checked by the framework at registration time.
# Exit 0 if this command can run on the current system, non-zero otherwise.
# stderr becomes the reason shown in `bu` help.
if [[ "$1" == "--is-compatible" ]]; then
    command -v sysctl &>/dev/null || { echo "sysctl is required" >&2; exit 1; }
    exit 0
fi
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
        # Kernel parameter name (repeatable)
        bu_parse_positional $# --ret __bu_bu_set_sysctl_complete_names ret-- --hint "Kernel parameter name"
        names+=("${!shift_by}")
        ;;
    --value)# VALUE
        # Parameter value (repeatable; pairs with --name by position)
        bu_parse_positional $# --hint "Parameter value"
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
                autocompletion=(--ret __bu_bu_set_sysctl_complete_names ret-- --hint "Kernel parameter name")
            else
                autocompletion=(--hint "Parameter value")
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
Set kernel parameters (PowerShell Set-ItemProperty analog, structured sysctl -w).
Emits one record per parameter: name, old_value, new_value, set (boolean);
failures carry an error field. Requires root or sufficient privileges for
most parameters.

Accepts pipeline input from get-sysctl (reads .name and .value fields).
" \
        --example "One parameter" "net.ipv4.ip_forward 1" \
        --example "Named flags" "--name kernel.hostname --name myhost" \
        --example "Dry run" "net.ipv4.ip_forward 0 --what-if" \
        --example "Pipeline from get-sysctl" ""
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
    error_msg="Missing required parameter name (e.g. bu set-sysctl net.ipv4.ip_forward 1)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

local records_file
records_file=$(mktemp)
bu_scope_add_cleanup rm -f "$records_file"

local rc=0
local i name value old_value err
{
    for i in "${!names[@]}"
    do
        name=${names[$i]}
        value=${values[$i]:-}

        # Read current value for the record
        old_value=$(sysctl -n "$name" 2>/dev/null) || old_value=

        if "$is_what_if"
        then
            bu_log_info "What if: sysctl -w $name=$value"
            continue
        fi

        if err=$(sysctl -w "$name=$value" 2>&1)
        then
            bu_out_record name="$name" old_value="$old_value" new_value="$value" set:=true
        else
            bu_out_record name="$name" old_value="$old_value" new_value="$value" set:=false error="$err"
            rc=1
        fi
    done
} > "$records_file"

bu_out --format "$format" < "$records_file"

bu_scope_pop_function
return $rc
}

__bu_bu_set_sysctl_main "$@"
