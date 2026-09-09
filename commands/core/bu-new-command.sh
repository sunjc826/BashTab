#!/usr/bin/env bash
# Pipeline: standalone
# Dispatch: source
# Synopsis: Create a new BashTab command from a template
# Help-Topic: commands
function __bu_bu_new_command_main()
{
set -e
# Considering how slow WSL1 is, let's optimize a bit here too
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

# This seems to be the most important optimization for WSL1, autocomplete is way more responsive
if [[ -z "$COMP_CWORD" ]]
then
source ../../bu_entrypoint.sh
fi
bu_exit_handler_setup
bu_scope_push_function
bu_scope_add_cleanup bu_popd_silent
bu_run_log_command "$@"

local dir=
local name=
local is_force=false
local is_source_only=false
local is_source_isolated=false
local is_directory_relevant=true
local is_help=false
local error_msg=
local options_finished=false
local autocompletion=()
local shift_by=
# bu_log_tty reached1
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    -d|--dir)# SCRIPT_DIR
        # Directory that the script should be placed in
        # It should be one of 
        # $(printf "  - ${BU_TPUT_BOLD}%s${BU_TPUT_RESET}\n" "${!BU_COMMAND_SEARCH_DIRS[@]}")
        bu_parse_positional $# --enum "${!BU_COMMAND_SEARCH_DIRS[@]}" enum--
        dir=${!shift_by}
        ;;
    -n|--name)# SCRIPT_NAME
        # Name of the script, can be given without the ${BU_TPUT_BOLD}.sh${BU_TPUT_RESET} suffix
        bu_parse_positional $# --hint "Name of the script (.sh suffix is optional)"
        name=${!shift_by}
        ;;
    -f|--force)# _FLAG
        # Overwrite any existing script at the same location
        is_force=true
        ;;
    --source)# _FLAG
        # Generate a source-type command that runs in the caller's shell and may
        # mutate it. Use ONLY when mutating the caller's shell is the command's
        # purpose; otherwise prefer --source-isolated.
        is_source_only=true
        ;;
    --source-isolated)# _FLAG
        # Generate a source-type command whose body runs in a subshell: it can
        # READ the caller's shell state but cannot mutate it (cd/export/PATH
        # edits die with the subshell).
        is_source_isolated=true
        ;;
    --no-chdir)# _FLAG
        # If given, the template used for the script will not automatically enter the script's directory.
        is_directory_relevant=false
        ;;
    -h|--help)# _FLAG
        # Print help
        is_help=true
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
        bu_parse_error_argn "$1"
        break
    fi
    shift "$shift_by"
done
local remaining_options=("$@")
if bu_env_is_in_autocomplete
then
    # bu_log_tty reached2
    bu_autocomplete
    return 0
fi

if "$is_help"
then
    local search_dirs=("${!BU_COMMAND_SEARCH_DIRS[@]}")
    bu_autohelp \
        --description "
Create a BashTab compatible \
(can be used with ${BU_TPUT_BOLD}${BU_CLI_COMMAND_NAME}${BU_TPUT_RESET}) \
script using a template
" \
        --example \
        "Generate an executable script called ${BU_TPUT_BOLD}my_script.sh${BU_TPUT_RESET} in ${BU_TPUT_BOLD}${search_dirs}${BU_TPUT_RESET}" \
        "--dir ${search_dirs} --name my_script" \
        --example \
        "Generate a source-able script called ${BU_TPUT_BOLD}my_sourceable_script.sh${BU_TPUT_RESET} in ${BU_TPUT_BOLD}${search_dirs}${BU_TPUT_RESET} (mutates the caller's shell)" \
        "--dir ${search_dirs} --name my_sourceable_script --source" \
        --example \
        "Generate an isolated source-able script called ${BU_TPUT_BOLD}my_readonly_script.sh${BU_TPUT_RESET} in ${BU_TPUT_BOLD}${search_dirs}${BU_TPUT_RESET} (reads the caller's shell, cannot mutate it)" \
        "--dir ${search_dirs} --name my_readonly_script --source-isolated" \
        --example \
        "Overwrite an existing script called ${BU_TPUT_BOLD}my_script.sh${BU_TPUT_RESET} in ${BU_TPUT_BOLD}${search_dirs}${BU_TPUT_RESET}" \
        "--dir ${search_dirs} --name my_script --force" \

    return 0
fi

name=${name%.sh}

if [[ -z "$name" ]]
then
    bu_assert_err '--name not provided'
fi

if [[ -z "$dir" ]]
then
    bu_assert_err '--dir not provided'
fi

local target=
local template=
target=$dir/$name.sh
if "$is_source_isolated"
then
    if "$is_directory_relevant"
    then
        template=$BU_LIB_TEMPLATE_DIR/subshell_script_template.sh
    else
        template=$BU_LIB_TEMPLATE_DIR/subshell_script_template_nodir.sh
    fi
elif "$is_source_only"
then
    if "$is_directory_relevant"
    then
        template=$BU_LIB_TEMPLATE_DIR/source_script_template.sh
    else
        template=$BU_LIB_TEMPLATE_DIR/source_script_template_nodir.sh
    fi
else
    if "$is_directory_relevant"
    then
        template=$BU_LIB_TEMPLATE_DIR/script_template.sh
    else
        bu_assert_err "Currently not supported (It doesn't hurt too much to pushd, since we're already forking a new bash process)"
    fi
fi


mkdir -p "$dir"

if [[ ! -e "$dir"/__bu_entrypoint_decl.sh ]]
then
    bu_gen_substitute BU_DIR <"$BU_LIB_TEMPLATE_DIR"/bu_entrypoint_decl_template.sh >"$dir"/__bu_entrypoint_decl.sh
fi

if [[ -e "$target" ]]
then
    if ! "$is_force"
    then
        bu_assert_err "$target already exists"
    else
        rm -vf "$target"
    fi
fi

touch "$target"

if ! "$is_source_only" && ! "$is_source_isolated"
then
    chmod +x "$target"
else
    chmod -x "$target"
fi

(
    # shellcheck disable=SC2034
    BU_SCRIPT_NAME=$(tr -- -: __ <<<"${name,,}")
    bu_gen_substitute BU_SCRIPT_NAME <"$template" >"$target"
)

bu_edit_file "$target" || true

bu_scope_pop_function
}

__bu_bu_new_command_main "$@"
