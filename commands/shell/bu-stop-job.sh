#!/usr/bin/env bash
# Pipeline: transform
# Requires-All: job_number
# Fields: job_number signal stopped error
# Dispatch: source
# Synopsis: Stop a background job
function __bu_bu_stop_job_main()
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

local -a job_numbers=()
local signal=STOP
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
        # Signal to send (default: STOP)
        bu_parse_positional $# --enum STOP TERM KILL CONT enum-- --hint "Signal name"
        signal=${!shift_by}
        ;;
    --what-if)# _FLAG
        # Show what would happen without changing anything
        is_what_if=true
        ;;
    --format)# FORMAT
        # Output format
        bu_parse_positional $# --enum ${BU_OUT_FORMATS[@]} enum-- --hint "Output format"
        format=${!shift_by}
        ;;
    --job-number)# JOB
        # Job number or specifier, e.g. 1 or %1 (repeatable)
        bu_parse_positional $# --hint "Job number (e.g. 1 or %1)"
        job_numbers+=("${!shift_by}")
        ;;
    -h|--help)# _FLAG
        # Print help
        is_help=true
        ;;
    *)
        # Accept bare job numbers, stripping leading %
        if bu_env_is_in_autocomplete
        then
            autocompletion=(--hint "Job number (e.g. 1 or %1)")
        fi
        job_numbers+=("${1#%}")
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
Stop (suspend) background jobs by sending a signal (PowerShell Stop-Job analog).
Runs sourced in the current shell. Default signal is STOP (suspend without
terminating); use --signal TERM or KILL to terminate. Emits one record per job.

Accepts pipeline input from get-job (reads .job_number field).
Job specifiers with a leading % are accepted and stripped automatically.
" \
        --example "Suspend job 1" "1" \
        --example "Terminate job" "2 --signal TERM" \
        --example "With percent" "%3" \
        --example "Dry run" "1 --what-if" \
        --example "Pipeline from get-job" ""
    return 0
fi

# Pipeline input: collect job numbers from .job_number field
if ((${#job_numbers[@]} == 0)) && [[ ! -t 0 ]]
then
    local _j
    while IFS= read -r _j
    do
        [[ -n "$_j" ]] && job_numbers+=("$_j")
    done < <(jq -r '.job_number // empty' 2>/dev/null)
fi

if ((${#job_numbers[@]} == 0))
then
    error_msg="No job numbers given. Pass job numbers as arguments or pipe records with a .job_number field (e.g. bu get-job | bu stop-job)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

local records_file
records_file=$(mktemp)
bu_scope_add_cleanup rm -f "$records_file"

local rc=0
local job_number
{
    for job_number in "${job_numbers[@]}"
    do
        if [[ ! "$job_number" =~ ^[0-9]+$ ]]
        then
            bu_out_record job_number="$job_number" signal="$signal" stopped:=false error="not a numeric job number"
            rc=1
            continue
        fi
        if "$is_what_if"
        then
            bu_log_info "What if: kill -s $signal %$job_number"
            continue
        fi
        if kill -s "$signal" "%$job_number" 2>/dev/null
        then
            bu_out_record job_number:="$job_number" signal="$signal" stopped:=true
        else
            bu_out_record job_number:="$job_number" signal="$signal" stopped:=false error="kill failed (no such job)"
            rc=1
        fi
    done
} > "$records_file"

bu_out --format "$format" < "$records_file"

bu_scope_pop_function
return $rc
}

__bu_bu_stop_job_main "$@"
