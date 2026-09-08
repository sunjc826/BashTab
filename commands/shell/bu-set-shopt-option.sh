#!/usr/bin/env bash
# Pipeline: consume
# Requires: name
# Dispatch: source
# Synopsis: Set a bash shopt option
function __bu_bu_set_shopt_option_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local name=
local action=
local format=auto
local is_dry_run=false
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    -s|--set)# _FLAG
        # Enable the option (shopt -s NAME); this is the default
        action=set
        ;;
    -u|--unset)# _FLAG
        # Disable the option (shopt -u NAME)
        action=unset
        ;;
    --format)# FORMAT
        # Output format
        bu_parse_positional $# --enum ${BU_OUT_FORMATS[@]} enum-- --hint "Output format"
        format=${!shift_by}
        ;;
    --name)# NAME
        # shopt option name (also accepts pipeline input by structural typing)
        bu_parse_positional $# --ret __bu_bu_set_shopt_complete_names ret-- --hint "Option name"
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
            # Name positional: complete from shopt option names
            autocompletion=(--ret __bu_bu_set_shopt_complete_names ret-- --hint "Option name")
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
Enable or disable a shopt shell option (shopt -s/-u with autocomplete).
Runs sourced, so the change affects your current shell — e.g.
'bu set-shopt-option globstar' enables ** recursive globs right away.
Option names autocomplete from the live shopt list. Emits the resulting
state as a record.
" \
        --example "Enable globstar" "globstar" \
        --example "Disable nullglob" "nullglob --unset" \
        --example "Pipeline (enable all off)" ""
        --example "Pipeline input" ""
    return 0
fi

action=${action:-set}

# Pipeline input: when no name is given and stdin is a pipe, read JSONL
# records and toggle each option's .name to the value (from .value or --set/--unset).
# 'bu get-shopt-option | bu where ".value == false" | bu set-shopt-option'
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
            _tv=${_v:-$action}
            if [[ "$_tv" == set || "$_tv" == on || "$_tv" == true ]]
            then
                shopt -s "$_n" 2>/dev/null \
                    && bu_out_record name="$_n" value:=true \
                    || { bu_out_record name="$_n" value:=false error="shopt -s failed"; rc=1; }
            else
                shopt -u "$_n" 2>/dev/null \
                    && bu_out_record name="$_n" value:=false \
                    || { bu_out_record name="$_n" value:=true error="shopt -u failed"; rc=1; }
            fi
        done < <(jq -r '.name as $n | (if has("value") then (.value | tostring) else "" end) as $v | if $n then "\($n)\t\($v)" else empty end' 2>/dev/null)
    } > "$records_file"
    bu_out --format "$format" < "$records_file"
    bu_scope_pop_function
    return $rc
fi

if [[ -z "$name" ]]
then
    error_msg="Missing required option name (e.g. bu set-shopt-option globstar)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

action=${action:-set}

if "$is_dry_run"; then
    bu_out_record name="$name" value:="$([[ "$action" == set ]] && echo true || echo false)" action="would-${action}" dry_run:=true | bu_out --format "$format"
    bu_scope_pop_function
    return 0
fi

# Runs sourced, so the change sticks in the current shell.
# Note: no command substitution here — it would run shopt in a subshell
# and the setting would be lost. shopt prints its own error to stderr.
local rc=0
if [[ "$action" == set ]]
then
    shopt -s "$name" || rc=1
else
    shopt -u "$name" || rc=1
fi

if ((rc != 0))
then
    error_msg="Invalid shell option name[$name]"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

shopt "$name" | jq -R -c '
    select(. != "")
    | capture("^(?<name>\\S+)\\s+(?<value>on|off)$")
    | .value |= (. == "on")
' | bu_out --format "$format"

bu_scope_pop_function
}

# Completion helper: valid shopt option names.
__bu_bu_set_shopt_complete_names()
{
    BU_RET=()
    local o
    while IFS= read -r o
    do
        [[ -n "$o" ]] && BU_RET+=("$o")
    done < <(shopt | awk '{print $1}')
}

__bu_bu_set_shopt_option_main "$@"
