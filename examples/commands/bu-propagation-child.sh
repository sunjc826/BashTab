#!/usr/bin/env bash
# Pipeline: standalone
# Demo: child command for --as-if propagation test.
#
# This command's options should inherit the parent's --ansi YELLOW
# and --hint text when called via --as-if, but currently they don't.
#
# Usage (standalone):
#   bu propagation-child --mode <TAB>     ← no color (expected, no --ansi here)
#   bu propagation-child --target <TAB>   ← shows dev, staging, prod
function __bu_bu_propagation_child_main()
{
set -e
local -r invocation_dir=$PWD
local script_name script_dir
case "$BASH_SOURCE" in
*/*) script_name=${BASH_SOURCE##*/}; script_dir=${BASH_SOURCE%/*} ;;
*)   script_name=$BASH_SOURCE;          script_dir=. ;;
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

local mode=
local target=
local is_help=false
local error_msg=
local options_finished=false
local autocompletion=()
local shift_by=

while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    -m|--mode)
        # Should appear yellow when called from parent
        bu_parse_positional $# --enum fast slow dry-run enum-- --hint "Execution mode"
        mode=${!shift_by}
        ;;
    -t|--target)
        # Should appear yellow when called from parent
        bu_parse_positional $# --enum dev staging prod enum-- --hint "Target environment"
        target=${!shift_by}
        ;;
    --verbose)
        bu_parse_positional $# --hint "Verbosity level"
        ;;
    -h|--help)
        is_help=true
        ;;
    *)
        bu_parse_error_enum "$1"
        break
        ;;
    esac
    if (( $# < shift_by )); then
        bu_parse_error_argn "$1" $#
        break
    fi
    shift "$shift_by"
done

local remaining_options=("$@")
if bu_env_is_in_autocomplete; then
    bu_autocomplete
    return 0
fi
if "$is_help"; then
    bu_autohelp --description 'Demo: --as-if color/hint propagation (child)'
    return 0
fi
echo "[child] mode=$mode target=$target"
bu_scope_pop_function
}

__bu_bu_propagation_child_main "$@"
