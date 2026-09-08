#!/usr/bin/env bash
# Pipeline: codec
# Dispatch: source
# Synopsis: Convert JSONL records to CSV text
function __bu_bu_convert_to_csv_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local columns=
local is_no_header=false
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --columns)# COLUMNS
        # Fields to emit, in order (comma-separated). Default: union of keys across all records.
        bu_parse_positional $# --hint "Comma-separated columns" --pipeline-fields pipeline-fields--
        columns=${!shift_by}
        ;;
    --no-header)# _FLAG
        # Omit the header row
        is_no_header=true
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
Convert a JSONL stream to CSV on stdout (PowerShell ConvertTo-Csv).
Emits a header row followed by one row per record. Values are quoted per
RFC 4180 (jq @csv); nested objects/arrays are serialized to JSON text.
Requires a full pass over the stream (to collect the union of keys,
unless --columns is given, in which case it streams).
" \
        --example "All fields" "" \
        --example "Selected columns" "--columns name,version" \
        --example "No header row" "--no-header --columns name,version"
    return 0
fi

# Nested values can't be represented in CSV cells: serialize them to JSON text
local sanitize='map_values(if type == "object" or type == "array" then tojson else . end)'

if [[ -n "$columns" ]]
then
    __bu_out_cols_to_json "$columns"
    local cols_json=$BU_RET
    jq -r --argjson cols "$cols_json" --argjson no_header "$is_no_header" "
        if input_line_number == 1 and (\$no_header | not)
        then (\$cols | @csv), ($sanitize | [.[\$cols[]]] | @csv)
        else ($sanitize | [.[\$cols[]]] | @csv)
        end
    "
else
    jq -rs --argjson no_header "$is_no_header" "
        (map(keys_unsorted) | add | unique // []) as \$cols
        | (if \$no_header then empty else (\$cols | @csv) end),
          (.[] | $sanitize | [.[\$cols[]]] | @csv)
    "
fi

bu_scope_pop_function
}

__bu_bu_convert_to_csv_main "$@"
