#!/usr/bin/env bash
# Pipeline: producer
# Fields: name path on_enter action dry_run
# Dispatch: source
# Synopsis: Change the current working directory
# Help-Topic: locations
function __bu_bu_set_location_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local module_name=
local commands_dir=
local location_name=
local is_cache=false
local is_bash_tab=false
local is_dry_run=false
local is_no_enter_hook=
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --module)# MODULE_NAME
        # Root directory of a loaded module (default: current top-level)
        # Optional name can follow, otherwise uses BU_TOP_LEVEL_MODULE
        if (($# >= 2)) && [[ "$2" != -* ]]; then
            module_name=$2
            shift_by=2
        fi
        ;;
    --commands-dir)# COMMANDS_DIR
        # A registered command-search directory
        bu_parse_positional $# --hint "Path to a commands directory"
        commands_dir=${!shift_by}
        ;;
    --cache)# _FLAG
        # BashTab cache directory
        is_cache=true
        ;;
    --bash-tab)# _FLAG
        # BashTab installation root (BU_DIR)
        is_bash_tab=true
        ;;
    --dry-run|--what-if) # _FLAG
        is_dry_run=true
        ;;
    --no-enter-hook)# _FLAG
        # Skip the location's on-enter callback
        is_no_enter_hook=true
        ;;
    -h|--help)# _FLAG
        # Print help
        is_help=true
        ;;
    *)
        if [[ "$1" != -* ]]
        then
            if bu_env_is_in_autocomplete
            then
                autocompletion=(--stdout bu_location_names --kind dir --with-aliases stdout-- --hint "Location name")
            fi
            location_name=$1
        else
            bu_parse_error_enum "$1"
            break
        fi
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

if bu_env_is_in_autocomplete
then
    bu_autocomplete
    return 0
fi

if "$is_help"
then
    bu_autohelp --description "
Change the current working directory to a well-known project location.

Runs in the current shell (sourceable command) so cd takes effect.
Equivalent to PowerShell's Set-Location.

With a NAME positional, resolves a registered dir location (see
bu new-location / bu get-location-registry) and cds into it.
" \
    --example "Jump to a registered location" "myproj" \
    --example "Jump to the top-level module root" "--module" \
    --example "Jump to a specific module" "--module mylib" \
    --example "Jump to a commands directory" "--commands-dir /path/to/commands" \
    --example "Jump to the cache directory" "--cache"
    return 0
fi

if [[ -n "$location_name" ]]
then
    if "$is_dry_run"
    then
        __bu_location_resolve_key "$location_name" --kind dir 2>/dev/null || {
            error_msg="Unknown dir location[$location_name]"
            bu_autohelp
            bu_scope_pop_function
            return 1
        }
        local _loc_key=$BU_RET
        bu_location_resolve "$location_name" --kind dir 2>/dev/null || {
            bu_scope_pop_function
            return 1
        }
        local _loc_path=${BU_RET[0]}
        local _loc_hook=${BU_LOCATION_PROPERTIES[$_loc_key,on_enter]:-}
        bu_out_record name="$location_name" path="$_loc_path" on_enter="$_loc_hook" action="would-cd" dry_run:=true | bu_out --format auto
        bu_scope_pop_function
        return 0
    fi
    bu_location_enter "$location_name" ${is_no_enter_hook:+--no-enter-hook} || {
        bu_scope_pop_function
        return 1
    }
    bu_scope_pop_function
    return 0
fi

local dir=

if [[ -n "$commands_dir" ]]; then
    # Validate it's a registered command-search directory
    if [[ -z "${BU_COMMAND_SEARCH_DIRS[$commands_dir]:-}" ]]; then
        bu_log_err "Not a registered command-search directory: $commands_dir"
        bu_log_info "Registered directories:"
        local d
        for d in "${!BU_COMMAND_SEARCH_DIRS[@]}"; do
            bu_log_info "  $d"
        done
        return 1
    fi
    dir=$commands_dir
elif "$is_cache"; then
    dir=$BU_CACHE_DIR
elif "$is_bash_tab"; then
    dir=$BU_DIR
else
    # Default: --module with optional name
    local key=${module_name:-${BU_TOP_LEVEL_MODULE:-}}
    if [[ -z "$key" ]]; then
        if "$is_dry_run"; then
            bu_log_info "Would cd to module root (no BU_TOP_LEVEL_MODULE set)"
            bu_scope_pop_function; return 0
        fi
        bu_log_err "No module specified and BU_TOP_LEVEL_MODULE is not set"
        return 1
    fi
    local entry=${BU_MODULE_REGISTRY[$key]:-}
    if [[ -z "$entry" ]]; then
        if "$is_dry_run"; then
            bu_log_info "Would cd to module '$key' (not currently loaded)"
            bu_scope_pop_function; return 0
        fi
        bu_log_err "Module '$key' not found in BU_MODULE_REGISTRY"
        local mod
        bu_log_info "Loaded modules:"
        for mod in "${!BU_MODULE_REGISTRY[@]}"; do
            bu_log_info "  $mod"
        done
        return 1
    fi
    # entry format: "version:preinit_path"
    dir=$(dirname -- "${entry#*:}")
fi

if [[ -z "$dir" ]]; then
    bu_log_err "Specify a location: --module, --commands-dir, --cache, or --bash-tab"
    return 1
fi

if "$is_dry_run"; then
    bu_log_info "Would cd to: $dir"
    bu_scope_pop_function
    return 0
fi

if [[ ! -d "$dir" ]]; then
    bu_log_err "Directory does not exist: $dir"
    return 1
fi

cd "$dir" || return 1
bu_log_info "Now in $dir"

bu_scope_pop_function
}

__bu_bu_set_location_main "$@"
