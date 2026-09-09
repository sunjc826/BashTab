#!/usr/bin/env bash
# Pipeline: standalone
# Dispatch: source
# Synopsis: Source environment variables from a file
# Help-Topic: environment
function __bu_bu_import_environment_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local namespace_style=
local command_dirs=()
local is_non_recursive=false
local is_git_pull=false
local is_reset_source=false
local is_reset_vars=false
local is_reset_module_path=false
local is_init=true
local is_force=false
local is_help=false
local error_msg=
local options_finished=false
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    -c|--command-dir)# COMMAND_DIR
        # Directory to add to the command search dirs, currently ${BU_COMMAND_SEARCH_DIRS[*]} 
        bu_parse_positional $# "${BU_AUTOCOMPLETE_SPEC_DIRECTORY[@]}"
        command_dirs+=("${!shift_by}")
        ;;
    -ns|--namespace-style)# NS_STYLE
        # One of ${BU_ENUM_NAMESPACE_STYLE[*]}. Default is empty, which has the same behavior as an explicit none.
        # - none: No namespace in command
        # - prefix-keep: Synonym to none
        # - powershell-keep: Synonym to none
        # - prefix: Assumes that scripts in the command dirs are of the form namespace-verb-noun.sh 
        #           and the user wants to not type out the namespace.
        #           This will strip out the 'namespace-' and '.sh' portion, so to invoke it, run '${BU_CLI_COMMAND_NAME} verb-noun'
        # - powershell: Script naming style is verb-namespace-noun.sh (i.e. PowerShell style),
        #               in this case this option isn't needed.
        bu_parse_positional $# --enum "${BU_ENUM_NAMESPACE_STYLE[@]}" enum--
        bu_validate_positional "${!shift_by}"
        namespace_style=${!shift_by}
        ;;
    -nr|--non-recursive)# _FLAG
        # Only scan the top level of the command directory (no subdirectories).
        # Subdirectories can serve as utility libraries that don't become commands.
        is_non_recursive=true
        ;;
    -p|--pull)# _FLAG
        # Pull from the git repo, works when using BashTab from a submodule too
        # Currently, the activated version of BashTab is at BU_DIR[$BU_DIR]
        is_git_pull=true
        ;;
    +i|--no-init)# _FLAG
        # An optimization if import-environment is to be called successively
        is_init=false;
        ;;
    -f|--force)# _FLAG
        # Forcefully source all files.
        # Note that despite its name, this option does not git pull --force, you need to do that manually if needed.
        is_force=true
        ;;
    --reset-all)# _FLAG
        # This is meant to be used by a top level script that wants to start from a (mostly) clean environment
        # You may want to choose individual resets to allow external helper modules to 'bleed into' the environment.
        is_reset_source=true
        is_reset_vars=true
        is_reset_module_path=true
        ;;
    --reset-leaky)# _FLAG
        # Allow BU_MODULE_LIST to leak into the current environment, otherwise reset everything else.
        is_reset_source=true
        is_reset_vars=true
        ;;
    --reset-source)# _FLAG
        # Does something similar to --force
        is_reset_source=true
        ;;
    --reset-vars)# _FLAG
        # Allow the variables in bu_core_vars.sh to be reset
        is_reset_vars=true
        ;;
    --reset-module-path)# _FLAG
        # Allow BU_MODULE_LIST to be reset, this will effectively de-register the other modules that are not part of this project.  
        is_reset_module_path=true
        ;;
    -h|--help)# _FLAG
        # Print help
        is_help=true
        ;;
    --)# _FLAG
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
    bu_autohelp --description "
Modifies the 'bu' environment. Optionally, syncs with the upstream git repo.
    " \
    --example \
    "Refresh some dynamic variables, e.g. after editing $BU_DIR/config/bu_config_dynamic.sh" \
    ""   \
    --example \
    "Reload a possibly broken (for whatever reason) environment" \
    "--force"
    return 0
fi

local opt_command_mapper=()
if [[ -n "$namespace_style" ]]
then
    opt_command_mapper=(bu_convert_file_to_command_namespace "$namespace_style")
fi
local command_dir
for command_dir in "${command_dirs[@]}"
do
    bu_preinit_register_user_defined_subcommand_dir "$command_dir" "${opt_command_mapper[@]}"
    if "$is_non_recursive"; then
        bu_realpath "$command_dir"
        BU_COMMAND_SEARCH_DIR_RECURSIVE[$BU_RET]=false
    fi
done

if "$is_git_pull"
then
    pushd "$BU_DIR" &>/dev/null
    local current_branch=$(git branch --show-current)
    if [[ -n "$current_branch" ]]
    then
        bu_run --no-log-last-run-cmd git pull --ff-only
    else
        # detached HEAD, could be a submodule
        local superproject=$(git rev-parse --show-superproject-working-tree)
        if [[ -n "$superproject" ]]
        then
            bu_basename "$BU_DIR"
            local bu_submodule_dir_basename=$BU_RET
            cd ..
            bu_run --no-log-last-run-cmd git submodule update --remote ./"$bu_submodule_dir_basename"
        else
            bu_log_err "Cannot detect current branch, or if we are in a submodule, unable to update"
        fi
    fi

    popd &>/dev/null
fi

local opt_force=()
if "$is_force"
then
    opt_force=(--__bu-force)
fi

if "$is_reset_source"
then
    bu_log_info "Resetting source once cache"
    declare -A -g BU_SOURCE_ONCE_CACHE=()
fi

if "$is_reset_vars"
then
    bu_log_info "Resetting BU_CORE_VAR_SOURCED"
    unset -v BU_CORE_VAR_SOURCED
fi

if "$is_reset_module_path"
then
    bu_log_info "Resetting BU_MODULE_LIST"
    BU_MODULE_LIST=
fi

if "$is_init"
then
source "$BU_DIR"/bu_entrypoint.sh "${opt_force[@]}"
fi

bu_scope_pop_function
}

__bu_bu_import_environment_main "$@"
