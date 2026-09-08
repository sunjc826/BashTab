#!/usr/bin/env bash
# Pipeline: sink
# Dispatch: source
# Synopsis: Dispatch a JSONL stream to the appropriate output formatter
function __bu_bu_out_default_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local format=auto
local columns=
local colors=
local style=
local is_stream=false
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --format)# FORMAT
        # Output format (auto resolves to table on a terminal, jsonl otherwise)
        bu_parse_positional $# --enum ${BU_OUT_FORMATS[@]} enum-- --hint "Output format"
        bu_validate_positional "${!shift_by}"
        format=${!shift_by}
        ;;
    --columns)# COLUMNS
        # Columns to display, in order (comma-separated). Forwarded to table/list/tsv.
        bu_parse_positional $# --hint "Comma-separated columns" --pipeline-fields pipeline-fields--
        columns=${!shift_by}
        ;;
    --colors)# COLORS
        # Colorize column cells (comma-separated key=color pairs). Forwarded to table.
        bu_parse_positional $# --hint "Comma-separated key=color pairs (e.g. name=green,version=yellow)"
        colors=${!shift_by}
        ;;
    --style)# STYLE
        # Table border/separator style (classic, plain, ascii, unicode, double, clickhouse, markdown, mysql, psql)
        bu_parse_positional $# --enum "${!__BU_TABLE_STYLES[*]}" enum--
        bu_validate_positional "${!shift_by}"
        style=${!shift_by}
        ;;
    --stream)# _FLAG
        # Stream table rows as they arrive (forwarded to table)
        is_stream=true
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
Format a JSONL stream, auto-detecting the best format (PowerShell Out-Default).
Resolution order: --format, then \$BU_OUTPUT_FORMAT, then terminal detection
(table on a terminal, jsonl when piped).
" \
        --example "Auto format" "" \
        --example "Force a table" "--format table --columns name,version"
    return 0
fi

local -a out_args=(--format "$format")
[[ -n "$columns" ]] && out_args+=(--columns "$columns")
[[ -n "$colors" ]] && out_args+=(--colors "$colors")
[[ -n "$style" ]] && out_args+=(--style "$style")
"$is_stream" && out_args+=(--stream)
bu_out "${out_args[@]}"

bu_scope_pop_function
}

__bu_bu_out_default_main "$@"
