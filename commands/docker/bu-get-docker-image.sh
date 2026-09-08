#!/usr/bin/env bash
# Pipeline: producer
# Dispatch: source
# Synopsis: List Docker images
# Fields: ID Repository Tag CreatedAt CreatedSince Size
function __bu_bu_get_docker_image_main()
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
        # Filter images (e.g. dangling=true, reference=nginx*, before=IMAGE)
        bu_parse_positional $# --hint "key=value filter"
        filter=${!shift_by}
        ;;
    -a|--all)# _FLAG
        # Show all images (including intermediate)
        is_all=true
        ;;
    -q|--quiet)# _FLAG
        # Only display image IDs
        is_quiet=true
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
List Docker images as JSONL records (docker images --format json wrapper).

Fields: ID, Repository, Tag, CreatedAt, CreatedSince, Size
" \
        --example "All images" "" \
        --example "Dangling images" "--filter dangling=true" \
        --example "Filter by reference" "--filter reference=nginx*" \
        --example "Quiet mode" "--quiet"
    return 0
fi

if ! command -v docker &>/dev/null
then
    error_msg="docker is required."
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

local -a docker_args=(images --format json)
"$is_all" && docker_args+=(-a)
"$is_quiet" && docker_args+=(-q)
[[ -n "$filter" ]] && docker_args+=(--filter "$filter")
if ((${#remaining_options[@]} > 0)); then docker_args+=("${remaining_options[@]}"); fi
${BU_CAP[docker,sudo]} docker "${docker_args[@]}" 2>/dev/null | bu_format_jsonl | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_get_docker_image_main "$@"
