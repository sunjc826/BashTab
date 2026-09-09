#!/usr/bin/env bash
# Pipeline: producer
# Dispatch: source
# Synopsis: List BashTab configuration settings
# Help-Topic: config
# Fields: name value default allowed module description
function __bu_bu_get_config_main()
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
        bu_parse_positional $# --hint "Comma-separated fields: name value default allowed module description"
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

# Stream TSV records (zero forks in the loop), recordify once, then
# let bu_out decide presentation (table on a terminal, JSONL when piped).
{
    local key name current
    for key in "${!BU_CONFIG_PROPERTIES[@]}"
    do
        [[ "$key" == *,registered ]] || continue
        name=${key%,registered}
        current=${!name:-}
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$name" \
            "${current:-(unset)}" \
            "${BU_CONFIG_PROPERTIES[$name,default]:-}" \
            "${BU_CONFIG_PROPERTIES[$name,enum]:-${BU_CONFIG_PROPERTIES[$name,bool]:+true|false}}" \
            "${BU_CONFIG_PROPERTIES[$name,module]:-}" \
            "${BU_CONFIG_PROPERTIES[$name,hint]:-}"
    done
} | bu_out_from_tsv --columns name,value,default,allowed,module,description | bu_out --format "$format" ${columns:+--columns "$columns"}

bu_scope_pop_function
}

__bu_bu_get_config_main "$@"
