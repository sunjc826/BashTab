#!/usr/bin/env bash
# Pipeline: sink
# Synopsis: Display a file as an fzf-browsable table
function __bu_bu_view_table_main()
{
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
script_dir=$PWD

# Source entrypoint (executable script — runs in a new process)
if [[ -z "$COMP_CWORD" ]]; then
    source "$BU_DIR"/bu_entrypoint.sh
fi

bu_exit_handler_setup
bu_scope_push_function
bu_scope_add_cleanup bu_popd_silent
bu_run_log_command "$@"

local columns=
local colors=
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
        # Colorize column cells (comma-separated key=color pairs, or "auto" for rainbow)
        bu_parse_positional $# --hint "Comma-separated key=color pairs (e.g. name=green,version=yellow) or auto"
        colors=${!shift_by}
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
Interactive table viewer for JSONL streams.  A superior alternative to piping
through less(1) for tabular data — provides fixed headers, column-aware
horizontal scrolling, interactive sort, and search with vim/less keybindings.

Reads JSONL records from stdin and opens a full-screen TUI.  Press q to quit.
" \
        --example "View all commands" "" \
        --example "Select columns" "--columns name,type,namespace" \
        --example "With rainbow colors" "--colors auto"
    return 0
fi

# Source the table viewer engine
# shellcheck source=../../lib/core/bu_core_tv.sh
source "$BU_DIR/lib/core/bu_core_tv.sh"

# Enter the interactive viewer (reads stdin, renders TUI)
bu_tv_enter "$columns" "$colors"
local rc=$?

bu_scope_pop_function
return $rc
}

__bu_bu_view_table_main "$@"
