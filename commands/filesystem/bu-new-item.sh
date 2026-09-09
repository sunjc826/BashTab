#!/usr/bin/env bash
# Pipeline: transform
# Requires-Any: path filename name
# Fields: path type created error
# Dispatch: source
# Synopsis: Create a new file or directory
function __bu_bu_new_item_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local -a paths=()
local type=file
local target=
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
    -t|--type)# TYPE
        # Kind of item to create
        bu_parse_positional $# --enum file directory symlink enum-- --hint "Item type"
        type=${!shift_by}
        ;;
    --target)# TARGET
        # Link target (required for --type symlink)
        bu_parse_positional $# --hint "Symlink target"
        target=${!shift_by}
        ;;
    -f|--force)# _FLAG
        # Create parent directories as needed
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
        # Path to create (repeatable; also accepts pipeline input by structural typing)
        bu_parse_positional $# "${BU_AUTOCOMPLETE_SPEC_FILE[@]}" --hint "File or directory path"
        paths+=("${!shift_by}")
        ;;
    -h|--help)# _FLAG
        # Print help
        is_help=true
        ;;
    *)
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
Create files, directories or symlinks (PowerShell New-Item, structured touch/mkdir/ln -s).
Emits one record per created item: path, type, created. --force creates
missing parent directories. Existing items are left untouched.
" \
        --example "Empty file" "notes.txt" \
        --example "Nested directory" "src/deep/dir --type directory" \
        --example "Symlink" "link --type symlink --target /etc/hosts"
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
    error_msg="Missing required path (e.g. bu new-item ./logs --type directory)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

if [[ "$type" == symlink && -z "$target" ]]
then
    error_msg="--type symlink requires --target"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

# Records go to a temp file (not a pipeline) so the loop runs in the current
# shell and the per-item failure status survives in rc.
local records_file
records_file=$(mktemp)
bu_scope_add_cleanup rm -f "$records_file"

local rc=0
local p parent
{
    for p in "${paths[@]}"
    do
        if [[ -e "$p" || -L "$p" ]]
        then
            bu_out_record path="$p" type="$type" created:=false error="already exists"
            rc=1
            continue
        fi
        parent=$(dirname -- "$p")
        if [[ ! -d "$parent" ]]
        then
            if "$is_force"
            then
                "$is_what_if" || mkdir -p -- "$parent"
            else
                bu_out_record path="$p" type="$type" created:=false error="parent directory does not exist (use --force)"
                rc=1
                continue
            fi
        fi
        if "$is_what_if"
        then
            bu_log_info "What if: create $type at $p"
            continue
        fi
        case "$type" in
        file)      touch -- "$p" ;;
        directory) mkdir -p -- "$p" ;;
        symlink)   ln -s -- "$target" "$p" ;;
        esac || { bu_out_record path="$p" type="$type" created:=false; rc=1; continue; }
        bu_out_record path="$p" type="$type" created:=true
    done
} > "$records_file"

bu_out --format "$format" < "$records_file"

bu_scope_pop_function
return $rc
}

__bu_bu_new_item_main "$@"
