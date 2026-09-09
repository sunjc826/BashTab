#!/usr/bin/env bash
# Pipeline: transform
# Requires-All: flag
# Fields: flag value old_value set hard error
# Dispatch: source
# Synopsis: Set a shell resource limit
# Completion helper: resource limit flag letters from ulimit -a.
__bu_bu_set_resource_limit_complete_flags()
{
    BU_RET=()
    local letter
    while IFS= read -r letter
    do
        [[ -n "$letter" ]] && BU_RET+=("$letter")
    done < <( ulimit -a 2>/dev/null | sed -n 's/.*(-\([a-zA-Z]\)) .*/\1/p' )
}

function __bu_bu_set_resource_limit_main()
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

local -a flags=()
local -a values=()
local is_hard=false
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
    --hard)# _FLAG
        # Set the hard limit (default: soft limit)
        is_hard=true
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
    --flag)# FLAG
        # Resource flag letter, e.g. n (file descriptors), u (processes)
        bu_parse_positional $# --ret __bu_bu_set_resource_limit_complete_flags ret-- --hint "Resource flag letter"
        flags+=("${!shift_by}")
        ;;
    --value)# VALUE
        # Limit value (repeatable; pairs with --flag by position)
        bu_parse_positional $# --hint "Limit value"
        values+=("${!shift_by}")
        ;;
    -h|--help)# _FLAG
        # Print help
        is_help=true
        ;;
    *)
        if bu_env_is_in_autocomplete && [[ "$1" != -* ]]
        then
            if ((${#flags[@]} == ${#values[@]}))
            then
                autocompletion=(--ret __bu_bu_set_resource_limit_complete_flags ret-- --hint "Resource flag letter")
            else
                autocompletion=(--hint "Limit value")
            fi
            bu_autocomplete
            return 0
        fi
        if ((${#flags[@]} == ${#values[@]}))
        then
            flags+=("$1")
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
Set per-process resource limits (structured ulimit).
Runs sourced in the current shell. By default sets the soft limit; use
--hard to set the hard limit. The flag letter corresponds to ulimit
switches: n (file descriptors), u (processes), etc. Emits one record
per resource.

Accepts pipeline input from get-resource-limit (reads .flag and .soft/.hard fields).
Use 'bu get-resource-limit' to see the available flags and current values.
" \
        --example "Set file descriptor limit" "--flag n --value 4096" \
        --example "Set hard process limit" "--flag u --value 8192 --hard" \
        --example "Bare positionals" "n 4096" \
        --example "Dry run" "n 65536 --what-if" \
        --example "Pipeline from get-resource-limit" ""
    return 0
fi

# Pipeline input: when no flags are given and stdin is a pipe,
# read JSONL records. Use .soft for soft limits, .hard for hard limits.
if ((${#flags[@]} == 0)) && [[ ! -t 0 ]]
then
    local _flag _value
    local value_field
    "$is_hard" && value_field=.hard || value_field=.soft
    while IFS=$'\t' read -r _flag _value
    do
        [[ -n "$_flag" ]] || continue
        flags+=("$_flag")
        values+=("${_value:-}")
    done < <(jq -r "[.flag, (${value_field} // \"\")] | @tsv" 2>/dev/null)
fi

# Align flags and values
if ((${#flags[@]} == 0))
then
    error_msg="Missing required resource flag (e.g. bu set-resource-limit n 4096)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

# Validate flags: must be a single letter
local records_file
records_file=$(mktemp)
bu_scope_add_cleanup rm -f "$records_file"

local rc=0
local i flag value old_value err ulimit_flag
{
    for i in "${!flags[@]}"
    do
        flag=${flags[$i]}
        value=${values[$i]:-}

        if [[ ! "$flag" =~ ^[a-zA-Z]$ ]]
        then
            bu_out_record flag="$flag" set:=false error="flag must be a single letter"
            rc=1
            continue
        fi

        # Read current value
        ulimit_flag="-$flag"
        "$is_hard" && ulimit_flag="-H$flag" || ulimit_flag="-S$flag"
        old_value=$(ulimit "$ulimit_flag" 2>/dev/null) || old_value=

        if "$is_what_if"
        then
            local limit_type=soft
            "$is_hard" && limit_type=hard
            bu_log_info "What if: ulimit -S$flag $value ($limit_type limit)"
            continue
        fi

        if err=$(ulimit "$ulimit_flag" "$value" 2>&1)
        then
            bu_out_record flag="$flag" value="$value" old_value="$old_value" set:=true hard:="$is_hard"
        else
            bu_out_record flag="$flag" value="$value" old_value="$old_value" set:=false hard:="$is_hard" error="$err"
            rc=1
        fi
    done
} > "$records_file"

bu_out --format "$format" < "$records_file"

bu_scope_pop_function
return $rc
}

__bu_bu_set_resource_limit_main "$@"
