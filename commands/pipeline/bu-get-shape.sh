#!/usr/bin/env bash
# Dispatch: source
# Pipeline: producer
# Synopsis: Infer the output record shape of a producer command
# Fields: name type types required count null_count
function __bu_bu_get_shape_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local producer=
local format=auto
local columns=
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
        bu_validate_positional "${!shift_by}"
        format=${!shift_by}
        ;;
    --columns)# COLUMNS
        # Display columns as key:Label (comma-separated)
        bu_parse_positional $# --hint "Comma-separated columns"
        columns=${!shift_by}
        ;;
    -h|--help)# _FLAG
        # Print help
        is_help=true
        ;;
    *)
        if [[ -n "$producer" ]]
        then
            bu_parse_error_enum "$1"
            break
        fi
        producer=$1
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
Infer the output record shape of a producer command: one record per field
with its observed JSON type(s), whether it is present on every record, and
presence/null counts. Runs the producer once (in a subshell) and pipes its
JSONL through schema inference.

Declared fields from the producer's # Fields: header are listed first (in
declared order), even when the producer emitted no records; inferred-only
fields follow. This is the type-level complement to the name-only # Fields:
header — nothing is hand-authored.
" \
        --example "Inspect a producer" "bu get-shape get-command" \
        --example "Types for grouping/aggregation" "bu get-shape get-command | bu where 'type == \"number\"' select name"
    return 0
fi

if [[ -z "$producer" ]]
then
    error_msg="Expected a producer command name (e.g. bu get-shape get-command)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

local producer_file=${BU_COMMANDS[$producer]:-}
if [[ -z "$producer_file" || ! -f "$producer_file" ]]
then
    bu_log_err "Unknown or non-file producer[$producer]. bu get-shape resolves file-backed commands only."
    bu_scope_pop_function
    return 1
fi

# Declared schema (name list + order) from the # Fields: header.
local declared=
__bu_command_header_get "$producer_file" "Fields" declared
local -a declared_fields=()
read -r -a declared_fields <<< "$declared"
local declared_json='[]'
if ((${#declared_fields[@]} > 0))
then
    declared_json=$("$BU_OUT_JQ" -cn --args '$ARGS.positional' -- "${declared_fields[@]}")
fi

# Run the producer once in a subshell and infer the schema in a single jq
# pass: per-field type(s), required flag, and counts, merged with the
# declared field list (declared order first, then inferred-only fields).
local -a out_args=(--format "$format")
[[ -n "$columns" ]] && out_args+=(--columns "$columns")

( BU_COMP_FAKE=1 bu "$producer" --format jsonl 2>/dev/null ) \
    | "$BU_OUT_JQ" -sc --argjson declared "$declared_json" '
        . as $rows
        | ($rows | length) as $total
        | (($rows | map(keys_unsorted) | add) // []) | unique as $seen
        | ($declared + [ $seen[] | select(. as $k | $declared | index($k) == null) ]) as $keys
        | $keys[] as $k
        | ([$rows[] | select(has($k))] | length) as $cnt
        | ([$rows[] | select(has($k) and .[$k] == null)] | length) as $nulls
        | ([$rows[] | select(has($k)) | .[$k] | type] | unique) as $ts
        | {
            name: $k,
            type: (if ($ts | length) == 1 then $ts[0] elif ($ts | length) > 1 then "mixed" else null end),
            types: ($ts | join("|")),
            required: ($total > 0 and $cnt == $total),
            count: $cnt,
            null_count: $nulls
          }
    ' | bu_out "${out_args[@]}"

bu_scope_pop_function
}

__bu_bu_get_shape_main "$@"
