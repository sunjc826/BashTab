#!/usr/bin/env bash
# Pipeline: passthrough
# Fields: name types count null_count
# Dispatch: source
# Synopsis: Show the schema of records in a JSONL stream
# Column: name string Field name
# Column: types string JSON types seen, joined with |
# Column: count int Records that contain the field
# Column: null_count int Records where the field is null
# Column: type string Declared column type (only when the producing pipeline is known)
# Column: unit string Declared unit (only when the producing pipeline is known)
# Column: description string Declared meaning (only when the producing pipeline is known)
function __bu_bu_get_member_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local format=auto
local first=
local has_first=true
local declared=
local has_declared=false
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

When the records come from a pipeline of bu commands whose columns are
declared (see bu get-column), each field also carries the declared type,
unit and description of its column; fields nobody declared have them null.
Records from a file or from other tools keep the four basic fields.
" \
        --example "Inspect bu commands" "" \
        --example "Pipe any producer" ""
    return 0
fi

# Join the declared columns of the pipeline feeding stdin, when its stages
# left sidecars (see bu_core_pipemeta.sh). Read a line first: by then every
# upstream sidecar is on disk.
IFS= read -r first || [[ -n "$first" ]] || has_first=false
__bu_pipemeta_resolve
if [[ "${BU_RET[1]}" == resolved ]] \
    && declared=$(__bu_column_explain_pipeline "${BU_RET[0]}" 2>/dev/null) \
    && [[ -n "$declared" ]]
then
    has_declared=true
fi

{
    if "$has_first"; then printf '%s\n' "$first"; fi
    cat
} | jq -sc --arg decl "$declared" --argjson has_declared "$has_declared" '
    . as $all
    | ($decl | split("\n") | map(select(length > 0) | fromjson | {key: .column, value: .}) | from_entries) as $d
    | ((map(keys_unsorted) | add) // []) | unique as $keys
    | $keys[] as $k
    | {
        name: $k,
        types: ([$all[] | select(has($k)) | .[$k] | type] | unique | join("|")),
        count: ([$all[] | select(has($k))] | length),
        null_count: ([$all[] | select(has($k) and .[$k] == null)] | length)
    }
    | if $has_declared
      then . + ($d[$k] // {} | {type, unit, description} | map_values(if . == "" then null else . end))
      else . end
' | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_get_member_main "$@"
