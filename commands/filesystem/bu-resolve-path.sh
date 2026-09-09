#!/usr/bin/env bash
# Pipeline: producer
# Fields: path resolved exists
# Dispatch: source
# Synopsis: Resolve a relative path to an absolute path
function __bu_bu_resolve_path_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local -a paths=()
local format=auto
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --format)# FORMAT
        # Output format
        bu_parse_positional $# --enum ${BU_OUT_FORMATS[@]} enum-- --hint "Output format"
        format=${!shift_by}
        ;;
    -h|--help)# _FLAG
        # Print help
        is_help=true
        ;;
    *)
        if bu_env_is_in_autocomplete
        then
            # Path positional: complete files
            autocompletion=("${BU_AUTOCOMPLETE_SPEC_FILE[@]}")
        fi
        paths+=("$1")
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
    bu_autohelp \
        --description "
Resolve paths to their canonical absolute form (PowerShell Resolve-Path).
Symlinks and . / .. components are resolved. Emits one record per path:
path (as given), resolved (canonical), exists (boolean).
" \
        --example "Resolve a relative path" "../README.md" \
        --example "Resolve several" "./lib ./commands"
    return 0
fi

if ((${#paths[@]} == 0))
then
    error_msg="Missing required path (e.g. bu resolve-path ./lib)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

local p resolved exists
{
    for p in "${paths[@]}"
    do
        exists=false
        [[ -e "$p" ]] && exists=true
        if resolved=$(realpath -- "$p" 2>/dev/null)
        then
            bu_out_record path="$p" resolved="$resolved" exists:=$exists
        else
            bu_out_record path="$p" resolved:=\"\" exists:=$exists
        fi
    done
} | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_resolve_path_main "$@"
