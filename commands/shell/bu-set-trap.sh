#!/usr/bin/env bash
# Pipeline: transform
# Requires-All: signal
# Fields: signal handler set error
# Dispatch: source
# Synopsis: Set a shell trap handler
# Common signal names for completion.
__bu_bu_set_trap_complete_signals()
{
    BU_RET=(EXIT SIGINT SIGTERM SIGQUIT SIGHUP SIGUSR1 SIGUSR2 SIGALRM SIGPIPE SIGCHLD SIGTSTP SIGCONT SIGSTOP)
}

function __bu_bu_set_trap_main()
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
local -a handlers=()
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
        # Signal name (repeatable)
        bu_parse_positional $# --ret __bu_bu_set_trap_complete_signals ret-- --hint "Signal name"
        signals+=("${!shift_by}")
        ;;
    --handler)# HANDLER
        # Handler command string (repeatable; pairs with --signal by position)
        bu_parse_positional $# --hint "Handler command (use '' to ignore)"
        handlers+=("${!shift_by}")
        ;;
    -h|--help)# _FLAG
        # Print help
        is_help=true
        ;;
    *)
        if bu_env_is_in_autocomplete && [[ "$1" != -* ]]
        then
            if ((${#signals[@]} == ${#handlers[@]}))
            then
                autocompletion=(--ret __bu_bu_set_trap_complete_signals ret-- --hint "Signal name")
            else
                autocompletion=(--hint "Handler command")
            fi
            bu_autocomplete
            return 0
        fi
        if ((${#signals[@]} == ${#handlers[@]}))
        then
            signals+=("$1")
        else
            handlers+=("$1")
        fi
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
Set signal traps (PowerShell-style trap, structured trap).
Runs sourced in the current shell. Each trap consists of a signal name
(e.g. EXIT, SIGINT) and a handler command string (use an empty string ''
to ignore the signal). Emits one record per trap.

Accepts pipeline input from get-trap (reads .signal and .handler fields).
Common signals: EXIT, SIGINT, SIGTERM, SIGQUIT, SIGHUP, SIGUSR1, SIGUSR2.
" \
        --example "Trap EXIT to clean up" "EXIT 'rm -f /tmp/my-temp'" \
        --example "Ignore SIGINT" "SIGINT ''" \
        --example "Named flags" "--signal EXIT --handler 'echo bye'" \
        --example "Pipeline from get-trap" ""
    return 0
fi

# Pipeline input: when no signals are given and stdin is a pipe,
# read JSONL records and extract .signal and .handler.
if ((${#signals[@]} == 0)) && [[ ! -t 0 ]]
then
    local _sig _handler
    while IFS=$'\t' read -r _sig _handler
    do
        [[ -n "$_sig" ]] || continue
        signals+=("$_sig")
        handlers+=("${_handler:-}")
    done < <(jq -r '[.signal, (.handler // "")] | @tsv' 2>/dev/null)
fi

# Align signals and handlers: if more signals than handlers, last handler repeats.
if ((${#signals[@]} == 0))
then
    error_msg="Missing required signal name (e.g. bu set-trap EXIT 'rm -f /tmp/my-temp')"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

local records_file
records_file=$(mktemp)
bu_scope_add_cleanup rm -f "$records_file"

local rc=0
local i signal handler err
{
    for i in "${!signals[@]}"
    do
        signal=${signals[$i]}
        handler=${handlers[$i]:-}
        if "$is_what_if"
        then
            bu_log_info "What if: trap -- ${handler@Q} $signal"
            continue
        fi
        if err=$(trap -- "$handler" "$signal" 2>&1)
        then
            bu_out_record signal="$signal" handler="$handler" set:=true
        else
            bu_out_record signal="$signal" handler="$handler" set:=false error="$err"
            rc=1
        fi
    done
} > "$records_file"

bu_out --format "$format" < "$records_file"

bu_scope_pop_function
return $rc
}

__bu_bu_set_trap_main "$@"
