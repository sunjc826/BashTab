#!/usr/bin/env bash
# Pipeline: producer
# Fields: action dry_run
# Dispatch: source
# Synopsis: Upgrade Arch Linux packages
function __bu_bu_update_pacman_package_main()
{
if [[ "$1" == "--is-compatible" ]]; then
    command -v pacman &>/dev/null || { echo "pacman is required" >&2; exit 1; }
    exit 0
fi
local -r invocation_dir=$PWD
source "$BU_NULL"
bu_scope_push_function
bu_run_log_command "$@"

local is_refresh=false
local is_yes=false
local is_dry_run=false
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#)); do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --refresh) # _FLAG
        is_refresh=true
        ;;
    -y|--yes) # _FLAG
        is_yes=true
        ;;
    --dry-run|--what-if) # _FLAG
        is_dry_run=true
        ;;
    -h|--help) # _FLAG
        is_help=true
        ;;
    *)
        break
        ;;
    esac
    if "$is_help"; then break; fi
    if (( $# < shift_by )); then bu_parse_error_argn "$1" $#; break; fi
    shift "$shift_by"
done
if bu_env_is_in_autocomplete; then bu_autocomplete; return 0; fi
if "$is_help"; then
    bu_autohelp --description "Upgrade Arch packages (pacman -Su).  Use --refresh to sync databases first (pacman -Syu)." \
        --example "Upgrade all" "" --example "Sync + upgrade" "--refresh"
    return 0
fi
if "$is_dry_run"; then
    bu_out_record action="would-upgrade" dry_run:=true | bu_out --format jsonl
else
    local -a cmd=(pacman -Su)
    "$is_refresh" && cmd=(pacman -Syu)
    "$is_yes" && cmd+=(--noconfirm)
    "${cmd[@]}" 2>/dev/null || { error_msg="pacman upgrade failed (try with sudo?)"; bu_autohelp; bu_scope_pop_function; return 1; }
    bu_out_record action="upgraded" | bu_out --format jsonl
fi
bu_scope_pop_function
}
__bu_bu_update_pacman_package_main "$@"
