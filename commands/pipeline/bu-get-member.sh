#!/usr/bin/env bash
# Dispatch: source
# Synopsis: Show the schema of records in a JSONL stream
function __bu_bu_get_member_main()
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
Show the schema of records in a JSONL stream (PowerShell Get-Member).
Reads records from stdin and emits one record per distinct field:
name, the type(s) seen, how many records contain the field, and how
many of those values are null. Requires a full pass over the stream.
" \
        --example "Inspect bu commands" "" \
        --example "Pipe any producer" ""
    return 0
fi

jq -sc '
    ((map(keys_unsorted) | add) // []) | unique as $keys
    | $keys[] as $k
    | {
        name: $k,
        types: ([.[] | select(has($k)) | .[$k] | type] | unique | join("|")),
        count: ([.[] | select(has($k))] | length),
        null_count: ([.[] | select(has($k) and .[$k] == null)] | length)
    }
' | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_get_member_main "$@"
