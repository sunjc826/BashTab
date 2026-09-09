#!/usr/bin/env bash
# Pipeline: producer
# Fields: command duration_ms exit_code
# Dispatch: source
# Synopsis: Time the execution of a command
function __bu_bu_measure_command_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local is_help=false
local format=auto
local is_pass_thru=false
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
    --pass-thru)# _FLAG
        # Replay the command's captured stdout after the timing record
        is_pass_thru=true
        ;;
    -h|--help)# _FLAG
        # Print help
        is_help=true
        ;;
    --)
        # Everything after -- is the command to measure
        shift
        break
        ;;
    *)
        # First unrecognized arg starts the command to measure
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
local -a measured_command=("$@")
if bu_env_is_in_autocomplete
then
    bu_autocomplete
    return 0
fi

if "$is_help"
then
    bu_autohelp \
        --description "
Time a command and report the duration as a record (PowerShell Measure-Command).
Emits one record: command, duration_ms, exit_code. The command's stdout
is captured and discarded unless --pass-thru is given; its stderr goes
straight through. Uses EPOCHREALTIME (bash 5+) for millisecond precision.
" \
        --example "Time a sleep" "sleep 1" \
        --example "Time a pipeline stage" "-- bu get-process --format json" \
        --example "Keep the output too" "ls --pass-thru"
    return 0
fi

if ((${#measured_command[@]} == 0))
then
    error_msg="Missing command to measure (e.g. bu measure-command sleep 1)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

local out_file
out_file=$(mktemp)
bu_scope_add_cleanup rm -f "$out_file"

local start end duration_ms exit_code
start=$EPOCHREALTIME
"${measured_command[@]}" > "$out_file"
exit_code=$?
end=$EPOCHREALTIME
duration_ms=$(awk -v s="$start" -v e="$end" 'BEGIN { printf "%.0f", (e - s) * 1000 }')

local command_string=${measured_command[*]}
if "$is_pass_thru"
then
    { bu_out_record command="$command_string" duration_ms:="$duration_ms" exit_code:="$exit_code"
      cat "$out_file"
    } | bu_out --format "$format"
else
    bu_out_record command="$command_string" duration_ms:="$duration_ms" exit_code:="$exit_code" \
        | bu_out --format "$format"
fi

bu_scope_pop_function
return $exit_code
}

__bu_bu_measure_command_main "$@"
