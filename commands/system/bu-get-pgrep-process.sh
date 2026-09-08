#!/usr/bin/env bash
# Pipeline: producer
# Dispatch: source
# Synopsis: List processes matching a name pattern
# Fields: pid command
function __bu_bu_get_pgrep_process_main()
{
# --is-compatible: magic flag checked by the framework at registration time.
# Exit 0 if this command can run on the current system, non-zero otherwise.
# stderr becomes the reason shown in `bu` help.
if [[ "$1" == "--is-compatible" ]]; then
    command -v pgrep &>/dev/null || { echo "pgrep is required" >&2; exit 1; }
    exit 0
fi
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local pattern=
local is_full=false
local is_help=false
local format=auto
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
        is_help=true
        ;;
    -f|--full)# _FLAG
        # Use pgrep -af (full command line)
        is_full=true
        ;;
    *)
        if [[ -z "$pattern" ]]
        then
            pattern=$1
        else
            bu_parse_error_enum "$1"
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
local remaining_options=("$@")
if bu_env_is_in_autocomplete
then
    bu_autocomplete
    return 0
fi

if "$is_help"
then
    bu_autohelp \
        --description "
Find processes by name pattern and emit them as JSONL records (pgrep wrapper).
Each record contains the PID and the process command line.

Fields: pid, command
" \
        --example "Find bash processes" "bash" \
        --example "Full command line" "-f nginx"
    return 0
fi

if [[ -z "$pattern" ]]
then
    error_msg="Missing required pattern (e.g. bu get-pgrep-process bash)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

# Run pgrep, split on first space/tab into pid and command
local pgrep_output
if "$is_full"
then
    pgrep_output=$(pgrep -af "$pattern" 2>/dev/null) || true
else
    pgrep_output=$(pgrep -a "$pattern" 2>/dev/null) || true
fi

if [[ -z "$pgrep_output" ]]
then
    bu_scope_pop_function
    return 0
fi

# Parse "PID COMMAND" into records, splitting on first whitespace
while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local pid=${line%%[[:space:]]*}
    local command=${line#*[[:space:]]}
    bu_out_record pid="$pid" command="$command"
done <<<"$pgrep_output" | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_get_pgrep_process_main "$@"
