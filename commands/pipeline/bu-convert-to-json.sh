#!/usr/bin/env bash
# Pipeline: codec
# Dispatch: source
# Synopsis: Convert JSONL records to a formatted JSON array
function __bu_bu_convert_to_json_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
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
Convert a JSONL stream to a pretty-printed JSON array (PowerShell ConvertTo-Json).
Reads records from stdin. Buffers all input.
" \
        --example "Modules as a JSON array" "< /dev/null"
    return 0
fi

bu_format_json

bu_scope_pop_function
}

__bu_bu_convert_to_json_main "$@"
