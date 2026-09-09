#!/usr/bin/env bash
# Pipeline: transform
# Requires-Any: Names ID name id
# Fields: container action stopped error
# Dispatch: source
# Synopsis: Stop a running Docker container
# Completion helper: running container names from docker ps.
__bu_bu_stop_docker_container_complete_containers()
{
    BU_RET=()
    local c
    while IFS= read -r c
    do
        [[ -n "$c" ]] && BU_RET+=("$c")
    done < <( ${BU_CAP[docker,sudo]} docker ps --format '{{.Names}}' 2>/dev/null )
}

function __bu_bu_stop_docker_container_main()
{
set -e
# --is-compatible: magic flag checked by the framework at registration time.
# Exit 0 if this command can run on the current system, non-zero otherwise.
# stderr becomes the reason shown in `bu` help.
if [[ "$1" == "--is-compatible" ]]; then
    command -v docker &>/dev/null || { echo "docker is required" >&2; exit 1; }
    exit 0
fi
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

local -a containers=()
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
    --what-if)# _FLAG
        # Show what would happen without changing anything
        is_what_if=true
        ;;
    --format)# FORMAT
        # Output format
        bu_parse_positional $# --enum ${BU_OUT_FORMATS[@]} enum-- --hint "Output format"
        format=${!shift_by}
        ;;
    --container)# CONTAINER
        # Container name or ID (repeatable; also accepts pipeline input by structural typing)
        bu_parse_positional $# --ret __bu_bu_stop_docker_container_complete_containers ret-- --hint "Container name or ID"
        containers+=("${!shift_by}")
        ;;
    -h|--help)# _FLAG
        # Print help
        is_help=true
        ;;
    *)
        if bu_env_is_in_autocomplete
        then
            # Container positional: complete from live running container names
            autocompletion=(--ret __bu_bu_stop_docker_container_complete_containers ret-- --hint "Container name or ID")
        fi
        containers+=("$1")
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
Stop Docker containers (PowerShell Stop-DockerContainer analog, structured docker stop).
Emits one record per container: container, action, stopped (boolean); failures carry
an error field. Requires docker to be installed and running.
" \
        --example "One container" "my-container" \
        --example "Multiple containers" "web db redis" \
        --example "Named flag" "--container my-container" \
        --example "Dry run" "my-container --what-if" \
        --example "Pipeline input (e.g. from get-docker-container)" ""
    return 0
fi

# Pipeline input: when no container names are given as arguments and stdin is a pipe,
# read JSONL records and extract .Names (or .ID, .name, .id) via structural typing.
if ((${#containers[@]} == 0)) && [[ ! -t 0 ]]
then
    local _c
    while IFS= read -r _c
    do
        [[ -n "$_c" ]] && containers+=("$_c")
    done < <(jq -r '.Names // .ID // .name // .id // empty' 2>/dev/null)
fi

if ((${#containers[@]} == 0))
then
    error_msg="Missing required container name or ID (e.g. bu stop-docker-container my-container)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

# Records go to a temp file (not a pipeline) so the loop runs in the current
# shell and the per-container failure status survives in rc.
local records_file
records_file=$(mktemp)
bu_scope_add_cleanup rm -f "$records_file"

local rc=0
local container err
{
    for container in "${containers[@]}"
    do
        if "$is_what_if"
        then
            bu_log_info "What if: docker stop $container"
            continue
        fi
        if err=$(${BU_CAP[docker,sudo]} docker stop -- "$container" 2>&1)
        then
            bu_out_record container="$container" action=stop stopped:=true
        else
            bu_out_record container="$container" action=stop stopped:=false error="$err"
            rc=1
        fi
    done
} > "$records_file"

bu_out --format "$format" < "$records_file"

bu_scope_pop_function
return $rc
}

__bu_bu_stop_docker_container_main "$@"
