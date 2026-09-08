#!/usr/bin/env bash
# Pipeline: consume
# Requires-All: pid
# Dispatch: source
# Synopsis: Terminate a running process
function __bu_bu_stop_process_main()
{
# --is-compatible: magic flag checked by the framework at registration time.
# Exit 0 if this command can run on the current system, non-zero otherwise.
# stderr becomes the reason shown in `bu` help.
if [[ "$1" == "--is-compatible" ]]; then
    exit 0
fi
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local -a pids=()
local signal=TERM
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
    -s|--signal)# SIGNAL
        # Signal to send
        bu_parse_positional $# --enum TERM KILL INT HUP QUIT STOP CONT USR1 USR2 enum-- --hint "Signal name"
        signal=${!shift_by}
        ;;
    --what-if)# _FLAG
        # Show what would be signaled without sending anything
        is_what_if=true
        ;;
    --format)# FORMAT
        # Output format
        bu_parse_positional $# --enum ${BU_OUT_FORMATS[@]} enum-- --hint "Output format"
        format=${!shift_by}
        ;;
    --pid)# PID
        # Numeric PID to signal (repeatable; also accepts pipeline input by structural typing)
        bu_parse_positional $# --hint "Process ID"
        pids+=("${!shift_by}")
        ;;
    -h|--help)# _FLAG
        # Print help
        is_help=true
        ;;
    *)
        if bu_env_is_in_autocomplete
        then
            # PID positional: complete from the live process list
            autocompletion=(--stdout ps -eo pid=,comm= stdout-- --hint "PID")
        fi
        pids+=("$1")
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
Send a signal to processes (PowerShell Stop-Process, structured kill).
PIDs come from positional arguments or, when stdin is a JSONL stream, from
the .pid field of incoming records — enabling pipelines like
'bu get-process | bu where ... | bu stop-process'. Emits one
record per PID: pid, signal, stopped (boolean).
" \
        --example "Terminate by PID" "1234" \
        --example "Force kill" "1234 --signal KILL" \
        --example "Pipeline (preview with --what-if)" "--what-if"
    return 0
fi

# Pipeline input: collect PIDs from the .pid field of incoming records
if ((${#pids[@]} == 0)) && [[ ! -t 0 ]]
then
    local pid
    while IFS= read -r pid
    do
        [[ -n "$pid" ]] && pids+=("$pid")
    done < <(__bu_out_strict_guard "stop-process" | jq -r '.pid // empty' 2>/dev/null)
fi

if ((${#pids[@]} == 0))
then
    error_msg="No PIDs given. Pass PIDs as arguments or pipe records with a .pid field (e.g. bu get-process | bu stop-process)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

# Records go to a temp file (not a pipeline) so the loop runs in the current
# shell and the per-PID failure status survives in rc.
local records_file
records_file=$(mktemp)
bu_scope_add_cleanup rm -f "$records_file"

local rc=0
local pid
{
    for pid in "${pids[@]}"
    do
        if [[ ! "$pid" =~ ^[0-9]+$ ]]
        then
            bu_out_record pid="$pid" signal="$signal" stopped:=false error="not a numeric PID"
            rc=1
            continue
        fi
        if "$is_what_if"
        then
            bu_log_info "What if: send $signal to PID $pid"
            continue
        fi
        if kill -s "$signal" "$pid" 2>/dev/null
        then
            bu_out_record pid:="$pid" signal="$signal" stopped:=true
        else
            bu_out_record pid:="$pid" signal="$signal" stopped:=false error="kill failed (no such process or permission denied)"
            rc=1
        fi
    done
} > "$records_file"

bu_out --format "$format" < "$records_file"

bu_scope_pop_function
return $rc
}

__bu_bu_stop_process_main "$@"
