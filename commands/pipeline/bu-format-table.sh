#!/usr/bin/env bash
# Dispatch: source
# Synopsis: Render a JSONL stream as an aligned table
function __bu_bu_format_table_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

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
    --columns)# COLUMNS
        # Columns to display, in order (comma-separated). Default: keys of the first record.
        bu_parse_positional $# --hint "Comma-separated columns" --pipeline-fields pipeline-fields--
        columns=${!shift_by}
        ;;
    --colors)# COLORS
        # Colorize column cells (comma-separated key=color pairs)
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
        # Stream rows as they arrive with proportional widths (requires --columns)
        # instead of buffering all records for optimal auto-widths.
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
Render a JSONL stream as an aligned table (PowerShell Format-Table).
Reads records from stdin. Column widths are computed from the data and
shrunk to fit the terminal; the header is bold on a terminal.
" \
        --example "Select columns" "--columns name,version" \
        --example "Streaming mode" "--columns name,version --stream"
    return 0
fi

local -a formatter_args=()
[[ -n "$columns" ]] && formatter_args+=(--columns "$columns")
[[ -n "$colors" ]] && formatter_args+=(--colors "$colors")
[[ -n "$style" ]] && formatter_args+=(--style "$style")
"$is_stream" && formatter_args+=(--stream)
bu_format_table "${formatter_args[@]}"

bu_scope_pop_function
}

__bu_bu_format_table_main "$@"
