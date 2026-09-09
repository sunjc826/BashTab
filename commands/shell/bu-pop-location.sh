#!/usr/bin/env bash
# Pipeline: producer
# Fields: path action dry_run
# Dispatch: source
# Synopsis: Pop the top directory off the pushd stack
# Help-Topic: locations
function __bu_bu_pop_location_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local format=auto
local is_help=false
local is_dry_run=false
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
    --dry-run|--what-if) # _FLAG
        is_dry_run=true
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
Pop the directory stack and cd to the popped entry (PowerShell Pop-Location, popd).
Runs in the current shell, so the cd takes effect. Fails when the stack
has only the current directory. Emits the new location as a record.
" \
        --example "Go back" ""
    return 0
fi

if "$is_dry_run"; then
    bu_out_record action="would-pop" dry_run:=true | bu_out --format "$format"
else
# Runs sourced, so popd affects the current shell's directory stack
if ! popd &>/dev/null
then
    error_msg="Directory stack is empty (nothing to pop)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

bu_out_record path="$PWD" | bu_out --format "$format"

fi
bu_scope_pop_function
}

__bu_bu_pop_location_main "$@"
