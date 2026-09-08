#!/usr/bin/env bash
# Dispatch: source
# Pipeline: producer
# Synopsis: Statically validate field references in a pipeline
# Fields: field
function __bu_bu_validate_pipeline_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local pipeline=
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
        if [[ -n "$pipeline" ]]
        then
            bu_parse_error_enum "$1"
            break
        fi
        pipeline=$1
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
Statically validate a pipeline's field references. Walks each stage,
tracking which fields are available at each point, and reports any field a
stage reads that is not produced upstream (e.g. 'bu get-command | bu sort
madeup' reports 'madeup'). Quote the whole pipeline as one argument.

Only structurally-parseable reads are checked: sort/select/where/group-by
field arguments and # Requires-All: / # Requires-Any: contracts. Raw jq
expressions, order-by aliases, and grep patterns are skipped. Unknown
producers make the available field set unknown, which skips further
validation rather than reporting false positives.
" \
        --example "Catch a typo" "bu validate-pipeline 'bu get-command | bu sort madeup'" \
        --example "A valid pipeline" "bu validate-pipeline 'bu get-command | bu select name'"
    return 0
fi

if [[ -z "$pipeline" ]]
then
    error_msg="Expected a pipeline string (quote it: bu validate-pipeline 'bu get-command | bu sort name')"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

local -a warnings=()
__bu_out_validate_pipeline "$pipeline"
warnings=("${BU_RET[@]}")

local -a out_args=(--format "$format")
[[ -n "$columns" ]] && out_args+=(--columns "$columns")

if ((${#warnings[@]} == 0))
then
    # No field errors: emit nothing (PowerShell Out-Default semantics).
    bu_scope_pop_function
    return 0
fi

{
    local field
    for field in "${warnings[@]}"
    do
        printf '%s\n' "$field"
    done
} | bu_out_from_lines --column field | bu_out "${out_args[@]}"

bu_scope_pop_function
}

__bu_bu_validate_pipeline_main "$@"
