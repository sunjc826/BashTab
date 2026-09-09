#!/usr/bin/env bash
# Pipeline: transform
# Requires-Any: path filename new_name
# Fields: path new_name renamed error
# Dispatch: source
# Synopsis: Rename a file or directory
function __bu_bu_rename_item_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local path=
local new_name=
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
    --what-if)# _FLAG
        # Show what would happen without changing anything
        is_what_if=true
        ;;
    --format)# FORMAT
        # Output format
        bu_parse_positional $# --enum ${BU_OUT_FORMATS[@]} enum-- --hint "Output format"
        format=${!shift_by}
        ;;
    --path)# PATH
        # Existing path to rename (also accepts pipeline input by structural typing)
        bu_parse_positional $# "${BU_AUTOCOMPLETE_SPEC_FILE[@]}" --hint "Existing file or directory"
        path=${!shift_by}
        ;;
    --new-name)# NAME
        # New name for the item (also accepts pipeline input by structural typing)
        bu_parse_positional $# --hint "New name (not a path, no slashes)"
        new_name=${!shift_by}
        ;;
    -h|--help)# _FLAG
        # Print help
        is_help=true
        ;;
    *)
        if [[ -z "$path" ]]
        then
            if bu_env_is_in_autocomplete
            then
                # Existing path positional: complete files
                autocompletion=("${BU_AUTOCOMPLETE_SPEC_FILE[@]}")
            fi
            path=$1
        elif [[ -z "$new_name" ]]
        then
            new_name=$1
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
Rename a file or directory in place (PowerShell Rename-Item).
The new name is a name, not a path: the item stays in its directory.
Use bu move-item to relocate. Emits one record: path, new_name,
renamed (boolean).
" \
        --example "Rename a file" "old.txt new.txt" \
        --example "Dry run" "old.txt new.txt --what-if"
        --example "Pipeline input" ""
    return 0
fi

# Pipeline input: when no path/new_name are given and stdin is a pipe, read
# JSONL records and extract .path (or .filename) and .new_name via structural typing.
if [[ -z "$path" || -z "$new_name" ]] && [[ ! -t 0 ]]
then
    local _line _p _n
    while IFS=$'\t' read -r _p _n
    do
        if [[ -z "$path" && -n "$_p" ]]
        then
            path=$_p
        fi
        if [[ -z "$new_name" && -n "$_n" ]]
        then
            new_name=$_n
        fi
    done < <(jq -r '(.path // .filename // null) as $p | (.new_name // null) as $n | if $p then ($p + "\t" + ($n // "")) else empty end' 2>/dev/null)
fi

if [[ -z "$path" || -z "$new_name" ]]
then
    error_msg="Need a path and a new name (e.g. bu rename-item old.txt new.txt)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

if [[ "$new_name" == */* ]]
then
    error_msg="New name must not contain '/'; use bu move-item to relocate"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

# Records go to a temp file (not a pipeline) so the failure status survives in rc.
local records_file
records_file=$(mktemp)
bu_scope_add_cleanup rm -f "$records_file"

local rc=0
{
    if [[ ! -e "$path" && ! -L "$path" ]]
    then
        bu_out_record path="$path" new_name="$new_name" renamed:=false error="does not exist"
        rc=1
    elif "$is_what_if"
    then
        bu_log_info "What if: rename $path to $new_name"
    else
        mv -- "$path" "$(dirname -- "$path")/$new_name" \
            && bu_out_record path="$path" new_name="$new_name" renamed:=true \
            || { bu_out_record path="$path" new_name="$new_name" renamed:=false; rc=1; }
    fi
} > "$records_file"

bu_out --format "$format" < "$records_file"

bu_scope_pop_function
return $rc
}

__bu_bu_rename_item_main "$@"
