#!/usr/bin/env bash
# Pipeline: producer
# Fields: index path
# Dispatch: source
# Synopsis: Show the pushd/popd directory stack
# Help-Topic: locations
function __bu_bu_get_location_stack_main()
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
Show the directory stack (structured dirs -v).
Each record: index (0 = current directory) and path. The stack is managed
with bu push-location and bu pop-location.
" \
        --example "Default" ""
    return 0
fi

# dirs -v prints: ' 0  /path' (one per line)
local idx path
{
    while read -r idx path
    do
        [[ -z "$idx" ]] && continue
        bu_out_record index:="$idx" path="$path"
    done < <(dirs -v)
} | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_get_location_stack_main "$@"
