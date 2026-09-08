#!/usr/bin/env bash
# Pipeline: producer
# Dispatch: source
# Synopsis: List Docker containers
# Fields: ID Image Command CreatedAt RunningFor Ports State Status Size Names Labels Mounts Networks
function __bu_bu_get_docker_container_main()
{
# --is-compatible: magic flag checked by the framework at registration time.
# Exit 0 if this command can run on the current system, non-zero otherwise.
# stderr becomes the reason shown in `bu` help.
if [[ "$1" == "--is-compatible" ]]; then
    command -v docker &>/dev/null || { echo "docker is required" >&2; exit 1; }
    exit 0
fi
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local is_all=false
local is_quiet=false
local is_latest=false
local is_size=false
local filter=
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
    -f|--filter)# FILTER
        # Filter containers (e.g. status=running, name=web, ancestor=nginx)
        bu_parse_positional $# --hint "key=value filter"
        filter=${!shift_by}
        ;;
    -a|--all)# _FLAG
        # Show all containers (including stopped)
        is_all=true
        ;;
    -q|--quiet)# _FLAG
        # Only display container IDs
        is_quiet=true
        ;;
    -l|--latest)# _FLAG
        # Show the latest created container (including all states)
        is_latest=true
        ;;
    -s|--size)# _FLAG
        # Show total file sizes
        is_size=true
        ;;
    -h|--help)# _FLAG
        is_help=true
        ;;
    --)
        shift
        break
        ;;
    *)
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
        --description "
List Docker containers as JSONL records (docker ps --format json wrapper).

Fields: ID, Image, Command, CreatedAt, RunningFor, Ports, State, Status, Size, Names, Labels, Mounts, Networks
" \
        --example "Running containers" "" \
        --example "All containers" "--all" \
        --example "Filter by name" "--filter name=web" \
        --example "Filter by status" "--filter status=exited" \
        --example "Latest container" "--latest" \
        --example "Show names and ports" "| bu select Names,Ports,Status"
    return 0
fi

if ! command -v docker &>/dev/null
then
    error_msg="docker is required. Install from https://docs.docker.com/engine/install/"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

local -a docker_args=(ps --format json)
"$is_all" && docker_args+=(-a)
"$is_quiet" && docker_args+=(-q)
"$is_latest" && docker_args+=(-l)
"$is_size" && docker_args+=(-s)
[[ -n "$filter" ]] && docker_args+=(--filter "$filter")
if ((${#remaining_options[@]} > 0)); then docker_args+=("${remaining_options[@]}"); fi
${BU_CAP[docker,sudo]} docker "${docker_args[@]}" 2>/dev/null | bu_format_jsonl | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_get_docker_container_main "$@"
