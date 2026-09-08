#!/usr/bin/env bash
# Pipeline: query
# Dispatch: source
# Synopsis: Group a JSONL stream by key fields with aggregate functions
function __bu_bu_group_object_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local keys=
local is_no_items=false
local format=auto
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --no-items)# _FLAG
        # Omit the items array from each group (keys and count only)
        is_no_items=true
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
        if bu_env_is_in_autocomplete && [[ "$1" != -* ]]
        then
            # Bare positional: suggest fields of the pipeline producer's records
            autocompletion=(--hint "key field(s), comma-separated" --pipeline-fields pipeline-fields--)
        fi
        if [[ -z "$keys" ]]
        then
            keys=$1
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
Group records in a JSONL stream by one or more key fields (PowerShell Group-Object).
Emits one record per group: the key field(s), count, and items (the
member records). Use --no-items for keys and count only (like
'sort | uniq -c'). For aggregated stats per group see bu query-object
group-by. Requires a full pass over the stream.
" \
        --example "Group by one field" "verb" \
        --example "Group by two fields" "verb,namespace" \
        --example "Counts only" "verb --no-items"
    return 0
fi

if [[ -z "$keys" ]]
then
    error_msg="Missing required key field (e.g. bu get-command | bu group-object verb)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

__bu_out_cols_to_json "$keys"
local keys_json=$BU_RET

jq -sc --argjson keys "$keys_json" --argjson no_items "$is_no_items" '
    group_by([.[$keys[]]])
    | map( . as $g
        | (reduce ($keys | to_entries[]) as $e ({}; .[$e.value] = $g[0][$e.value]))
        + {count: ($g | length)}
        + (if $no_items then {} else {items: $g} end)
    )
    | .[]
' | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_group_object_main "$@"
