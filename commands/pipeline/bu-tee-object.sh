#!/usr/bin/env bash
# Pipeline: passthrough
# Dispatch: source
# Synopsis: Tee a JSONL stream to a file while passing it through
function __bu_bu_tee_object_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local file=
local is_append=false
local format=auto
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    -a|--append)# _FLAG
        # Append to the file instead of overwriting it
        is_append=true
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
        if bu_env_is_in_autocomplete
        then
            # File positional: complete files
            autocompletion=("${BU_AUTOCOMPLETE_SPEC_FILE[@]}")
        fi
        if [[ -z "$file" ]]
        then
            file=$1
        else
            bu_parse_error_enum "$1"
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
    bu_autohelp \
        --description "
Save a copy of the JSONL stream to a file while passing it through (PowerShell Tee-Object).
The raw JSONL records are written to the file; the stream continues
downstream unchanged. Streams with O(1) latency (tee).
" \
        --example "Snapshot and display" "snapshot.jsonl" \
        --example "Append to a log" "--append audit.jsonl"
    return 0
fi

if [[ -z "$file" ]]
then
    error_msg="Missing required file path (e.g. bu get-process | bu tee-object snapshot.jsonl)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

local -a tee_args=()
"$is_append" && tee_args+=(-a)

tee "${tee_args[@]}" -- "$file" | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_tee_object_main "$@"
