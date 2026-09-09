#!/usr/bin/env bash
# Pipeline: standalone
# Dispatch: source
# Synopsis: Execute a command and cache its output
function __bu_bu_invoke_cached_command_main()
{
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

# Note that we do not source bu_entrypoint inside the sourceable script template
# as it is assumed that sourceable scripts are sourced AFTER 
# bu_entrypoint has been sourced by the user.

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_scope_add_cleanup bu_popd_silent
bu_run_log_command "$@"

local bu_cached_execute_args=()

local is_help=false
local is_dry_run=false
local error_msg=
local options_finished=false
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --check)
        # Only check if the command is cached, do not execute it
        bu_cached_execute_args+=("$1")
        ;;
    --error-pattern)
        # Regular expression pattern to search for in the command output that indicates an error
        bu_parse_positional $# --hint regex
        bu_cached_execute_args+=("$1" "$2")
        ;;
    --allow-empty)
        # Do not treat empty output as an error
        bu_cached_execute_args+=("$1")
        ;;
    --env-vars)
        # Comma-separated list of environment variable names to include in the cache key
        bu_parse_positional $# --hint "var1,var2,var3"
        bu_cached_execute_args+=("$1" "$2")
        ;;
    --bash-vars)
        # Comma-separated list of bash variable names to include in the cache key
        bu_parse_positional $# --hint "var1,var2,var3"
        bu_cached_execute_args+=("$1" "$2")
        ;;
    --dir)
        # Directory to use for caching
        bu_parse_positional $# "${BU_AUTOCOMPLETE_SPEC_DIRECTORY[@]}"
        bu_cached_execute_args+=("$1" "$2")
        ;;
    --invalidate|--invalidate-cache)
        # Invalidate the cache for this command before executing
        bu_cached_execute_args+=("$1")
        ;;
    --invalidate-bool|--invalidate-cache-bool)
        # Boolean to control cache invalidation
        bu_parse_positional $# --enum true false enum--
        bu_cached_execute_args+=("$1" "$2")
        ;;
    --strict-equality)
        # Use strict equality (including command line) for cache hits
        bu_cached_execute_args+=("$1")
        ;;
    --dry-run|--what-if) # _FLAG
        is_dry_run=true
        ;;
    -h|--help)
        # Print help
        is_help=true
        ;;
    --)
        # Remaining options will be collected
        bu_cached_execute_args+=("$1")
        options_finished=true
        shift
        break
        ;;
    ''|-*)
        bu_parse_error_enum "$1"
        break
        ;;
    *)
        bu_spawn_args+=(--)
        options_finished=true
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
    bu_autocomplete_remaining +c --as-if "${remaining_options[@]}" as-if--
    return 0
fi

if "$is_help"
then
    bu_autohelp --description "Wrapper script around the bu_cached_execute function. Use the function directly in scripts for higher performance."
    return 0
fi

bu_cached_execute_args+=("${remaining_options[@]}")

bu_scope_pop_function

if "$is_dry_run"; then
    bu_log_info "Would execute cached: ${bu_cached_execute_args[*]}"
    return 0
fi

bu_cached_execute "${bu_cached_execute_args[@]}"
}

__bu_bu_invoke_cached_command_main "$@"
