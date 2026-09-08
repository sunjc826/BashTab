#!/usr/bin/env bash
# Pipeline: passthrough
# Dispatch: source
# Synopsis: Execute a script block for each record in a JSONL stream
function __bu_bu_foreach_object_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local expression=
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
        if bu_env_is_in_autocomplete && [[ "$1" != -* ]]
        then
            # Bare positional: suggest jq-style fields of the pipeline producer's records
            autocompletion=(--hint "jq field" --pipeline-fields --dot pipeline-fields--)
        fi
        if [[ -z "$expression" ]]
        then
            expression=$1
        else
            bu_parse_error_enum "$1"
        fi
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
Transform each record in a JSONL stream with a jq expression (PowerShell ForEach-Object).
Reads records from stdin; the expression runs once per record with the
current record as '.'. The expression may emit 0..n records per input
(e.g. '.items[]' unnests, 'empty' drops). Streams with O(1) latency.
" \
        --example "Add a computed field" "'. + {upper: (.name | ascii_upcase)}'" \
        --example "Unnest an array field" "'.items[]'" \
        --example "Rewrite records" "'{cmd: .name, kind: .type}'"
    return 0
fi

if [[ -z "$expression" ]]
then
    error_msg="Missing required jq expression (e.g. bu foreach-object '. + {upper: (.name | ascii_upcase)}')"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

# Cmdlets implicitly end at Out-Default: a table on a terminal, JSONL when piped
jq -c "$expression" | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_foreach_object_main "$@"
