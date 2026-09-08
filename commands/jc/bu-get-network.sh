#!/usr/bin/env bash
# Pipeline: producer
# Dispatch: source
# Synopsis: Show network connection summary
# Fields: proto recv_q send_q local_address foreign_address state program_name kind local_port foreign_port transport_protocol network_protocol local_port_num
function __bu_bu_get_network_main()
{
# --is-compatible: magic flag checked by the framework at registration time.
# Exit 0 if this command can run on the current system, non-zero otherwise.
# stderr becomes the reason shown in `bu` help.
if [[ "$1" == "--is-compatible" ]]; then
    command -v jc &>/dev/null || { echo "jc is required" >&2; exit 1; }
    command -v netstat &>/dev/null || { echo "netstat is required" >&2; exit 1; }
    exit 0
fi
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local is_help=false
local format=auto
local is_tcp=false
local is_udp=false
local is_listening=false
local is_all=false
local is_numeric=false
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
    --tcp)# _FLAG
        # Show TCP connections only (-t)
        is_tcp=true
        ;;
    --udp)# _FLAG
        # Show UDP connections only (-u)
        is_udp=true
        ;;
    -l|--listening)# _FLAG
        # Show only listening sockets (-l)
        is_listening=true
        ;;
    -a|--all)# _FLAG
        # Show both listening and non-listening sockets (-a)
        is_all=true
        ;;
    -n|--numeric)# _FLAG
        # Show numeric addresses instead of resolving hosts (-n)
        is_numeric=true
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
        --description "Show network connections (jc netstat parser wrapper)." \
        --example "TCP listeners (default)" "" \
        --example "All connections" "--all --numeric" \
        --example "UDP only" "--udp --listening" \
        --example "TCP, all states" "--tcp --all" \
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

# Build the command: use explicit flags when provided, otherwise default
local -a cmd=()
if "$is_tcp" || "$is_udp" || "$is_listening" || "$is_all" || "$is_numeric" || ((${#remaining_options[@]} > 0))
then
    cmd=(netstat)
    "$is_tcp" && cmd+=(-t)
    "$is_udp" && cmd+=(-u)
    "$is_listening" && cmd+=(-l)
    "$is_all" && cmd+=(-a)
    "$is_numeric" && cmd+=(-n)
    # Default to -p for process info unless user provided custom args
    if ((${#remaining_options[@]} > 0)); then cmd+=("${remaining_options[@]}"); else cmd+=(-p); fi
else
    cmd=(netstat -tlnp)
fi

"${cmd[@]}" 2>/dev/null | jc --netstat 2>/dev/null | jq -c 'if type == "array" then .[] else . end' 2>/dev/null | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_get_network_main "$@"
