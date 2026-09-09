#!/usr/bin/env bash
# Pipeline: transform
# Requires-All: line
# Fields: path bytes_written overwritten error
# Dispatch: source
# Synopsis: Write content to a file
function __bu_bu_set_content_main()
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

bu_exit_handler_setup
bu_scope_push_function
bu_scope_add_cleanup bu_popd_silent
bu_run_log_command "$@"

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
            # First bare positional could be path
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
if bu_env_is_in_autocomplete
then
    bu_autocomplete
    return 0
fi

if "$is_help"
then
    bu_autohelp \
        --description "
Write content to a file, overwriting it (PowerShell Set-Content analog).
Content comes from a positional argument, or from stdin (pipeline).
When piping from get-content, .line fields are joined with newlines.

Use --no-newline to suppress the trailing newline. Emits one record:
path, bytes_written, overwritten (boolean).
" \
        --example "Write a string" "--path /tmp/msg.txt 'hello world'" \
        --example "Bare positionals" "/tmp/msg.txt 'hello world'" \
        --example "No trailing newline" "--path /tmp/data.bin --no-newline 'raw-data'" \
        --example "Pipeline from get-content" ""
    return 0
fi

if [[ -z "$path" ]]
then
    error_msg="Missing required --path (e.g. bu set-content --path /tmp/msg.txt 'hello')"
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
    bu_log_info "What if: write $(echo "$content" | wc -c) bytes to $path"
    bu_scope_pop_function
    return 0
fi

local bytes_written=0
local err=
# Write to file
{
    if "$is_no_newline"
    then
        printf '%s' "$content"
    else
        printf '%s\n' "$content"
    fi
} > "$path" 2>/dev/null || { err="write failed (permission denied or disk full)"; }

if [[ -z "$err" ]]
then
    bytes_written=$(wc -c < "$path" 2>/dev/null) || bytes_written=0
    bu_out_record path="$path" bytes_written:="$bytes_written" overwritten:=true | bu_out --format "$format"
else
    bu_out_record path="$path" bytes_written:=0 overwritten:=false error="$err" | bu_out --format "$format"
    bu_scope_pop_function
    return 1
fi

bu_scope_pop_function
}

__bu_bu_set_content_main "$@"
