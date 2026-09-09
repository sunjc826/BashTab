#!/usr/bin/env bash
# Pipeline: transform
# Requires-Any: Repository name image
# Fields: image action pulled error
# Dispatch: source
# Synopsis: Pull a Docker image from a registry
function __bu_bu_pull_docker_image_main()
{
set -e
# --is-compatible: magic flag checked by the framework at registration time.
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

local -a images=()
local is_all_tags=false
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
    --all-tags|-a)# _FLAG
        # Pull all tags of the image (docker pull -a)
        is_all_tags=true
        ;;
    --what-if)# _FLAG
        is_what_if=true
        ;;
    --format)# FORMAT
        bu_parse_positional $# --enum ${BU_OUT_FORMATS[@]} enum-- --hint "Output format"
        format=${!shift_by}
        ;;
    --image)# IMAGE
        # Image name (e.g. nginx:latest; repeatable)
        bu_parse_positional $# --hint "Image name (e.g. nginx:latest)"
        images+=("${!shift_by}")
        ;;
    -h|--help)# _FLAG
        is_help=true
        ;;
    *)
        images+=("$1")
        ;;
    esac
    if "$is_help"; then break; fi
    if (( $# < shift_by )); then bu_parse_error_argn "$1" $#; break; fi
    shift "$shift_by"
done
if bu_env_is_in_autocomplete; then bu_autocomplete; return 0; fi

if "$is_help"
then
    bu_autohelp \
        --description "
Pull Docker images from a registry (structured docker pull).
Emits one record per image: image, action, pulled (boolean); failures carry
an error field. Use --all-tags to pull all tags of a repository.
Requires docker to be installed.
" \
        --example "Pull latest" "nginx" \
        --example "Specific tag" "python:3.12-alpine" \
        --example "All tags" "nginx --all-tags" \
        --example "Dry run" "ubuntu:24.04 --what-if" \
        --example "Multiple images" "nginx redis:7-alpine" \
        --example "Pipeline input" ""
    return 0
fi

# Pipeline input: extract .Repository or .name
if ((${#images[@]} == 0)) && [[ ! -t 0 ]]
then
    local _img
    while IFS= read -r _img; do
        [[ -n "$_img" ]] && images+=("$_img")
    done < <(jq -r '.Repository // .name // .image // empty' 2>/dev/null)
fi

if ((${#images[@]} == 0))
then
    error_msg="Missing required image name (e.g. bu pull-docker-image nginx:latest)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

local -a docker_args=(pull)
"$is_all_tags" && docker_args+=(-a)

local records_file
records_file=$(mktemp)
bu_scope_add_cleanup rm -f "$records_file"

local rc=0
local image err
{
    for image in "${images[@]}"
    do
        if "$is_what_if"
        then
            bu_log_info "What if: docker ${docker_args[*]} $image"
            continue
        fi
        if err=$(${BU_CAP[docker,sudo]} docker "${docker_args[@]}" -- "$image" 2>&1)
        then
            bu_out_record image="$image" action=pull pulled:=true
        else
            bu_out_record image="$image" action=pull pulled:=false error="$err"
            rc=1
        fi
    done
} > "$records_file"

bu_out --format "$format" < "$records_file"

bu_scope_pop_function
return $rc
}

__bu_bu_pull_docker_image_main "$@"
