#!/usr/bin/env bash
# Pipeline: codec
# Dispatch: source
# Synopsis: Convert JSONL records to TSV text
function __bu_bu_convert_to_tsv_main()
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
        # Fields to emit, in order (comma-separated). Default: keys of each record.
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
Convert a JSONL stream to tab-separated lines for scripting (no header row).
Embedded tabs/newlines in values are escaped. Streams record-by-record.
" \
        --example "Extract two fields" "--columns name,path"
    return 0
fi

local -a formatter_args=()
[[ -n "$columns" ]] && formatter_args+=(--columns "$columns")
bu_format_tsv "${formatter_args[@]}"

bu_scope_pop_function
}

__bu_bu_convert_to_tsv_main "$@"
