#!/usr/bin/env bash
# Pipeline: consume
# Requires-All: name
# Dispatch: source
# Synopsis: Remove a registered command alias
# Help-Topic: aliases
# Completion helper: defined alias names.
__bu_bu_remove_alias_complete_names()
{
    BU_RET=()
    local a
    while IFS= read -r a
    do
        [[ -n "$a" ]] && BU_RET+=("$a")
    done < <(alias | sed -n "s/^alias \([^=]*\)=.*/\1/p")
}

function __bu_bu_remove_alias_main()
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
        # Alias name (repeatable; also accepts pipeline input)
        bu_parse_positional $# --ret __bu_bu_remove_alias_complete_names ret-- --hint "Alias name"
        names+=("${!shift_by}")
        ;;
    -h|--help)# _FLAG
        # Print help
        is_help=true
        ;;
    *)
        if bu_env_is_in_autocomplete
        then
            autocompletion=(--ret __bu_bu_remove_alias_complete_names ret-- --hint "Alias name")
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
Remove shell aliases (PowerShell Remove-Alias analog, structured unalias).
Runs sourced in the current shell. Emits one record per alias: name, removed (boolean).

Accepts pipeline input from get-shell-alias (reads .name field).
" \
        --example "One alias" "ll" \
        --example "Multiple aliases" "gs gp gl" \
        --example "Dry run" "ll --what-if" \
        --example "Pipeline from get-shell-alias" ""
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
    done < <(jq -r '.name // empty' 2>/dev/null)
fi

if ((${#names[@]} == 0))
then
    error_msg="Missing required alias name (e.g. bu remove-alias ll)"
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
            bu_log_info "What if: unalias $name"
            continue
        fi
        if unalias "$name" 2>/dev/null
        then
            bu_out_record name="$name" removed:=true
        else
            bu_out_record name="$name" removed:=false error="unalias failed (not found or readonly)"
            rc=1
        fi
    done
} > "$records_file"

bu_out --format "$format" < "$records_file"

bu_scope_pop_function
return $rc
}

__bu_bu_remove_alias_main "$@"
