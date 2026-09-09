#!/usr/bin/env bash
# Pipeline: producer
# Fields: path exists type
# Dispatch: source
# Synopsis: Test whether a file or directory exists
function __bu_bu_test_path_main()
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
Test whether paths exist, and what they are (PowerShell Test-Path).
Emits one record per path: path, exists (boolean), and type
(file, directory, symlink, other, or missing).
" \
        --example "Test one path" "/etc/hosts" \
        --example "Filter to missing paths" "/etc/hosts /nope | "
    return 0
fi

if ((${#paths[@]} == 0))
then
    error_msg="Missing required path (e.g. bu test-path /etc/hosts)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

local p type exists
{
    for p in "${paths[@]}"
    do
        exists=false
        type=missing
        if [[ -L "$p" ]]
        then
            exists=true; type=symlink
        elif [[ -f "$p" ]]
        then
            exists=true; type=file
        elif [[ -d "$p" ]]
        then
            exists=true; type=directory
        elif [[ -e "$p" ]]
        then
            exists=true; type=other
        fi
        bu_out_record path="$p" exists:=$exists type="$type"
    done
} | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_test_path_main "$@"
