#!/usr/bin/env bash
# Pipeline: sink
# Dispatch: source
# Synopsis: Write a JSONL stream to a file
function __bu_bu_out_file_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local file=
local is_append=false
local format=jsonl
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
        # Format written to the file (default: jsonl)
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
Write the JSONL stream to a file and terminate the pipeline (PowerShell Out-File).
The file receives the stream rendered in --format (default jsonl, the
lossless round-trip format). Nothing is emitted downstream. Use
bu tee-object instead to save a copy while continuing the pipeline.
" \
        --example "Save as JSONL" "out.jsonl" \
        --example "Save a report as a table" "report.txt --format table" \
        --example "Append" "--append out.jsonl"
    return 0
fi

if [[ -z "$file" ]]
then
    error_msg="Missing required file path (e.g. bu get-process | bu out-file procs.jsonl)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

if "$is_append"
then
    bu_out --format "$format" >> "$file"
else
    bu_out --format "$format" > "$file"
fi

local rc=$?
if ((rc == 0))
then
    bu_log_info "Wrote output to $file"
else
    bu_log_err "Failed to write to $file"
fi
bu_scope_pop_function
return $rc
}

__bu_bu_out_file_main "$@"
