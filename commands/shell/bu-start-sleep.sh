#!/usr/bin/env bash
# Pipeline: standalone
# Dispatch: source
# Synopsis: Suspend execution for a specified duration
function __bu_bu_start_sleep_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local seconds=
local is_countdown=false
local is_help=false
local is_dry_run=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --countdown)# _FLAG
        # Show a per-second countdown on stderr while sleeping
        is_countdown=true
        ;;
    --dry-run|--what-if) # _FLAG
        is_dry_run=true
        ;;
    -h|--help)# _FLAG
        # Print help
        is_help=true
        ;;
    *)
        if [[ -z "$seconds" ]]
        then
            seconds=$1
        else
            bu_parse_error_enum "$1"
        fi
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
Sleep for a number of seconds (PowerShell Start-Sleep).
Accepts fractional seconds (0.5, 1.25). --countdown shows remaining time
on stderr each second, useful in scripts and demos.
" \
        --example "Two and a half seconds" "2.5" \
        --example "With countdown" "10 --countdown"
    return 0
fi

if [[ -z "$seconds" ]]
then
    error_msg="Missing required seconds (e.g. bu start-sleep 2.5)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

if [[ ! "$seconds" =~ ^[0-9]+([.][0-9]+)?$ ]]
then
    error_msg="Seconds must be a non-negative number, got[$seconds]"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

if "$is_dry_run"; then
    bu_log_info "Would sleep for $seconds seconds"
else
if "$is_countdown"
then
    # Count down in whole-second steps, then sleep off the remainder
    local remaining=$seconds
    while awk -v r="$remaining" 'BEGIN { exit !(r >= 1) }'
    do
        printf '\r\033[K%s remaining…' "$remaining" >&2
        sleep 1
        remaining=$(awk -v r="$remaining" 'BEGIN { print r - 1 }')
    done
    awk -v r="$remaining" 'BEGIN { exit !(r > 0) }' && sleep "$remaining"
    printf '\r\033[K' >&2
else
    sleep "$seconds"
fi

fi
bu_scope_pop_function
}

__bu_bu_start_sleep_main "$@"
