#!/usr/bin/env bash
# Pipeline: recordify_new
# Dispatch: source
# Synopsis: Construct a single JSONL record from key=value arguments
function __bu_bu_new_record_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local -a pairs=()
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
        pairs+=("$1")
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
        --description "
Construct a single JSON record from key=value pairs (PowerShell
[PSCustomObject]@{...}). Values are properly JSON-escaped.
Use key:=value for typed JSON values (numbers, booleans, arrays).

Prefer bu_out_from_tsv / bu convert-from-tsv when constructing many
records in a loop: one jq process for the whole stream instead of one
per record.
" \
        --example "Simple record" "name=bashtab version=0.1.0" \
        --example "Typed values" "pid=$$ alive:=true retries:=3"
    return 0
fi

# Cmdlets implicitly end at Out-Default: a table on a terminal, JSONL when piped
bu_out_record "${pairs[@]}" | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_new_record_main "$@"
