#!/usr/bin/env bash
# Pipeline: consume
# Requires-All: name
# Dispatch: source
# Synopsis: Set a bash shell option
function __bu_bu_set_shell_option_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local name=
local value=
local format=auto
local is_help=false
local is_dry_run=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --on)# _FLAG
        # Turn the option on (set -o NAME); this is the default
        value=on
        ;;
    --off)# _FLAG
        # Turn the option off (set +o NAME)
        value=off
        ;;
    --format)# FORMAT
        # Output format
        bu_parse_positional $# --enum ${BU_OUT_FORMATS[@]} enum-- --hint "Output format"
        format=${!shift_by}
        ;;
    --name)# NAME
        # Shell option name (also accepts pipeline input by structural typing)
        bu_parse_positional $# --ret __bu_bu_set_shell_option_complete_names ret-- --hint "Option name"
        name=${!shift_by}
        ;;
    --dry-run|--what-if) # _FLAG
        is_dry_run=true
        ;;
    -h|--help)# _FLAG
        # Print help
        is_help=true
        ;;
    *)
        if bu_env_is_in_autocomplete && [[ "$1" != -* ]]
        then
            # Name positional: complete from set -o option names
            autocompletion=(--ret __bu_bu_set_shell_option_complete_names ret-- --hint "Option name")
        fi
        if [[ -z "$name" ]]
        then
            name=$1
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
Turn a set -o shell option on or off (PowerShell preference-variable style).
Runs sourced, so the change affects your current shell — e.g.
'bu set-shell-option pipefail --on' behaves like '$ErrorActionPreference'
counterparts. Option names autocomplete from the live set -o list.
Emits the resulting state as a record.
" \
        --example "Enable pipefail" "pipefail" \
        --example "Disable xtrace" "xtrace --off" \
        --example "Enable every off option" ""
    return 0
fi

value=${value:-on}

# Pipeline input: when no name is given and stdin is a pipe, read JSONL
# records and toggle each option's .name to the value (from .value or --on/--off).
# 'bu get-shell-option | bu where ".value == false" | bu set-shell-option'
# enables every currently-off option.
if [[ -z "$name" ]] && [[ ! -t 0 ]]
then
    local records_file _n _v _tv
    records_file=$(mktemp)
    bu_scope_add_cleanup rm -f "$records_file"
    local rc=0
    {
        while IFS=$'\t' read -r _n _v
        do
            [[ -z "$_n" ]] && continue
            _tv=${_v:-$value}
            if [[ "$_tv" == on || "$_tv" == true ]]
            then
                set -o "$_n" 2>/dev/null \
                    && bu_out_record name="$_n" value:=true \
                    || { bu_out_record name="$_n" value:=false error="set -o failed"; rc=1; }
            else
                set +o "$_n" 2>/dev/null \
                    && bu_out_record name="$_n" value:=false \
                    || { bu_out_record name="$_n" value:=true error="set +o failed"; rc=1; }
            fi
        done < <(__bu_out_strict_guard "set-shell-option" | jq -r '.name as $n | (if has("value") then (.value | tostring) else "" end) as $v | if $n then "\($n)\t\($v)" else empty end' 2>/dev/null)
    } > "$records_file"
    bu_out --format "$format" < "$records_file"
    bu_scope_pop_function
    return $rc
fi

if [[ -z "$name" ]]
then
    error_msg="Missing required option name (e.g. bu set-shell-option pipefail --on)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

value=${value:-on}

# Validate against the live option list
local -a valid=()
__bu_bu_set_shell_option_complete_names
valid=("${BU_RET[@]}")
local found=false v
for v in "${valid[@]}"
do
    [[ "$v" == "$name" ]] && { found=true; break; }
done
if ! "$found"
then
    error_msg="Unknown shell option[$name]. Valid options: ${valid[*]}"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

if "$is_dry_run"; then
    bu_out_record name="$name" value:="$([[ "$value" == on ]] && echo true || echo false)" action="would-set" dry_run:=true | bu_out --format "$format"
else
# Runs sourced, so the change sticks in the current shell
if [[ "$value" == on ]]
then
    set -o "$name"
else
    set +o "$name"
fi

set -o | jq -R -c --arg name "$name" '
    select(. != "")
    | capture("^(?<name>\\S+)\\s+(?<value>on|off)$")
    | select(.name == $name)
    | .value |= (. == "on")
' | bu_out --format "$format"
fi

bu_scope_pop_function
}

# Completion helper: valid set -o option names.
__bu_bu_set_shell_option_complete_names()
{
    BU_RET=()
    local o
    while IFS= read -r o
    do
        [[ -n "$o" ]] && BU_RET+=("$o")
    done < <(set -o | awk '{print $1}')
}

__bu_bu_set_shell_option_main "$@"
