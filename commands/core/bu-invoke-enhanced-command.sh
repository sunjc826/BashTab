#!/usr/bin/env bash
# Pipeline: standalone
# Dispatch: source
# Synopsis: Execute a command with progress bar and enhanced output
function __bu_bu_invoke_enhanced_command_main()
{
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

# Note that we do not source bu_entrypoint inside the sourceable script template
# as it is assumed that sourceable scripts are sourced AFTER 
# bu_entrypoint has been sourced by the user.

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_scope_add_cleanup bu_popd_silent
bu_run_log_command "$@"

local bu_run_args=()

local is_help=false
local error_msg=
local options_finished=false
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --gdb)
        # Append gdb ahead of the command
        bu_run_args+=("$1")
        ;;
    --log)
        # Log the command stdout + stderr to BU_LOG_DIR[${BU_LOG_DIR}]
        bu_run_args+=("$1")
        ;;
    --log-stdout)
        # Log the command stdout to BU_LOG_DIR[${BU_LOG_DIR}]
        bu_run_args+=("$1")
        ;;
    --copy-logs-to)
        # File or directory to copy the logs to
        bu_parse_positional $# "${BU_AUTOCOMPLETE_SPEC_DIRECTORY[@]}"
        bu_run_args+=("$1" "$2")
        ;;
    --open-logs)
        # Open logs in a code editor
        bu_run_args+=("$1")
        ;;
    --kill)
        # Kill any existing process of the same name
        bu_run_args+=("$1")
        ;;
    --ignore-non-zero-exit-code)
        # If the command returns non-zero exit code, it will not be forwarded.
        # A non-zero exit code of bu_run must imply that something within bu_run failed. 
        bu_run_args+=("$1")
        ;;
    --watch)
        # Interval for the watch command
        bu_parse_positional $# --hint "${BU_TPUT_BOLD}watch${BU_TPUT_RESET} interval"
        bu_run_args+=("$1" "$2")
        ;;
    --ldd)
        # Run ldd on the command before executing it.
        bu_run_args+=("$1")
        ;;
    --dry-run)
        # Do not actually run the command. Good for scripting and forwarding the --dry-run flag.
        bu_run_args+=("$1")
        ;;
    --no-log-last-run-cmd)
        # Do not place the ran command into BU_LAST_RUN_CMDS[${BU_LAST_RUN_CMDS}]
        bu_run_args+=("$1")
        ;;
    --cmd-log-file)
        # Additional log file (in addition to $BU_LAST_RUN_CMDS) to log to
        bu_parse_positional $# "${BU_AUTOCOMPLETE_SPEC_DIRECTORY[@]}"
        bu_run_args+=("$1" "$2")
        ;;
    --working-directory)
        bu_parse_positional $# "${BU_AUTOCOMPLETE_SPEC_DIRECTORY[@]}"
        bu_run_args+=("$1" "$2")
        ;;
    --mapfile)
        bu_run_args+=("$1")
        ;;
    --mapfile-str)
        bu_run_args+=("$1")
        ;;
    --mapfile-outparam)
        bu_parse_positional $# --hint outparam
        bu_run_args+=("$1" "$2")
        ;;
    -h|--help)
        # Print help
        is_help=true
        ;;
    --)
        # Remaining options will be collected
        bu_run_args+=("$1")
        options_finished=true
        shift
        break
        ;;
    ''|-*)
        bu_parse_error_enum "$1"
        break
        ;;
    *)
        bu_spawn_args+=(--)
        options_finished=true
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
    bu_autocomplete_remaining +c --as-if "${remaining_options[@]}" as-if--
    return 0
fi

if "$is_help"
then
    bu_autohelp --description "Wrapper script around the bu_run function. Use the function directly in scripts for higher performance."
    return 0
fi

bu_run_args+=("${remaining_options[@]}")

bu_scope_pop_function

bu_run "${bu_run_args[@]}"
}

__bu_bu_invoke_enhanced_command_main "$@"
