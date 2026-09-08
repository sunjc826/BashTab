#!/usr/bin/env bash
# Pipeline: producer
# Dispatch: source
# Synopsis: List mounted filesystems
# Fields: filesystem mount_point type options
function __bu_bu_get_mount_main()
{
# --is-compatible: magic flag checked by the framework at registration time.
# Exit 0 if this command can run on the current system, non-zero otherwise.
# stderr becomes the reason shown in `bu` help.
if [[ "$1" == "--is-compatible" ]]; then
    command -v jc &>/dev/null || { echo "jc is required" >&2; exit 1; }
    command -v mount &>/dev/null || { echo "mount is required" >&2; exit 1; }
    exit 0
fi
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local is_help=false
local format=auto
local type_filter=
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
    -t|--type)# TYPE
        # Filter by filesystem type (e.g. ext4, xfs, tmpfs, nfs)
        bu_parse_positional $# --hint "Filesystem type"
        type_filter=${!shift_by}
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
        --description "List mounted filesystems (jc mount parser wrapper)." \
        --example "All mounts" "" \
        --example "Filter by type" "--type ext4" \
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

# Build the command: use provided args if any, otherwise the default
local -a cmd=()
if [[ -n "$type_filter" ]] || ((${#remaining_options[@]} > 0))
then
    cmd=(mount)
    [[ -n "$type_filter" ]] && cmd+=(-t "$type_filter")
    ((${#remaining_options[@]} > 0)) && cmd+=("${remaining_options[@]}")
else
    cmd=(mount)
fi

"${cmd[@]}" 2>/dev/null | jc --mount 2>/dev/null | jq -c 'if type == "array" then .[] else . end' 2>/dev/null | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_get_mount_main "$@"
