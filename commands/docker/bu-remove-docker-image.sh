#!/usr/bin/env bash
# Pipeline: transform
# Requires-Any: Repository ID name id
# Fields: image action removed error
# Dispatch: source
# Synopsis: Remove a Docker image
# Completion helper: image names from docker images.
__bu_bu_remove_docker_image_complete_images()
{
    BU_RET=()
    local img
    while IFS= read -r img
    do
        [[ -n "$img" ]] && BU_RET+=("$img")
    done < <( ${BU_CAP[docker,sudo]} docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null )
}

function __bu_bu_remove_docker_image_main()
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
local is_force=false
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
    --force|-f)# _FLAG
        # Force removal (docker rmi -f)
        is_force=true
        ;;
    --what-if)# _FLAG
        is_what_if=true
        ;;
    --format)# FORMAT
        bu_parse_positional $# --enum ${BU_OUT_FORMATS[@]} enum-- --hint "Output format"
        format=${!shift_by}
        ;;
    --image)# IMAGE
        # Image name or ID (repeatable; also accepts pipeline input)
        bu_parse_positional $# --ret __bu_bu_remove_docker_image_complete_images ret-- --hint "Image name or ID"
        images+=("${!shift_by}")
        ;;
    -h|--help)# _FLAG
        is_help=true
        ;;
    *)
        if bu_env_is_in_autocomplete
        then
            autocompletion=(--ret __bu_bu_remove_docker_image_complete_images ret-- --hint "Image name or ID")
        fi
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
Remove Docker images (structured docker rmi).
Emits one record per image: image, action, removed (boolean); failures carry
an error field. Use --force to force removal of images with dependent containers.
Requires docker to be installed.
" \
        --example "One image" "nginx:latest" \
        --example "By ID" "abc123def456" \
        --example "Force remove" "old-image --force" \
        --example "Dry run" "unused-image --what-if" \
        --example "Pipeline input (e.g. from get-docker-image)" ""
    return 0
fi

# Pipeline input: extract .Repository (or .ID, .name, .id)
if ((${#images[@]} == 0)) && [[ ! -t 0 ]]
then
    local _img
    while IFS= read -r _img; do
        [[ -n "$_img" ]] && images+=("$_img")
    done < <(jq -r '.Repository // .ID // .name // .id // empty' 2>/dev/null)
fi

if ((${#images[@]} == 0))
then
    error_msg="Missing required image name or ID (e.g. bu remove-docker-image nginx:latest)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

local -a docker_args=(rmi)
"$is_force" && docker_args+=(-f)

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
            bu_out_record image="$image" action=remove removed:=true
        else
            bu_out_record image="$image" action=remove removed:=false error="$err"
            rc=1
        fi
    done
} > "$records_file"

bu_out --format "$format" < "$records_file"

bu_scope_pop_function
return $rc
}

__bu_bu_remove_docker_image_main "$@"
