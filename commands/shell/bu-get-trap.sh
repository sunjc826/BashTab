#!/usr/bin/env bash
# Pipeline: producer
# Fields: signal handler
# Dispatch: source
# Synopsis: List active shell trap handlers
function __bu_bu_get_trap_main()
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
List registered signal traps (structured trap -p).
Each record: signal (e.g. EXIT, SIGINT) and handler (the command string).
An empty stream means no traps are set. Runs in the current shell.
" \
        --example "Default" ""
    return 0
fi

# trap -p prints: trap -- 'handler' SIGNAL   (one per line)
local line rest signal handler
{
    while IFS= read -r line
    do
        [[ "$line" == trap\ --\ * ]] || continue
        rest=${line#trap -- }
        signal=${rest##* }
        handler=${rest% "$signal"}
        # Strip the surrounding single quotes from the handler
        handler=${handler#\'}
        handler=${handler%\'}
        bu_out_record signal="$signal" handler="$handler"
    done < <(trap -p)
} | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_get_trap_main "$@"
