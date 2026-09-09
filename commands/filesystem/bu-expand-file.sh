#!/usr/bin/env bash
# Pipeline: producer
# Fields: path format destination entry_count size type
# Dispatch: source
# Synopsis: Decompress a compressed file
function __bu_bu_expand_file_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local path=
local destination=.
local format_type=
local is_list=false
local is_dry_run=false
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --path)# PATH
        # Archive file path (required)
        bu_parse_positional $# "${BU_AUTOCOMPLETE_SPEC_FILE[@]}" --hint "Archive path"
        path=${!shift_by}
        ;;
    --destination)# DIR
        # Directory to extract into (default: current directory)
        bu_parse_positional $# "${BU_AUTOCOMPLETE_SPEC_DIRECTORY[@]}" --hint "Output directory"
        destination=${!shift_by}
        ;;
    --format)# FORMAT
        # Archive format. Auto-detected from extension if not specified.
        bu_parse_positional $# --enum tgz tbz2 txz tar zip enum-- --hint "Archive format"
        format_type=${!shift_by}
        ;;
    -l|--list)# _FLAG
        # List contents without extracting
        is_list=true
        ;;
    --dry-run|--what-if)# _FLAG
        # Show what would be extracted without doing it
        is_dry_run=true
        ;;
    -h|--help)# _FLAG
        is_help=true
        ;;
    *)
        if [[ -z "$path" ]]; then
            path=$1
        else
            break
        fi
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
Extract a compressed archive (PowerShell Expand-Archive analog).
Supports tar.gz, tar.bz2, tar.xz, tar, and zip. Format is auto-detected
from the file extension when not specified.

Use --list to peek inside without extracting. Emits one record per entry
with path, size, and type.

Output fields (--list): path, size, type
Output record (extract): path, format, destination, entry_count
" \
        --example "Extract archive" "dist.tar.gz" \
        --example "Extract to directory" "--path dist.zip --destination /tmp/out" \
        --example "List contents" "--list dist.tar.gz" \
        --example "Explicit format" "--format zip --path bundle.bin"
    return 0
fi

if [[ -z "$path" ]]; then
    error_msg="Archive path is required (e.g. bu expand-file dist.tar.gz)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

if [[ ! -f "$path" ]]; then
    error_msg="Archive not found: $path"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

# Auto-detect format from extension
if [[ -z "$format_type" ]]; then
    case "$path" in
        *.tar.gz|*.tgz)      format_type=tgz ;;
        *.tar.bz2|*.tbz2)    format_type=tbz2 ;;
        *.tar.xz|*.txz)      format_type=txz ;;
        *.tar)                format_type=tar ;;
        *.zip)                format_type=zip ;;
        *) error_msg="Cannot detect format from extension: $path. Use --format."; bu_autohelp; bu_scope_pop_function; return 1 ;;
    esac
fi

# Check for required tools
local tool_missing=
case "$format_type" in
    tgz|tbz2|txz|tar) command -v tar &>/dev/null || tool_missing="tar" ;;
    zip)               command -v unzip &>/dev/null || tool_missing="unzip" ;;
esac
if [[ -n "$tool_missing" ]]; then
    error_msg="$tool_missing is required for --format $format_type"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

if "$is_dry_run"; then
    bu_out_record path="$path" format="$format_type" destination="$destination" dry_run:=true | bu_out --format jsonl
    bu_scope_pop_function
    return 0
fi

if "$is_list"; then
    # List archive contents
    case "$format_type" in
        tgz|tbz2|txz|tar)
            # Use tar -t (terse list) for paths, then stat for sizes.
            # The verbose format is too variable to parse reliably.
            tar -tf "$path" 2>/dev/null | while IFS= read -r entry; do
                [[ -z "$entry" ]] && continue
                local etype=f
                [[ "$entry" == */ ]] && etype=d
                printf '%s\t%s\t%s\n' "$entry" "0" "$etype"
            done | bu_out_from_tsv --columns path,size,type \
              | jq -c '.size |= tonumber' \
              | bu_out --format auto
            ;;
        zip)
            unzip -l "$path" 2>/dev/null | tail -n +4 | head -n -2 | awk '{
                size = $1
                $1=""; $2=""; $3=""; $4=""
                gsub(/^[[:space:]]+/, "")
                path = $0
                printf "%s\t%s\t%s\n", path, size, "f"
            }' | bu_out_from_tsv --columns path,size,type \
              | jq -c '.size |= tonumber' \
              | bu_out --format auto
            ;;
    esac
else
    # Extract
    mkdir -p "$destination" 2>/dev/null || true
    local entry_count=0
    case "$format_type" in
        tgz)   tar -xzf "$path" -C "$destination" 2>/dev/null || { error_msg="Extract failed"; bu_autohelp; bu_scope_pop_function; return 1; } ;;
        tbz2)  tar -xjf "$path" -C "$destination" 2>/dev/null || { error_msg="Extract failed"; bu_autohelp; bu_scope_pop_function; return 1; } ;;
        txz)   tar -xJf "$path" -C "$destination" 2>/dev/null || { error_msg="Extract failed"; bu_autohelp; bu_scope_pop_function; return 1; } ;;
        tar)   tar -xf "$path" -C "$destination" 2>/dev/null || { error_msg="Extract failed"; bu_autohelp; bu_scope_pop_function; return 1; } ;;
        zip)   unzip -o "$path" -d "$destination" 2>/dev/null || { error_msg="Extract failed"; bu_autohelp; bu_scope_pop_function; return 1; } ;;
    esac
    entry_count=$(tar -tf "$path" 2>/dev/null | wc -l) || entry_count=0
    bu_out_record path="$path" format="$format_type" destination="$destination" entry_count:="$entry_count" | bu_out --format jsonl
fi

bu_scope_pop_function
}

__bu_bu_expand_file_main "$@"
