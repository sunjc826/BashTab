#!/usr/bin/env bash
# Pipeline: producer
# Fields: guid
# Dispatch: source
# Synopsis: Generate a new GUID/UUID
function __bu_bu_new_guid_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local count=1
local format=auto
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    -n|--count)# N
        # Number of GUIDs to generate
        bu_parse_positional $# --hint "Count"
        count=${!shift_by}
        ;;
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
if bu_env_is_in_autocomplete
then
    bu_autocomplete
    return 0
fi

if "$is_help"
then
    bu_autohelp \
        --description "
Generate random UUIDs (PowerShell New-Guid).
Reads from /proc/sys/kernel/random/uuid when available (no dependencies),
otherwise falls back to uuidgen. Emits one record per GUID.
" \
        --example "One GUID" "" \
        --example "Five GUIDs" "--count 5"
    return 0
fi

local i guid
{
    for ((i = 0; i < count; i++))
    do
        if [[ -r /proc/sys/kernel/random/uuid ]]
        then
            guid=$(cat /proc/sys/kernel/random/uuid)
        elif command -v uuidgen &>/dev/null
        then
            guid=$(uuidgen)
        else
            bu_log_err "Neither /proc/sys/kernel/random/uuid nor uuidgen is available"
            bu_scope_pop_function
            return 1
        fi
        bu_out_record guid="$guid"
    done
} | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_new_guid_main "$@"
