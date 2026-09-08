#!/usr/bin/env bash
# Pipeline: passthrough
# Dispatch: source
# Synopsis: Calculate statistics (count, sum, avg) on a JSONL stream
function __bu_bu_measure_object_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local field=
local is_sum=false
local is_avg=false
local is_min=false
local is_max=false
local format=auto
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --sum)# _FLAG
        # Include the sum of the numeric field values
        is_sum=true
        ;;
    --avg|--average)# _FLAG
        # Include the average of the numeric field values
        is_avg=true
        ;;
    --min)# _FLAG
        # Include the minimum of the field values
        is_min=true
        ;;
    --max)# _FLAG
        # Include the maximum of the field values
        is_max=true
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
            autocompletion=(--hint "numeric field" --pipeline-fields pipeline-fields--)
        fi
        if [[ -z "$field" ]]
        then
            field=$1
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
Aggregate a JSONL stream into a single statistics record (PowerShell Measure-Object).
count is always included and counts input records. With a field but no
stat flags, all stats (sum, avg, min, max) are included; otherwise only
the requested stats. Non-numeric and missing values are skipped for
sum/avg; min/max ignore nulls. Requires a full pass over the stream.
" \
        --example "Count records" "" \
        --example "All stats for a field" "size" \
        --example "Just the sum" "size --sum"
    return 0
fi

# Field given without stat flags: default to all stats (PowerShell behavior)
if [[ -n "$field" ]] && ! "$is_sum" && ! "$is_avg" && ! "$is_min" && ! "$is_max"
then
    is_sum=true; is_avg=true; is_min=true; is_max=true
fi

# Build the jq program: count always; requested stats over the numeric field values
local fragments='"count": length'
[[ -n "$field" ]] && fragments+=', "property": $field'
"$is_sum" && fragments+=', "sum": ($nums | add // 0)'
"$is_avg" && fragments+=', "avg": (if ($nums | length) > 0 then ($nums | add) / ($nums | length) else null end)'
"$is_min" && fragments+=', "min": ($raw | map(select(. != null)) | min // null)'
"$is_max" && fragments+=', "max": ($raw | map(select(. != null)) | max // null)'

jq -sc --arg field "$field" "
    (if \$field == \"\" then [] else map(.[\$field]) end) as \$raw
    | (\$raw | map(select(type == \"number\"))) as \$nums
    | {$fragments}
" | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_measure_object_main "$@"
