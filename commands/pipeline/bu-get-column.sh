#!/usr/bin/env bash
# Dispatch: source
# Pipeline: producer
# Synopsis: Describe output columns and their lineage without executing commands
# Column: column string Output column name
# Column: type string Column value type
# Column: unit string Unit of measurement
# Column: description string Meaning of the column
# Column: source string Origin of the column description
# Column: producer string Command that produced the column
# Column: derived string How the column was derived
function __bu_bu_get_column_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local pipeline=
local format=auto
local columns=
local traced=
local status=0
local -a out_args=()
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
        bu_parse_positional $# --enum "${BU_OUT_FORMATS[@]}" enum-- --hint "Output format"
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
    bu_autohelp --description "Describe the output columns of a command or quoted pipeline without executing it." \
        --example "Trace a renamed column" "bu get-column 'get-module | select name,r=rank'"
    return 0
fi

if [[ -z "$pipeline" ]]
then
    error_msg="Expected a command or quoted pipeline (bu get-column 'get-module | select name')"
    bu_autohelp
    return 1
fi

out_args=(--format "$format")
[[ -n "$columns" ]] && out_args+=(--columns "$columns")
# Capture only metadata so a tracing failure survives the output pipeline.
traced=$(__bu_column_explain_pipeline "$pipeline") || status=$?
if ((status == 0)) && [[ -n "$traced" ]]; then
    printf '%s\n' "$traced" | bu_out "${out_args[@]}"
    status=$?
fi
bu_scope_pop_function
return "$status"
}

__bu_bu_get_column_main "$@"
