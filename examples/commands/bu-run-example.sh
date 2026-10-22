#!/usr/bin/env bash
# Pipeline: standalone
function __bu_bu_run_example_main()
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
bu import-environment --command-dir "$BU_DIR"/examples/commands --namespace-style prefix
fi

bu_exit_handler_setup
bu_scope_push_function
bu_scope_add_cleanup bu_popd_silent
bu_run_log_command "$@"

local name=
local age=
local food_type=
local fruit=
local vegetable=
local meat_type=
local meat=
local gaming_platform=
local gaming_genre=
local more_details=$BU_NULL
local run_example2_args=("$BU_NULL")
local is_help=false
local error_msg=
local options_finished=false
local autocompletion=()
local shift_by=

function __bu_example_print_fruits()
{
    echo apple
    echo orange
    echo pineapple
    echo watermelon
}

function __bu_example_get_vegetables()
{
    BU_RET=(
        spinach
        carrot
    )
}

function __bu_example_get_meat()
{
    local meat_type=$1
    case "$meat_type" in
    '') ;;
    red) BU_RET=(pork beef) ;;
    white) BU_RET=(fish chicken) ;;
    esac
}

# Subparser demo
function __bu_example_parse_games()
{
    while (($#))
    do
        bu_parse_multiselect
        case "$1" in
        --platform)
            bu_parse_positional $# :Windows :Linux :Mac :FreeBSD
            gaming_platform=${!shift_by}
            ;;
        --genre)
            bu_parse_positional $# --enum horror adventure action strategy enum--
            gaming_genre=${!shift_by}
            ;;
        /) 
            # terminates the parse loop
            shift
            break
            ;;
        *)
            bu_parse_error_enum "$1"
            ;;
        esac
        if (( $# < shift_by ))
        then
            bu_parse_error_argn "$1" $#
            break
        fi
        shift "$shift_by"
    done
}

while (($#))
do
    if [[ -z "$name" ]]
    then
        bu_parse_positional $# --hint 'Input your name or --help'
        name=${!shift_by}
        if [[ "$name" = --help ]]; then is_help=true; break; fi
        bu_parse_positional $# --hint 'Input your age or --help'
        age=${!shift_by}
        if [[ "$age" = --help ]]; then is_help=true; break; fi
    else
        bu_parse_multiselect $# "$1"
        case "$1" in
        -ff|--favorite-food)
            # Favorite food of ${name:-the user}
            bu_parse_positional $# --enum fruit vegetable meat enum--
            food_type=${!shift_by}
            case "$food_type" in
            fruit)
                bu_parse_positional $# --stdout __bu_example_print_fruits stdout--
                fruit=${!shift_by}
                ;;
            vegetable)
                bu_parse_positional $# --ret __bu_example_get_vegetables
                vegetable=${!shift_by}
                ;;
            meat)
                bu_parse_positional $# --enum red white enum--
                meat_type=${!shift_by}
                bu_parse_positional $# --ret __bu_example_get_meat "$meat_type" ret--
                meat=${!shift_by}
                ;;
            esac
            ;;
        -g|--games)
            bu_parse_nested __bu_example_parse_games "$@"
            ;;
        --details)
            bu_parse_positional $# --hint 'More about me'
            more_details=${!shift_by}
            ;;
        --run-example2)
            # "Recursive" call into bu-run-example2
            bu_parse_command_context "$@"
            run_example2_args=("${BU_RET[@]}")
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
    bu_autohelp --description 'Example command to showcase autocomplete and parsing utilities' \
    --example 'John of age 12 likes fish' 'John 12 --favorite-food meat white fish --details "I like fish" --run-example2 -a1 val1_1 run-example2--' 
    return 0
fi

cat <<EOF
Got arguments
Name=${name}
Age=${age}
Favorite food type=${food_type}
EOF

case "$food_type" in
fruit)
    echo "Fruit=${fruit}"
    ;;
vegetable)
    echo "Vegetable=${vegetable}"
    ;;
meat)
cat <<EOF
Meat type=${meat_type}
Meat=${meat}
EOF
    ;;
esac

if bu_is_not_null "$more_details"
then
echo "Details=${more_details}"
fi

if bu_is_not_null "$run_example2_args"
then
    bu run-example2 "${run_example2_args[@]}"
fi

bu_scope_pop_function
}

__bu_bu_run_example_main "$@"
