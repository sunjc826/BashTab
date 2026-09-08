#!/usr/bin/env bash
# Pipeline: sink
# Dispatch: source
# Synopsis: Render a JSONL stream as a key-value list
function __bu_bu_format_list_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local columns=
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --columns)# COLUMNS
        # Fields to display, in order (comma-separated). Default: keys of each record.
        bu_parse_positional $# --hint "Comma-separated columns" --pipeline-fields pipeline-fields--
        columns=${!shift_by}
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
Render a JSONL stream as a list of key-value blocks (PowerShell Format-List).
Reads records from stdin. Streams record-by-record with O(1) latency.
" \
        --example "Select fields" "--columns name,version"
    return 0
fi

local -a formatter_args=()
[[ -n "$columns" ]] && formatter_args+=(--columns "$columns")
bu_format_list "${formatter_args[@]}"

bu_scope_pop_function
}

__bu_bu_format_list_main "$@"
