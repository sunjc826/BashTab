#!/usr/bin/env bash
# Pipeline: passthrough
# Dispatch: source
# Synopsis: Remove duplicate records from a JSONL stream
function __bu_bu_distinct_object_main()
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
Remove duplicate records from a JSONL stream (Select-Object -Unique).
The first occurrence wins; original order is preserved. Records are
compared with key-order canonicalization, so {\"a\":1,\"b\":2} equals
{\"b\":2,\"a\":1}.
" \
        --example "Distinct verbs" "< /dev/null; bu get-command | bu select verb | bu distinct-object"
    return 0
fi

# Cmdlets implicitly end at Out-Default: a table on a terminal, JSONL when piped
bu_out_distinct | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_distinct_object_main "$@"
