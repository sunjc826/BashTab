#!/usr/bin/env bash
# Pipeline: transform
# Requires-Any: source path filename
# Fields: source destination copied error
# Dispatch: source
# Synopsis: Copy a file or directory
function __bu_bu_copy_item_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local -a args=()
local is_recursive=false
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
    -r|--recursive)# _FLAG
        # Copy directories recursively
        is_recursive=true
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
    --source)# SOURCE
        # Source path to copy (repeatable; also accepts pipeline input by structural typing)
        bu_parse_positional $# "${BU_AUTOCOMPLETE_SPEC_FILE[@]}" --hint "File or directory path"
        args+=("${!shift_by}")
        ;;
    -h|--help)# _FLAG
        # Print help
        is_help=true
        ;;
    *)
        if bu_env_is_in_autocomplete
        then
            # Path positionals: complete files
            autocompletion=("${BU_AUTOCOMPLETE_SPEC_FILE[@]}")
        fi
        args+=("$1")
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
Copy files and directories (PowerShell Copy-Item, structured cp).
The last positional is the destination; all preceding positionals are
sources. When copying several sources, the destination must be an
existing directory. Emits one record per source: source, destination,
copied (boolean).
" \
        --example "One file" "a.txt backup/a.txt" \
        --example "Several into a directory" "-r src include dist/" \
        --example "Dry run" "a.txt /tmp --what-if"
        --example "Pipeline input" ""
    return 0
fi

if ((${#args[@]} < 1))
then
    error_msg="Need a destination (e.g. bu copy-item a.txt backup/)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

local destination=${args[-1]}
local -a sources=()
if ((${#args[@]} >= 2))
then
    sources=("${args[@]:0:${#args[@]}-1}")
fi

# Pipeline input: when no sources are given as arguments and stdin is a pipe,
# read JSONL records and extract .source (or .path, .filename) via structural typing.
if ((${#sources[@]} == 0)) && [[ ! -t 0 ]]
then
    local _s
    while IFS= read -r _s
    do
        [[ -n "$_s" ]] && sources+=("$_s")
    done < <(jq -r '.source // .path // .filename // empty' 2>/dev/null)
fi

if ((${#sources[@]} == 0))
then
    error_msg="Need at least one source (e.g. bu copy-item a.txt backup/)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

if ((${#sources[@]} > 1)) && [[ ! -d "$destination" ]]
then
    error_msg="Destination must be an existing directory when copying multiple sources: $destination"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

local -a cp_args=()
"$is_recursive" && cp_args+=(-r)

# Records go to a temp file (not a pipeline) so the loop runs in the current
# shell and the per-item failure status survives in rc.
local records_file
records_file=$(mktemp)
bu_scope_add_cleanup rm -f "$records_file"

local rc=0
local src
{
    for src in "${sources[@]}"
    do
        if [[ ! -e "$src" ]]
        then
            bu_out_record source="$src" destination="$destination" copied:=false error="source does not exist"
            rc=1
            continue
        fi
        if [[ -d "$src" ]] && ! "$is_recursive"
        then
            bu_out_record source="$src" destination="$destination" copied:=false error="is a directory (use --recursive)"
            rc=1
            continue
        fi
        if "$is_what_if"
        then
            bu_log_info "What if: copy $src to $destination"
            continue
        fi
        cp "${cp_args[@]}" -- "$src" "$destination" \
            && bu_out_record source="$src" destination="$destination" copied:=true \
            || { bu_out_record source="$src" destination="$destination" copied:=false; rc=1; }
    done
} > "$records_file"

bu_out --format "$format" < "$records_file"

bu_scope_pop_function
return $rc
}

__bu_bu_copy_item_main "$@"
