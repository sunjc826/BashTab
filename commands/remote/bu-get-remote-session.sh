#!/usr/bin/env bash
# Pipeline: producer
# Dispatch: source
# Synopsis: List remote ControlMaster sessions and their status
# Tab-Execute: true
# Fields: host alive socket master_pid
function __bu_bu_get_remote_session_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local format=auto
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
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
    *)
        bu_parse_error_enum "$1"
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

if bu_env_is_in_autocomplete
then
    bu_autocomplete
    return 0
fi

if "$is_help"
then
    bu_autohelp \
        --description "
List remote ControlMaster sessions by enumerating the socket directory (no
state store): the spec is recovered from each cm-* filename (bijective by
construction) and each is checked with ssh -O check.  Dead sockets are still
listed with alive=false.

Output is structured: piped output defaults to JSONL, terminal output
defaults to a table. Use --format to override.
" \
        --example "List sessions" "" \
        --example "Render as a table" "--format table"
    return 0
fi

local dir
__bu_remote_ssh_dir
dir=$BU_RET

local sock spec master_pid alive
{
    for sock in "$dir"/cm-*
    do
        [[ -e "$sock" ]] || continue
        bu_basename "$sock"
        spec=${BU_RET#cm-}

        if bu_remote_session_alive "$spec"
        then
            alive=true
            if __bu_remote_master_pid "$spec"
            then
                master_pid=$BU_RET
            else
                master_pid=
            fi
        else
            alive=false
            master_pid=
        fi
        bu_out_record "host=$spec" "alive:=$alive" "socket=$sock" "master_pid=$master_pid"
    done
} | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_get_remote_session_main "$@"
