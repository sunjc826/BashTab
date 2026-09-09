#!/usr/bin/env bash
# Pipeline: producer
# Dispatch: source
# Synopsis: Show battery status and charge level
function __bu_bu_get_battery_main()
{
# --is-compatible: magic flag checked by the framework at registration time.
# Exit 0 if this command can run on the current system, non-zero otherwise.
# stderr becomes the reason shown in `bu` help.
if [[ "$1" == "--is-compatible" ]]; then
    command -v jc &>/dev/null || { echo "jc is required" >&2; exit 1; }
    command -v upower &>/dev/null || { echo "upower is required" >&2; exit 1; }
    exit 0
fi
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local is_help=false
local format=auto
local show_all=false
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
    --all)# _FLAG
        # Show all power devices, not just batteries
        show_all=true
        ;;
    -h|--help)# _FLAG
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
        --description "Show battery status (upower, PowerShell Get-Battery analog). Desktops without batteries can use --all to see all power devices." \
        --example "Batteries only" "" \
        --example "All power devices" "--all"
    return 0
fi

if ! command -v jc &>/dev/null
then
    error_msg="jc is required. Install with: pip install jc"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

# Enumerate battery devices (or all power devices with --all)
local -a devices=()
if "$show_all"
then
    mapfile -t devices < <(upower -e 2>/dev/null)
else
    mapfile -t devices < <(upower -e 2>/dev/null | grep -i bat)
fi

local dev
{
    for dev in "${devices[@]}"
    do
        upower -i "$dev" 2>/dev/null
    done
} | jc --upower 2>/dev/null | jq -c 'if type == "array" then .[] else . end' 2>/dev/null | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_get_battery_main "$@"
