#!/usr/bin/env bash
# Pipeline: producer
# Dispatch: source
# Synopsis: List registered command-line transforms
# Help-Topic: commands
# Fields: name match replace description module derived
function __bu_bu_get_transform_main()
{
# --is-compatible: no external dependencies
if [[ "$1" == "--is-compatible" ]]; then
    exit 0
fi

local -r invocation_dir=$PWD
local script_name script_dir
case "$BASH_SOURCE" in
*/*)
    script_name=${BASH_SOURCE##*/}
    script_dir=${BASH_SOURCE%/*}
    ;;
*)
    script_name=$BASH_SOURCE
    script_dir=.
    ;;
esac
pushd "$script_dir" &>/dev/null

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_scope_add_cleanup bu_popd_silent
bu_run_log_command "$@"

local format=${BU_OUTPUT_FORMAT:-auto}
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
        format=${!shift_by}
        ;;
    --columns)# COLUMNS
        # Fields to display, in order (comma-separated)
        bu_parse_positional $# --hint "Comma-separated fields: name match replace description module derived"
        columns=${!shift_by}
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
    bu_autohelp
    return 0
fi

{
    local key name
    for key in "${!BU_LINE_TRANSFORM_PROPERTIES[@]}"
    do
        [[ "$key" == *,match ]] || continue
        name=${key%,match}
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$name" \
            "${BU_LINE_TRANSFORM_PROPERTIES[$name,match]:-}" \
            "${BU_LINE_TRANSFORM_PROPERTIES[$name,replace]:-}" \
            "${BU_LINE_TRANSFORM_PROPERTIES[$name,description]:-}" \
            "${BU_LINE_TRANSFORM_PROPERTIES[$name,module]:-}" \
            "${BU_LINE_TRANSFORM_PROPERTIES[$name,derived]:-false}"
    done
} | bu_out_from_tsv --columns name,match,replace,description,module,derived \
  | bu_out --format "$format" ${columns:+--columns "$columns"}

bu_scope_pop_function
}

__bu_bu_get_transform_main "$@"
