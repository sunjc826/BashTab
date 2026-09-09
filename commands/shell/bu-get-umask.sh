#!/usr/bin/env bash
# Pipeline: producer
# Fields: symbolic
# Dispatch: source
# Synopsis: Show the current file creation mask
function __bu_bu_get_umask_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local format=auto
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
Show the current umask as a record (structured umask).
Reports both forms: symbolic (e.g. u=rwx,g=rx,o=rx) and octal (e.g. 0022).
The umask masks permission bits from newly created files and directories.
" \
        --example "Default" ""
    return 0
fi

local symbolic octal
symbolic=$(umask -S)
octal=$(umask)

bu_out_record symbolic="$symbolic" octal="$octal" | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_get_umask_main "$@"
