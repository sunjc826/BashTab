#!/usr/bin/env bash
# Pipeline: producer
# Dispatch: source
# Synopsis: List block devices
function __bu_bu_get_block_device_main()
{
# --is-compatible: magic flag checked by the framework at registration time.
# Exit 0 if this command can run on the current system, non-zero otherwise.
# stderr becomes the reason shown in `bu` help.
if [[ "$1" == "--is-compatible" ]]; then
    command -v jc &>/dev/null || { echo "jc is required" >&2; exit 1; }
    command -v lsblk &>/dev/null || { echo "lsblk is required" >&2; exit 1; }
    exit 0
fi
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local is_help=false
local format=auto
local output=
local is_paths=false
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
    -o|--output)# COLUMNS
        # Select output columns (e.g. NAME,SIZE,TYPE,MOUNTPOINT)
        bu_parse_positional $# --hint "Comma-separated columns"
        output=${!shift_by}
        ;;
    -p|--paths)# _FLAG
        # Print full device paths
        is_paths=true
        ;;
    -h|--help)# _FLAG
        is_help=true
        ;;
    --)
        # Remaining args are passed to the underlying command, replacing the default arguments
        shift
        break
        ;;
    *)
        # Any unrecognized arg: pass through to the underlying command, replacing the default arguments
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
        --description "List block devices (PowerShell Get-Disk / Get-PhysicalDisk analog). Wraps lsblk; extra arguments replace the default arguments." \
        --example "Default" "" \
        --example "Custom columns" "--output NAME,SIZE,TYPE,MOUNTPOINT" \
        --example "Full paths" "--paths" \
        --example "With arguments" "--fs"
    return 0
fi

if ! command -v jc &>/dev/null
then
    error_msg="jc is required. Install with: pip install jc"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

# Build the command: base command + provided args, otherwise base + default args
local -a cmd=(lsblk)
[[ -n "$output" ]] && cmd+=(-o "$output")
"$is_paths" && cmd+=(-p)
if ((${#remaining_options[@]} > 0)); then cmd+=("${remaining_options[@]}"); fi

"${cmd[@]}" 2>/dev/null | jc --lsblk 2>/dev/null | jq -c 'if type == "array" then .[] else . end' 2>/dev/null | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_get_block_device_main "$@"
