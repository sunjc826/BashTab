#!/usr/bin/env bash
# Pipeline: standalone
# Demo: --as-if color and hint propagation.
#
# The parent delegates completions for --child to `bu propagation-child`
# via --as-if, passing --ansi YELLOW.  The child should inherit the
# color and hint, but currently they are lost at the --as-if boundary.
#
# Usage:
#   bu propagation-parent --child --<TAB>   ← child options should be yellow, but aren't
#   bu propagation-parent --local <TAB>     ← these ARE yellow (baseline)
function __bu_bu_propagation_parent_main()
{
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
    script_name=$BASH_SOURCE;
    script_dir=.
    ;;
esac
pushd "$script_dir" &>/dev/null
script_dir=$PWD

if [[ -z "$COMP_CWORD" ]]; then
    # shellcheck source=./__bu_entrypoint_decl.sh
    source "$BU_DIR"/bu_entrypoint.sh
    bu import-environment --command-dir "$BU_DIR"/examples/commands --namespace-style prefix
fi

bu_exit_handler_setup
bu_scope_push_function
bu_scope_add_cleanup bu_popd_silent
bu_run_log_command "$@"

local child_mode=false
local child_args=()
local is_help=false
local error_msg=
local options_finished=false
local autocompletion=()
local shift_by=

while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --propagation-child)
        # Delegate completions to bu propagation-child.
        # The --ansi YELLOW should cascade, but currently doesn't.
        child_mode=true
        bu_parse_command_context "$@"
        child_args=("${BU_RET[@]}")
        ;;
    --local)
        # Baseline: these options ARE colored yellow.
        bu_parse_positional $# -a "$BU_TPUT_VSCODE_YELLOW" \
            --enum local-opt-1 local-opt-2 enum--
        ;;
    -h|--help)
        is_help=true
        ;;
    *)
        bu_parse_error_enum "$1"
        break
        ;;
    esac
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
    bu_autohelp --description 'Demo: --as-if color/hint propagation (parent)'
    return 0
fi
echo "[parent] child_mode=$child_mode"
bu_scope_pop_function
}

__bu_bu_propagation_parent_main "$@"
