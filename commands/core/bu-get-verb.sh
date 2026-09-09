#!/usr/bin/env bash
# Pipeline: producer
# Dispatch: source
# Synopsis: List known BashTab verbs
# Help-Topic: commands
# Fields: name
function __bu_bu_get_verb_main()
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
        bu_parse_positional $# --enum name enum-- --hint "Comma-separated fields"
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
    bu_autohelp \
        --description "
List all known verbs from registered commands (BU_COMMAND_VERBS).
Verbs are the leading part of each verb-noun command name.
Multi-word verbs like convert-to and convert-from are included.

Output is structured: piped output defaults to JSONL, terminal output
defaults to a table. Use --format to override.
" \
        --example "List all verbs" "" \
        --example "List verbs as JSON array" "--format json" \
        --example "List verbs as a plain list" "--format list"
    return 0
fi

if ((${#BU_COMMAND_VERBS[@]} == 0))
then
    bu_log_info "No verbs registered."
else
    # Stream TSV records (zero forks in the loop), recordify once, then
    # let bu_out decide presentation (table on a terminal, JSONL when piped)
    local verb
    {
        for verb in "${!BU_COMMAND_VERBS[@]}"
        do
            [[ -z "$verb" ]] && continue
            printf '%s\n' "$verb"
        done
    } | bu_out_from_lines --column name | bu_out --format "$format" ${columns:+--columns "$columns"}
fi

bu_scope_pop_function
}

__bu_bu_get_verb_main "$@"
