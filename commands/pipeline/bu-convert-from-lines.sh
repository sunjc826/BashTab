#!/usr/bin/env bash
# Pipeline: recordify_lines
# Dispatch: source
# Synopsis: Convert line-oriented text to JSONL records with a single key
function __bu_bu_convert_from_lines_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local column=
local is_help=false
local format=auto
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --column)# COLUMN
        # Key to assign each input line to
        bu_parse_positional $# --hint "Column name (e.g. file)"
        column=${!shift_by}
        ;;
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
Convert a line-oriented stream to JSONL records, one single-key record
per line. Useful for wrapping line-oriented tools (ls, git, ...) into
the structured pipeline.
" \
        --example "Files as records" "--column file"
    return 0
fi

if [[ -z "$column" ]]
then
    error_msg="Missing required --column (e.g. bu convert-from-lines --column file)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

# Cmdlets implicitly end at Out-Default: a table on a terminal, JSONL when piped
bu_out_from_lines --column "$column" | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_convert_from_lines_main "$@"
