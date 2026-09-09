#!/usr/bin/env bash
# Pipeline: standalone
# Dispatch: source
# Synopsis: Spawn a background process and track its status
function __bu_bu_invoke_spawn_command_main()
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

local bu_spawn_args=()

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
    --split)
        # Split mode: none, vertical, horizontal
        bu_parse_positional $# --enum none vertical horizontal enum--
        bu_spawn_args+=("$1" "$2")
        ;;
    --split-opposite)
        # Split opposite mode: none, vertical, horizontal
        bu_parse_positional $# --enum none vertical horizontal enum--
        bu_spawn_args+=("$1" "$2")
        ;;
    --joinable)
        # Make the spawned command joinable
        bu_spawn_args+=("$1")
        ;;
    --scoped)
        # Make the spawned command scoped
        bu_spawn_args+=("$1")
        ;;
    --delete-pane)
        # Delete the pane after the command finishes
        bu_spawn_args+=("$1")
        ;;
    --wait)
        # Wait for the spawned command to finish
        bu_spawn_args+=("$1")
        ;;
    --command)
        # Spawn a command
        bu_spawn_args+=("$1")
        ;;
    --function)
        # Spawn a function
        bu_spawn_args+=("$1")
        ;;
    --no-bashrc)
        # Do not source bashrc
        bu_spawn_args+=("$1")
        ;;
    --repl)
        # REPL mode (send Ctrl-D to exit)
        bu_spawn_args+=("$1")
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
        bu_spawn_args+=("$1")
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
    bu_autohelp --description "Wrapper script around the bu_spawn function. Use the function directly in scripts for higher performance."
    return 0
fi

bu_spawn_args+=("${remaining_options[@]}")

bu_scope_pop_function

if "$is_dry_run"; then
    bu_log_info "Would spawn: ${bu_spawn_args[*]}"
    return 0
fi

bu_spawn "${bu_spawn_args[@]}"
}

__bu_bu_invoke_spawn_command_main "$@"
