#!/usr/bin/env bash
# Pipeline: standalone
function __bu_bu_run_example2_main()
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

local val1=
local val2=
local val3=
local is_help=false
local error_msg=
local options_finished=false
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    -a1|--arg1)
        bu_parse_positional $# :val1_1 :val1_2
        val1=${!shift_by}
        ;;
    -a2|--arg2)
        bu_parse_positional $# :val2_1 :val2_2
        val2=${!shift_by}
        bu_parse_positional $# :val3_1 :val3_2 :val3_3
        val3=${!shift_by}
        ;;
    --)
        # Remaining options will be collected
        options_finished=true
        shift
        break
        ;;
    -h|--help)
        # Print help
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
    bu_autohelp
    return 0
fi

echo "bu-run-example2: val1=${val1}, val2=${val2}, val3=${val3}"

bu_scope_pop_function
}

__bu_bu_run_example2_main "$@"
