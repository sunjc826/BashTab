#!/usr/bin/env bash
# Synopsis: TODO -- one line for the command catalog
function __bu_@BU_SCRIPT_NAME@_main()
{
# --is-compatible: magic flag checked by the framework at registration time.
# It must exit BEFORE any entrypoint sourcing: the framework probes with
# `bash <script> --is-compatible`, and sourcing bu_entrypoint here would run
# a full command scan that probes every gated command again — infinite
# recursion that hangs the probe until Ctrl-C.
# Exit 0 if this command can run on the current system, non-zero otherwise.
# stderr becomes the reason shown in `bu` help.
if [[ "$1" == "--is-compatible" ]]; then
    # Example checks (uncomment and customize):
    # command -v mytool &>/dev/null || { echo "mytool is required" >&2; exit 1; }
    exit 0
fi

set -e
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

local is_help=false
local error_msg=
local options_finished=false
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    -h|--help)
        # Print help
        is_help=true
        ;;
    --)
        # Remaining options will be collected
        options_finished=true
        shift
        break
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
local remaining_options=("$@")
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

bu_scope_pop_function
}

__bu_@BU_SCRIPT_NAME@_main "$@"
