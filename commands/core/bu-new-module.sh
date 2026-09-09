#!/usr/bin/env bash
# Pipeline: standalone
# Dispatch: source
# Synopsis: Scaffold a new BashTab module
# Help-Topic: modules
function __bu_bu_new_module_main()
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
source "$BU_DIR"/bu_entrypoint.sh
fi
bu_exit_handler_setup
bu_scope_push_function
bu_scope_add_cleanup bu_popd_silent
bu_run_log_command "$@"

local name=
local dir=
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
    -n|--name)# MODULE_NAME
        # Name of the new module, will be used as prefix for generated files
        # (e.g. --name myapp creates myapp/activate, myapp/myapp_bu_module.sh, etc.)
        bu_parse_positional $# --hint "Module name (directory name, no spaces)"
        name=${!shift_by}
        ;;
    -d|--dir)# COMMAND_DIR
        # Parent directory to create the module in.
        # Defaults to the current working directory.
        bu_parse_positional $# "${BU_AUTOCOMPLETE_SPEC_DIRECTORY[@]}"
        dir=${!shift_by}
        ;;
    -f|--force)# _FLAG
        # Overwrite existing files in the target directory
        is_force=true
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
    bu_autocomplete
    return 0
fi

if "$is_help"
then
    bu_autohelp \
        --description "
Scaffold a new BashTab module directory with the standard layout:
  {NAME}/
  ├── activate
  ├── {NAME}_bu_module.sh
  ├── {NAME}_bu_preinit.sh
  └── commands/
A quick-start module skeleton, following the same pattern used by
the Utilities example project.
" \
        --example \
        "Create a module called myapp in the current directory" \
        "--name myapp" \
        --example \
        "Create a module in a specific directory" \
        "--name myapp --dir ~/Projects"
    return 0
fi

if [[ -z "$name" ]]
then
    bu_assert_err '--name not provided'
fi

# Validate name: no spaces, reasonable format
if [[ "$name" =~ [^a-zA-Z0-9_-] ]]
then
    bu_assert_err "Module name '$name' contains invalid characters (use a-z, 0-9, -, _)"
fi

dir=${dir:-$invocation_dir}
local module_dir=$dir/$name
local substitute_name=${name//-/_}

if [[ -d "$module_dir" ]] && ! "$is_force"
then
    bu_assert_err "$module_dir already exists (use --force to overwrite)"
fi

bu_log_info "Scaffolding module '$name' in $module_dir"

mkdir -p "$module_dir"/commands

# Copy and substitute templates
local tmpldir=$BU_LIB_TEMPLATE_DIR

# Activate script
(
    # shellcheck disable=SC2034
    MODULE_NAME=$substitute_name
    bu_gen_substitute MODULE_NAME <"$tmpldir"/module_activate.sh >"$module_dir"/activate
)
chmod +x "$module_dir"/activate

# Module registration
(
    MODULE_NAME=$substitute_name
    bu_gen_substitute MODULE_NAME <"$tmpldir"/module_module.sh >"$module_dir"/"${substitute_name}"_bu_module.sh
)

# Preinit callback
(
    MODULE_NAME=$substitute_name
    bu_gen_substitute MODULE_NAME <"$tmpldir"/module_preinit.sh >"$module_dir"/"${substitute_name}"_bu_preinit.sh
)

# Print summary
local g=$BU_TPUT_GREEN rs=$BU_TPUT_RESET b=$BU_TPUT_BOLD
echo
echo "  ${g}✓${rs} Module scaffolded at ${b}$module_dir${rs}"
echo
echo "  Layout:"
echo "    activate                      ← source this to enter the environment"
echo "    ${substitute_name}_bu_module.sh ← library registration (appends to BU_MODULE_LIST)"
echo "    ${substitute_name}_bu_preinit.sh ← pre-init callback (bu IS available here)"
echo "    commands/                     ← your subcommands (registered by preinit)"
echo
echo "  Lifecycle:"
echo "    1. activate sets BU_MODULE_LIST + BU_TOP_LEVEL_MODULE, sources bu_entrypoint.sh"
echo "    2. bu_entrypoint.sh parses BU_MODULE_LIST, registers preinit callbacks"
echo "    3. *_bu_preinit.sh runs → bu import-environment (bu is available)"
echo "    4. bu_mark_load_complete → caches command registry"
echo
echo "  Next steps:"
echo "    cd $module_dir"
echo "    source activate"
echo "    bu new-command --dir commands --name my-first-cmd"

bu_scope_pop_function
}

__bu_bu_new_module_main "$@"
