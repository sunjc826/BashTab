#!/usr/bin/env bash
# Pipeline: standalone
# Dispatch: source
# Synopsis: Exit the current remote session shell (refuses outside one)
function __bu_bu_exit_remote_session_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local code=0
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    -h|--help)# _FLAG
        # Print help
        is_help=true
        ;;
    -*)
        bu_parse_error_enum "$1"
        break
        ;;
    *)
        if [[ ! "$1" =~ ^[0-9]+$ ]]
        then
            error_msg="Invalid exit code[$1]: expected a non-negative integer"
            is_help=true
            break
        fi
        code=$1
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
Terminate the current remote session shell (builtin exit).  Refuses to exit
when BU_REMOTE_SESSION is unset, so it can never end the wrong shell.  The
optional CODE (a non-negative integer) becomes enter-remote-session's return
value on the calling side.
" \
        --example "Exit the session" "" \
        --example "Exit with a specific code" "7"
    return 0
fi

# Refuse outside a session before terminating the shell — --help above still
# works, but an actual exit must never end the wrong shell.
if [[ -z "${BU_REMOTE_SESSION:-}" ]]
then
    bu_log_err "Not inside a remote session (BU_REMOTE_SESSION is unset); refusing to exit this shell"
    return 1
fi

bu_log_info "Exiting remote session[$BU_REMOTE_SESSION] (origin: ${BU_REMOTE_SESSION_ORIGIN:-unknown})"

builtin exit "$code"
}

__bu_bu_exit_remote_session_main "$@"
