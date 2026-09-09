#!/usr/bin/env bash
# Pipeline: transform
# Requires-Any: path filename name
# Fields: path removed error
# Dispatch: source
# Synopsis: Delete a file or directory
function __bu_bu_remove_item_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local -a paths=()
local is_recursive=false
local is_force=false
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
        # Remove directories and their contents
        is_recursive=true
        ;;
    -f|--force)# _FLAG
        # Ignore nonexistent paths and never prompt (rm -f)
        is_force=true
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
    --path)# PATH
        # Path to remove (repeatable; also accepts pipeline input by structural typing)
        bu_parse_positional $# "${BU_AUTOCOMPLETE_SPEC_FILE[@]}" --hint "File or directory path"
        paths+=("${!shift_by}")
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
Remove files and directories (PowerShell Remove-Item, structured rm).
Directories require --recursive. Emits one record per path: path,
removed (boolean). Failures include an error field and set a non-zero
exit code. Destructive: use --what-if to preview.
" \
        --example "One file" "tmp.txt" \
        --example "Directory tree" "-r build/" \
        --example "Dry run" "-r build/ --what-if"
        --example "Pipeline input" ""
    return 0
fi

# Pipeline input: when no paths are given and stdin is a pipe, read JSONL
# records and extract .path (or .filename, .name) via structural typing.
if ((${#paths[@]} == 0)) && [[ ! -t 0 ]]
then
    local _p
    while IFS= read -r _p
    do
        [[ -n "$_p" ]] && paths+=("$_p")
    done < <(jq -r '.path // .filename // .name // empty' 2>/dev/null)
fi

if ((${#paths[@]} == 0))
then
    error_msg="Missing required path (e.g. bu remove-item tmp.txt)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

local -a rm_args=()
"$is_recursive" && rm_args+=(-r)
"$is_force" && rm_args+=(-f)

# Records go to a temp file (not a pipeline) so the loop runs in the current
# shell and the per-item failure status survives in rc.
local records_file
records_file=$(mktemp)
bu_scope_add_cleanup rm -f "$records_file"

local rc=0
local p
{
    for p in "${paths[@]}"
    do
        if [[ ! -e "$p" && ! -L "$p" ]]
        then
            if "$is_force"
            then
                continue
            fi
            bu_out_record path="$p" removed:=false error="does not exist"
            rc=1
            continue
        fi
        if "$is_what_if"
        then
            bu_log_info "What if: remove $p"
            continue
        fi
        rm "${rm_args[@]}" -- "$p" \
            && bu_out_record path="$p" removed:=true \
            || { bu_out_record path="$p" removed:=false; rc=1; }
    done
} > "$records_file"

bu_out --format "$format" < "$records_file"

bu_scope_pop_function
return $rc
}

__bu_bu_remove_item_main "$@"
