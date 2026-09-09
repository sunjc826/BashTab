#!/usr/bin/env bash
# Pipeline: producer
# Dispatch: source
# Synopsis: Start (or adopt) a persistent ControlMaster session to a host
# Fields: host action socket master_pid
function __bu_bu_new_remote_session_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local -a specs=()
local persist=30
local format=auto
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --persist)# PERSIST
        # ControlPersist value (yes, a duration, or the 30-second default)
        bu_parse_positional $# --hint "ControlPersist value (e.g. yes, 4h, 30)"
        persist=${!shift_by}
        ;;
    --format)# FORMAT
        # Output format
        bu_parse_positional $# --enum "${BU_OUT_FORMATS[@]}" enum-- --hint "Output format"
        bu_validate_positional "${!shift_by}"
        format=${!shift_by}
        ;;
    -h|--help)# _FLAG
        # Print help
        is_help=true
        ;;
    -*)
        bu_parse_error_enum "$1"
        break
        ;;
    *)
        specs+=("$1")
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
Start a persistent ControlMaster session to one or more hosts, or adopt the
existing live master when one is already running.  The socket path is
bijective with the normalized spec, so get-remote-session can enumerate
sessions with no state store.

Output is structured: piped output defaults to JSONL, terminal output
defaults to a table. Use --format to override.
" \
        --example "Open a session" "web01" \
        --example "Open with a longer persist" "web01 --persist 4h" \
        --example "Render as a table" "web01 --format table"
    return 0
fi

if ((${#specs[@]} == 0))
then
    bu_log_err "At least one spec is required"
    bu_scope_pop_function
    return 1
fi

local dir
__bu_remote_ssh_dir
dir=$BU_RET
bu_mkdir "$dir"

local errfile
errfile=$(mktemp "$BU_TMP_DIR/bu_remote_session_err.XXXXXXXXXX")
bu_scope_add_cleanup rm -f "$errfile"

local rc=0
local pipe_rc
local spec normalized sock master_pid spawn_rc err_detail
{
    for spec in "${specs[@]}"
    do
        if ! bu_remote_spec_normalize "$spec"
        then
            rc=1
            continue
        fi
        normalized=$BU_RET
        if ! bu_remote_socket "$spec"
        then
            rc=1
            continue
        fi
        sock=$BU_RET

        if bu_remote_session_alive "$spec"
        then
            if __bu_remote_master_pid "$spec"
            then
                master_pid=$BU_RET
            else
                master_pid=
            fi
            bu_out_record "host=$normalized" action=reused "socket=$sock" "master_pid=$master_pid"
            continue
        fi

        # Stale socket from a dead master: clear before respawning.
        rm -f "$sock"

        # -fN daemonizes but INHERITS fds, so stdio must be pinned to /dev/null
        # (a piped stdout would keep downstream readers waiting for EOF forever);
        # stderr goes to a file so a failed spawn has a readable reason.
        ssh -o BatchMode=yes -o ControlMaster=yes -o "ControlPath=$sock" -o "ControlPersist=$persist" -fN "$normalized" \
            </dev/null >/dev/null 2>"$errfile"
        spawn_rc=$?

        if __bu_remote_master_pid "$spec"
        then
            master_pid=$BU_RET
        else
            master_pid=
        fi

        if [[ -n "$master_pid" ]]
        then
            bu_out_record "host=$normalized" action=created "socket=$sock" "master_pid=$master_pid"
        else
            err_detail=$(< "$errfile")
            bu_log_err "Failed to create remote session for $normalized: ${err_detail:-ssh exited with code $spawn_rc}"
            bu_out_record "host=$normalized" action=failed "socket=$sock" master_pid=
            rc=1
        fi
    done
    exit "$rc"
} | bu_out --format "$format"
pipe_rc=${PIPESTATUS[0]}

bu_scope_pop_function
return "$pipe_rc"
}

__bu_bu_new_remote_session_main "$@"
