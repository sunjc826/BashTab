#!/usr/bin/env bash
# Pipeline: producer
# Fields: path
# Dispatch: source
# Synopsis: Print the current working directory
function __bu_bu_get_location_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local is_physical=false
local format=auto
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    -P|--physical)# _FLAG
        # Resolve symlinks (pwd -P)
        is_physical=true
        ;;
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
Show the current working directory as a record (PowerShell Get-Location).
path is the logical view (respecting symlinks) unless --physical is
given. See also bu set-location, bu push-location, bu get-location-stack.
" \
        --example "Default" "" \
        --example "Physical path" "--physical"
    return 0
fi

local path
if "$is_physical"
then
    path=$(pwd -P)
else
    path=$(pwd -L)
fi

bu_out_record path="$path" | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_get_location_main "$@"
