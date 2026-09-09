#!/usr/bin/env bash
# Pipeline: recordify_file
# Dispatch: source
# Synopsis: Read a CSV file and emit JSONL records
function __bu_bu_import_csv_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local file=
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
        if [[ -n "$file" ]]
        then
            bu_parse_error_enum "$1"
            break
        fi
        file=$1
        autocompletion=("${BU_AUTOCOMPLETE_SPEC_FILE[@]}" --hint "CSV file")
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
Read a CSV file and emit its records as a JSONL object stream (the
file-reading companion to bu convert-from-csv). The first row is the header;
each subsequent row becomes one record keyed by the headers. Quoting and
embedded commas are handled by jc's CSV parser.
" \
        --example "Recordify a CSV file" "data.csv" \
        --example "Pipe into a query" "data.csv | bu query-object where type -eq source select name"
    return 0
fi

if [[ -z "$file" ]]
then
    error_msg="Expected a CSV file path (e.g. bu import-csv data.csv)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

bu_realpath "$file" "$invocation_dir"
file=$BU_RET
if [[ ! -e "$file" ]]
then
    error_msg="File does not exist[$file]"
elif [[ ! -r "$file" ]]
then
    error_msg="File is not readable[$file]"
elif ! command -v jc &>/dev/null
then
    error_msg="jc is required. Install with: pip install jc"
fi

if [[ -n "$error_msg" ]]
then
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

# Cmdlets implicitly end at Out-Default: a table on a terminal, JSONL when piped
__bu_out_read_file_jsonl "$file" | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_import_csv_main "$@"
