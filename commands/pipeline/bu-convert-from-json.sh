#!/usr/bin/env bash
# Pipeline: codec
# Dispatch: source
# Synopsis: Convert JSON text to JSONL records
function __bu_bu_convert_from_json_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

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
        bu_parse_error_enum "$1"
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
if bu_env_is_in_autocomplete
then
    bu_autocomplete
    return 0
fi

if "$is_help"
then
    bu_autohelp \
        --description "
Convert JSON on stdin to the JSONL object stream (PowerShell ConvertFrom-Json).
Accepts a JSON array (unrolled to one record per element), a single JSON
object (one record), or existing JSONL (passed through record-by-record).
This is the inverse of bu convert-to-json. Streams with O(1) latency.
" \
        --example "Unroll a JSON array" "" \
        --example "Round-trip" ""
    return 0
fi

# Cmdlets implicitly end at Out-Default: a table on a terminal, JSONL when piped
jq -c 'if type == "array" then .[] else . end' | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_convert_from_json_main "$@"
