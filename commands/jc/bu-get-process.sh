#!/usr/bin/env bash
# Pipeline: producer
# Dispatch: source
# Synopsis: List running processes
# Fields: user pid vsz rss tty stat start time command cpu_percent mem_percent
function __bu_bu_get_process_main()
{
# --is-compatible: magic flag checked by the framework at registration time.
# Exit 0 if this command can run on the current system, non-zero otherwise.
# stderr becomes the reason shown in `bu` help.
if [[ "$1" == "--is-compatible" ]]; then
    command -v jc &>/dev/null || { echo "jc is required" >&2; exit 1; }
    command -v ps &>/dev/null || { echo "ps is required" >&2; exit 1; }
    exit 0
fi
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local is_help=false
local format=auto
local user=
local pid=
local command_name=
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
    -u|--user)# USER
        # Filter by effective user (passes -u to ps)
        bu_parse_positional $# --hint "Username or UID"
        user=${!shift_by}
        ;;
    -p|--pid)# PID
        # Filter by process ID (passes -p to ps)
        bu_parse_positional $# --hint "Process ID"
        pid=${!shift_by}
        ;;
    -C|--command)# COMMAND
        # Filter by command name (passes -C to ps)
        bu_parse_positional $# --hint "Command name"
        command_name=${!shift_by}
        ;;
    -h|--help)# _FLAG
        is_help=true
        ;;
    --)
        shift
        break
        ;;
    *)
        # Any unrecognized arg: pass through to the underlying command, replacing the default
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
local remaining_options=("$@")
if bu_env_is_in_autocomplete
then
    bu_autocomplete
    return 0
fi

if "$is_help"
then
    bu_autohelp \
        --description "List running processes (jc ps parser wrapper)." \
        --example "All processes" "" \
        --example "By user" "--user root" \
        --example "By PID" "--pid 1234" \
        --example "By command name" "--command nginx" \
        --example "With extra flags" "-- -la /var/log"
    return 0
fi

if ! command -v jc &>/dev/null
then
    error_msg="jc is required. Install with: pip install jc"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

# Build the command: use provided args if any, otherwise the default
local -a cmd=()
if [[ -n "$user" ]] || [[ -n "$pid" ]] || [[ -n "$command_name" ]] || ((${#remaining_options[@]} > 0))
then
    # Use explicit ps invocation with flags
    cmd=(ps)
    [[ -n "$user" ]] && cmd+=(-u "$user")
    [[ -n "$pid" ]] && cmd+=(-p "$pid")
    [[ -n "$command_name" ]] && cmd+=(-C "$command_name")
    # Default to aux output format unless user provided custom args
    if ((${#remaining_options[@]} > 0))
    then
        cmd+=("${remaining_options[@]}")
    else
        cmd+=(aux)
    fi
else
    cmd=(ps aux)
fi

"${cmd[@]}" 2>/dev/null | jc --ps 2>/dev/null | jq -c 'if type == "array" then .[] else . end' 2>/dev/null | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_get_process_main "$@"
