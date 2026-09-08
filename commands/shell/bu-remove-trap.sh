#!/usr/bin/env bash
# Pipeline: consume
# Requires-All: signal
# Dispatch: source
# Synopsis: Remove a shell trap handler
# Common signal names for completion.
__bu_bu_remove_trap_complete_signals()
{
    BU_RET=(EXIT SIGINT SIGTERM SIGQUIT SIGHUP SIGUSR1 SIGUSR2 SIGALRM SIGPIPE SIGCHLD SIGTSTP SIGCONT SIGSTOP)
}

function __bu_bu_remove_trap_main()
{
set -e
local -r invocation_dir=$PWD
local script_name
local script_dir
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

if [[ -z "$COMP_CWORD" ]]
then
# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_DIR"/bu_entrypoint.sh
fi

bu_exit_handler_setup
bu_scope_push_function
bu_scope_add_cleanup bu_popd_silent
bu_run_log_command "$@"

local -a signals=()
local is_what_if=false
local format=auto
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --what-if)# _FLAG
        # Show what would happen without changing anything
        is_what_if=true
        ;;
    --format)# FORMAT
        # Output format
        bu_parse_positional $# --enum ${BU_OUT_FORMATS[@]} enum-- --hint "Output format"
        format=${!shift_by}
        ;;
    --signal)# SIGNAL
        # Signal name (repeatable; also accepts pipeline input)
        bu_parse_positional $# --ret __bu_bu_remove_trap_complete_signals ret-- --hint "Signal name"
        signals+=("${!shift_by}")
        ;;
    -h|--help)# _FLAG
        # Print help
        is_help=true
        ;;
    *)
        if bu_env_is_in_autocomplete
        then
            autocompletion=(--ret __bu_bu_remove_trap_complete_signals ret-- --hint "Signal name")
        fi
        signals+=("$1")
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
Remove signal traps (structured trap - SIGNAL).
Runs sourced in the current shell. Removes the trap for the given signal,
restoring default behavior. Emits one record per signal: signal, removed (boolean).

Accepts pipeline input from get-trap (reads .signal field).
" \
        --example "Remove EXIT trap" "EXIT" \
        --example "Multiple signals" "SIGINT SIGTERM" \
        --example "Dry run" "EXIT --what-if" \
        --example "Pipeline from get-trap" ""
    return 0
fi

# Pipeline input: when no signals are given and stdin is a pipe,
# read JSONL records and extract .signal.
if ((${#signals[@]} == 0)) && [[ ! -t 0 ]]
then
    local _s
    while IFS= read -r _s
    do
        [[ -n "$_s" ]] && signals+=("$_s")
    done < <(__bu_out_strict_guard "remove-trap" | jq -r '.signal // empty' 2>/dev/null)
fi

if ((${#signals[@]} == 0))
then
    error_msg="Missing required signal name (e.g. bu remove-trap EXIT)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

local records_file
records_file=$(mktemp)
bu_scope_add_cleanup rm -f "$records_file"

local rc=0
local signal
{
    for signal in "${signals[@]}"
    do
        if "$is_what_if"
        then
            bu_log_info "What if: trap - $signal"
            continue
        fi
        if trap - "$signal" 2>/dev/null
        then
            bu_out_record signal="$signal" removed:=true
        else
            bu_out_record signal="$signal" removed:=false error="trap removal failed"
            rc=1
        fi
    done
} > "$records_file"

bu_out --format "$format" < "$records_file"

bu_scope_pop_function
return $rc
}

__bu_bu_remove_trap_main "$@"
