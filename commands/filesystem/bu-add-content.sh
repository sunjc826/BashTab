#!/usr/bin/env bash
# Pipeline: transform
# Requires-All: line
# Fields: path bytes_appended appended error
# Dispatch: source
# Synopsis: Append content to a file
function __bu_bu_add_content_main()
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
source ../../bu_entrypoint.sh
fi
bu_log_trace "after entrypoint"

bu_exit_handler_setup
bu_scope_push_function
bu_scope_add_cleanup bu_popd_silent
bu_run_log_command "$@"
bu_log_trace "after init+run_log"

local path=
local content=
local is_no_newline=false
local is_what_if=false
local format=auto
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --path)# PATH
        # Target file path
        bu_parse_positional $# "${BU_AUTOCOMPLETE_SPEC_FILE[@]}"
        path=${!shift_by}
        ;;
    --no-newline)# _FLAG
        # Suppress the trailing newline
        is_no_newline=true
        ;;
    --what-if)# _FLAG
        # Show what would happen without changing anything
        is_what_if=true
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
        if bu_env_is_in_autocomplete && [[ "$1" != -* ]] && [[ -z "$path" ]]
        then
            :
        fi
        if [[ -z "$path" ]]
        then
            path=$1
        elif [[ -z "$content" ]]
        then
            content=$1
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
bu_log_trace "after while loop"
if bu_env_is_in_autocomplete
then
    bu_autocomplete
    return 0
fi

if "$is_help"
then
    bu_log_trace "before bu_autohelp"
    bu_autohelp \
        --description "
Append content to a file (PowerShell Add-Content analog).
Content comes from a positional argument, or from stdin (pipeline).
When piping from get-content, .line fields are joined with newlines.

Use --no-newline to suppress the trailing newline. Emits one record:
path, bytes_appended, appended (boolean).
" \
        --example "Append a line" "--path /tmp/log.txt '[ERROR] something went wrong'" \
        --example "Bare positionals" "/tmp/log.txt '[ERROR] something went wrong'" \
        --example "Pipeline from get-content" "| bu where '.line | test(\"ERROR\")' | bu add-content --path /tmp/errors.log"
    bu_log_trace "after bu_autohelp"

    return 0
fi

if [[ -z "$path" ]]
then
    error_msg="Missing required --path (e.g. bu add-content --path /tmp/log.txt 'new line')"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

# Collect content: positional arg takes precedence, then pipeline
if [[ -z "$content" ]] && [[ ! -t 0 ]]
then
    # Read all stdin. Try JSONL first (.line fields), fall back to raw text.
    local first_line
    IFS= read -r first_line || first_line=
    if [[ -n "$first_line" ]] && echo "$first_line" | jq -e '.line // empty' &>/dev/null 2>&1
    then
        # JSONL input: extract .line fields
        content=$( { echo "$first_line"; cat; } | jq -r '.line' 2>/dev/null | { if "$is_no_newline"; then paste -sd '' -; else cat; fi; } )
    else
        # Raw text input
        content=$( { echo "$first_line"; cat; } )
    fi
fi

if [[ -z "$content" ]]
then
    error_msg="Missing content. Provide a positional argument or pipe content to stdin."
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

if "$is_what_if"
then
    bu_log_info "What if: append $(echo "$content" | wc -c) bytes to $path"
    bu_scope_pop_function
    return 0
fi

local bytes_before=0
local bytes_after=0
local err=
# Get current size
bytes_before=$(wc -c < "$path" 2>/dev/null) || bytes_before=0

# Append to file
{
    if "$is_no_newline"
    then
        printf '%s' "$content"
    else
        printf '%s\n' "$content"
    fi
} >> "$path" 2>/dev/null || { err="append failed (permission denied or disk full)"; }

if [[ -z "$err" ]]
then
    bytes_after=$(wc -c < "$path" 2>/dev/null) || bytes_after="$bytes_before"
    local bytes_appended=$((bytes_after - bytes_before))
    bu_out_record path="$path" bytes_appended:="$bytes_appended" appended:=true | bu_out --format "$format"
else
    bu_out_record path="$path" bytes_appended:=0 appended:=false error="$err" | bu_out --format "$format"
    bu_scope_pop_function
    return 1
fi

bu_scope_pop_function
}

__bu_bu_add_content_main "$@"
