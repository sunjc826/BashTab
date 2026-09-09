#!/usr/bin/env bash
# Pipeline: producer
# Dispatch: source
# Tab-Execute: true
# Synopsis: Show which commands consumed which context variables
# Fields: ts command var value local source origin
function __bu_bu_get_context_usage_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

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
        # Fields to display, in order (comma-separated)
        bu_parse_positional $# --enum ts command var value local source origin enum-- --hint "Comma-separated fields"
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
Census of context-variable consumption logged by bu_context_default and
bu_context_use (see docs/context_variables.md).  Each record answers: which
command consulted which ambient context variable, what value it held, what
local it mapped to, whether the value was used or overridden by a flag, and
where the variable was last assigned.

Records are appended by the helpers to \$BU_OUT_DIR/context/<YYYY-MM-DD>.jsonl
(one file per day; daily files sort lexically, which is chronologically).
This command concatenates them into a single JSONL stream.

Output is structured: piped output defaults to JSONL, terminal output
defaults to a table.  Use --format to override.
" \
        --example "Show all consumption records" "" \
        --example "Which commands use MY_APP_COLO" "| bu query-object where var -eq MY_APP_COLO select command distinct"
    return 0
fi

local context_dir=${BU_OUT_DIR:-}/context
local -a files=()
if [[ -d "$context_dir" ]]
then
    local f
    for f in "$context_dir"/*.jsonl
    do
        [[ -f "$f" ]] && files+=("$f")
    done
fi

if ((${#files[@]} == 0))
then
    # No records — empty success.
    bu_scope_pop_function
    return 0
fi

cat "${files[@]}" | bu_out --format "$format" ${columns:+--columns "$columns"}

bu_scope_pop_function
}

__bu_bu_get_context_usage_main "$@"
