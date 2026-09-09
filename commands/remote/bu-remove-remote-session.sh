#!/usr/bin/env bash
# Pipeline: producer
# Dispatch: source
# Synopsis: Close (or clean up) a remote ControlMaster session
# Fields: host action socket
function __bu_bu_remove_remote_session_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local -a specs=()
local all=false
local format=auto
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --all)# _FLAG
        # Remove every session in the socket directory
        all=true
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
Close a remote ControlMaster session (ssh -O exit), or clean up a stale
socket when the master is already gone.  WARNING: a live master may be the
only remaining route to a host if the credentials that opened it are gone —
closing it can strand you.

Output is structured: piped output defaults to JSONL, terminal output
defaults to a table. Use --format to override.
" \
        --example "Close a session" "host1" \
        --example "Render as a table" "host1 --format table"
    return 0
fi

if ! "$all" && ((${#specs[@]} == 0))
then
    bu_log_err "Provide at least one spec or --all"
    bu_scope_pop_function
    return 1
fi

local rc=0
local pipe_rc
{
    if "$all"
    then
        local dir
        __bu_remote_ssh_dir
        dir=$BU_RET
        local sock spec
        for sock in "$dir"/cm-*
        do
            [[ -e "$sock" ]] || continue
            bu_basename "$sock"
            spec=${BU_RET#cm-}
            __bu_remote_remove_spec "$spec" || rc=1
        done
    else
        local spec
        for spec in "${specs[@]}"
        do
            __bu_remote_remove_spec "$spec" || rc=1
        done
    fi
    exit "$rc"
} | bu_out --format "$format"
pipe_rc=${PIPESTATUS[0]}

bu_scope_pop_function
return "$pipe_rc"
}

__bu_bu_remove_remote_session_main "$@"
