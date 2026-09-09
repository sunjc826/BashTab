#!/usr/bin/env bash
# Pipeline: transform
# Requires-All: path
# Fields: path would_create dry_run mtime_before mtime_after atime_before atime_after error
# Dispatch: source
# Synopsis: Modify file timestamps or create empty files
function __bu_bu_update_file_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local -a paths=()
local is_no_create=false
local is_access=false
local reference=
local timestamp=
local is_dry_run=false
local format=auto
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --no-create)# _FLAG
        # Do not create the file if it doesn't exist
        is_no_create=true
        ;;
    -a|--access)# _FLAG
        # Only update access time (touch -a)
        is_access=true
        ;;
    --reference)# PATH
        # Use this file's timestamps instead of current time
        bu_parse_positional $# "${BU_AUTOCOMPLETE_SPEC_FILE[@]}" --hint "Reference file"
        reference=${!shift_by}
        ;;
    --timestamp)# TIMESTAMP
        # Specific timestamp: [[CC]YY]MMDDhhmm[.ss] or ISO 8601
        bu_parse_positional $# --hint "Timestamp"
        timestamp=${!shift_by}
        ;;
    --dry-run|--what-if)# _FLAG
        # Show what would happen without doing it
        is_dry_run=true
        ;;
    --format)# FORMAT
        bu_parse_positional $# --enum ${BU_OUT_FORMATS[@]} enum-- --hint "Output format"
        format=${!shift_by}
        ;;
    -h|--help)# _FLAG
        is_help=true
        ;;
    *)
        if bu_env_is_in_autocomplete; then
            autocompletion=("${BU_AUTOCOMPLETE_SPEC_FILE[@]}")
        fi
        paths+=("$1")
        ;;
    esac
    if "$is_help"; then break; fi
    if (( $# < shift_by )); then bu_parse_error_argn "$1" $#; break; fi
    shift "$shift_by"
done
if bu_env_is_in_autocomplete; then bu_autocomplete; return 0; fi

if "$is_help"; then
    bu_autohelp \
        --description "
Update file timestamps (touch).  Creates empty files by default; use
--no-create to only update existing files.

Accepts file paths as positional arguments. When no paths are given and
stdin is a pipe, reads JSONL records from stdin and operates on each
record's .path field.

Output: one record per path with mtime_before, mtime_after, atime_before, atime_after.
" \
        --example "Touch a file (update mtime)" "file.txt" \
        --example "Create empty file" "newfile.txt" \
        --example "Only existing files" "--no-create file.txt" \
        --example "Use reference timestamps" "--reference other.txt file.txt" \
        --example "Change access time" "--access file.txt"
    return 0
fi

# Read paths from stdin pipeline
if ((${#paths[@]} == 0)) && read -t 0 2>/dev/null; then
    local line
    while IFS= read -r line; do
        local p
        p=$(jq -r '.path // empty' <<<"$line" 2>/dev/null) || true
        [[ -n "$p" ]] && paths+=("$p")
    done
fi

if ((${#paths[@]} == 0)); then
    error_msg="No paths specified. Provide file paths or pipe records with .path fields."
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

local -a touch_args=()
"$is_no_create" && touch_args+=(-c)
"$is_access" && touch_args+=(-a)
[[ -n "$reference" ]] && touch_args+=(-r "$reference")
[[ -n "$timestamp" ]] && touch_args+=(-t "$timestamp")

local p rc=0
{
    for p in "${paths[@]}"; do
        local mtime_before atime_before
        if [[ -e "$p" ]]; then
            read -r mtime_before atime_before < <(stat -c '%Y %X' "$p" 2>/dev/null) || { mtime_before=0; atime_before=0; }
        else
            mtime_before=0; atime_before=0
        fi

        if "$is_dry_run"; then
            local would_create=false
            [[ ! -e "$p" ]] && ! "$is_no_create" && would_create=true
            bu_out_record path="$p" would_create:="$would_create" dry_run:=true | bu_out --format jsonl
            continue
        fi

        if [[ ! -e "$p" ]] && "$is_no_create"; then
            bu_out_record path="$p" error="file not found (--no-create prevents creation)"
            rc=1
            continue
        fi

        touch "${touch_args[@]}" "$p" 2>/dev/null || {
            bu_out_record path="$p" error="touch failed (permission denied?)"
            rc=1
            continue
        }

        local mtime_after atime_after
        read -r mtime_after atime_after < <(stat -c '%Y %X' "$p" 2>/dev/null) || { mtime_after=0; atime_after=0; }

        bu_out_record path="$p" \
            mtime_before:="$mtime_before" mtime_after:="$mtime_after" \
            atime_before:="$atime_before" atime_after:="$atime_after"
    done
} | bu_out --format "$format"

bu_scope_pop_function
return $rc
}

__bu_bu_update_file_main "$@"
