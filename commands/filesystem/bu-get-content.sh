#!/usr/bin/env bash
# Pipeline: producer
# Fields: path line_number line
# Dispatch: source
# Synopsis: Read the contents of a file
function __bu_bu_get_content_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local -a files=()
local head=
local tail=
local is_follow=false
local format=auto
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --head)# N
        # Only the first N lines
        bu_parse_positional $# --hint "Line count"
        head=${!shift_by}
        ;;
    --tail)# N
        # Only the last N lines
        bu_parse_positional $# --hint "Line count"
        tail=${!shift_by}
        ;;
    -f|--follow)# _FLAG
        # Keep reading as the file grows (tail -f); single file only
        is_follow=true
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
        files+=("$1")
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
Read files as line records (PowerShell Get-Content, structured cat/head/tail).
Emits one record per line: path, line_number, line. Line numbers restart
at 1 for --tail output. With no files, reads stdin (path is <stdin>).
Combine with bu where to filter lines, bu select line to
recover plain text.
" \
        --example "Whole file" "app.log" \
        --example "First 20 lines" "app.log --head 20" \
        --example "Follow a growing log" "app.log --follow"
    return 0
fi

if [[ -n "$head" && -n "$tail" ]]
then
    error_msg="--head and --tail are mutually exclusive"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

if "$is_follow" && ((${#files[@]} > 1))
then
    error_msg="--follow supports a single file only"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

# No files: read stdin with a synthetic path
if ((${#files[@]} == 0))
then
    if [[ -t 0 ]]
    then
        error_msg="Missing required file (e.g. bu get-content app.log --head 20)"
        bu_autohelp
        bu_scope_pop_function
        return 1
    fi
    files=(-)
fi

# Emit one file's lines as TSV: path <TAB> line_number <TAB> line
__bu_get_content_file_tsv()
{
    local path=$1
    local input_cmd=()
    if [[ "$path" == - ]]
    then
        path='<stdin>'
        input_cmd=(cat)
    elif "$is_follow"
    then
        input_cmd=(tail -n +1 -f -- "$path")
    elif [[ -n "$head" ]]
    then
        input_cmd=(head -n "$head" -- "$path")
    elif [[ -n "$tail" ]]
    then
        input_cmd=(tail -n "$tail" -- "$path")
    else
        input_cmd=(cat -- "$path")
    fi
    "${input_cmd[@]}" 2>/dev/null | awk -v path="$path" '{printf "%s\t%d\t%s\n", path, NR, $0}'
}

local f
{
    for f in "${files[@]}"
    do
        __bu_get_content_file_tsv "$f"
    done
} | bu_out_from_tsv --columns path,line_number,line \
  | jq -c '.line_number |= tonumber' \
  | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_get_content_main "$@"
