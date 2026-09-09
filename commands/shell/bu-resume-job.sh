#!/usr/bin/env bash
# Pipeline: transform
# Requires-All: job_number
# Fields: job_number action resumed error
# Dispatch: source
# Synopsis: Resume a suspended background job
function __bu_bu_resume_job_main()
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
local is_foreground=false
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
    --foreground|-f)# _FLAG
        # Bring the job to the foreground (fg); default is background (bg)
        is_foreground=true
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
Resume suspended or background jobs (PowerShell Resume-Job analog, fg/bg).
Runs sourced in the current shell. By default runs jobs in the background (bg);
use --foreground to bring to the foreground (fg). Only the last job goes to
the foreground when --foreground is used with multiple jobs. Emits one record
per job.

Accepts pipeline input from get-job (reads .job_number field).
Job specifiers with a leading % are accepted and stripped automatically.
" \
        --example "Background job 1" "1" \
        --example "Foreground job" "2 --foreground" \
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
    error_msg="No job numbers given. Pass job numbers as arguments or pipe records with a .job_number field (e.g. bu get-job | bu resume-job)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

local records_file
records_file=$(mktemp)
bu_scope_add_cleanup rm -f "$records_file"

local rc=0
local job_number action
{
    for job_number in "${job_numbers[@]}"
    do
        if [[ ! "$job_number" =~ ^[0-9]+$ ]]
        then
            bu_out_record job_number="$job_number" resumed:=false error="not a numeric job number"
            rc=1
            continue
        fi
        if "$is_foreground"
        then
            action=foreground
            if "$is_what_if"
            then
                bu_log_info "What if: fg %$job_number"
            else
                fg "%$job_number" 2>/dev/null || { bu_out_record job_number:="$job_number" action="$action" resumed:=false error="fg failed (no such job)"; rc=1; continue; }
                bu_out_record job_number:="$job_number" action="$action" resumed:=true
            fi
        else
            action=background
            if "$is_what_if"
            then
                bu_log_info "What if: bg %$job_number"
            else
                if bg "%$job_number" 2>/dev/null
                then
                    bu_out_record job_number:="$job_number" action="$action" resumed:=true
                else
                    bu_out_record job_number:="$job_number" action="$action" resumed:=false error="bg failed (no such job)"
                    rc=1
                fi
            fi
        fi
    done
} > "$records_file"

bu_out --format "$format" < "$records_file"

bu_scope_pop_function
return $rc
}

__bu_bu_resume_job_main "$@"
