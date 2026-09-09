#!/usr/bin/env bash
# Pipeline: standalone
# Dispatch: source
# Synopsis: Clear the BashTab command and compatibility cache
# Help-Topic: modules
function __bu_bu_clear_cache_main()
{
# --is-compatible: no external dependencies
if [[ "$1" == "--is-compatible" ]]; then
    exit 0
fi

local -r invocation_dir=$PWD
local script_name script_dir
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

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_scope_add_cleanup bu_popd_silent
bu_run_log_command "$@"

local key=
local is_all=false
local is_dry_run=false
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --all)# _FLAG
        # Invalidate all project caches
        is_all=true
        ;;
    --dry-run|--what-if)# _FLAG
        is_dry_run=true
        ;;
    -h|--help)# _FLAG
        # Print help
        is_help=true
        ;;
    *)
        if [[ -z "$key" ]]; then
            key=$1
        else
            bu_parse_error_enum "$1"
            break
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
    bu_autohelp
    return 0
fi

if "$is_dry_run"; then
    if "$is_all"; then
        bu_log_info "Would invalidate all command caches"
    elif [[ -n "$key" ]]; then
        bu_log_info "Would invalidate cache for: $key"
    fi
elif "$is_all"; then
    __bu_invalidate_command_cache --all
elif [[ -n "$key" ]]; then
    __bu_invalidate_command_cache "$key"
else
    bu_log_err "Specify a project key or --all"
    return 1
fi

bu_scope_pop_function
}

__bu_bu_clear_cache_main "$@"
