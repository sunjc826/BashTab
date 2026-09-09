#!/usr/bin/env bash
# Pipeline: producer
# Fields: path format size file_count
# Dispatch: source
# Synopsis: Compress a file using gzip, bzip2, or xz
function __bu_bu_compress_file_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local destination=
local -a sources=()
local format_type=tgz
local is_dry_run=false
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --destination)# PATH
        # Output archive path (required)
        bu_parse_positional $# "${BU_AUTOCOMPLETE_SPEC_FILE[@]}" --hint "Archive path"
        destination=${!shift_by}
        ;;
    --format)# FORMAT
        # Archive format: tgz (tar.gz), tbz2 (tar.bz2), txz (tar.xz), zip, tar
        bu_parse_positional $# --enum tgz tbz2 txz zip tar enum-- --hint "Archive format"
        format_type=${!shift_by}
        ;;
    --dry-run|--what-if)# _FLAG
        # Show what would be created without doing it
        is_dry_run=true
        ;;
    -h|--help)# _FLAG
        is_help=true
        ;;
    *)
        if bu_env_is_in_autocomplete; then
            autocompletion=("${BU_AUTOCOMPLETE_SPEC_FILE[@]}")
        fi
        sources+=("$1")
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
Create a compressed archive (PowerShell Compress-Archive analog).
Supports tar.gz (tgz), tar.bz2 (tbz2), tar.xz (txz), tar, and zip.

Emits a record with the archive path, format, and size in bytes.

Output fields: path, format, size, file_count
" \
        --example "Tar.gz a directory" "--destination dist.tar.gz src/" \
        --example "Zip several files" "--format zip --destination bundle.zip a.txt b.txt c.txt" \
        --example "Tar.bz2" "--format tbz2 --destination proj.tar.bz2 ."
    return 0
fi

if [[ -z "$destination" ]]; then
    error_msg="--destination is required (e.g. bu compress-file --destination out.tar.gz src/)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

if ((${#sources[@]} == 0)); then
    error_msg="At least one source file or directory is required"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

# Check for required tools
local tool_missing=
case "$format_type" in
    tgz)  command -v tar &>/dev/null || tool_missing="tar" ;;
    tbz2) command -v tar &>/dev/null || tool_missing="tar" ;;
    txz)  command -v tar &>/dev/null || tool_missing="tar" ;;
    tar)  command -v tar &>/dev/null || tool_missing="tar" ;;
    zip)  command -v zip &>/dev/null || tool_missing="zip" ;;
esac
if [[ -n "$tool_missing" ]]; then
    error_msg="$tool_missing is required for --format $format_type"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

if "$is_dry_run"; then
    bu_out_record path="$destination" format="$format_type" size:=0 file_count:=0 dry_run:=true | bu_out --format jsonl
    bu_scope_pop_function
    return 0
fi

local file_count=0

case "$format_type" in
    tgz)
        tar -czf "$destination" "${sources[@]}" 2>/dev/null || {
            error_msg="Failed to create tar.gz archive"
            bu_autohelp; bu_scope_pop_function; return 1
        }
        ;;
    tbz2)
        tar -cjf "$destination" "${sources[@]}" 2>/dev/null || {
            error_msg="Failed to create tar.bz2 archive"
            bu_autohelp; bu_scope_pop_function; return 1
        }
        ;;
    txz)
        tar -cJf "$destination" "${sources[@]}" 2>/dev/null || {
            error_msg="Failed to create tar.xz archive"
            bu_autohelp; bu_scope_pop_function; return 1
        }
        ;;
    tar)
        tar -cf "$destination" "${sources[@]}" 2>/dev/null || {
            error_msg="Failed to create tar archive"
            bu_autohelp; bu_scope_pop_function; return 1
        }
        ;;
    zip)
        zip -r "$destination" "${sources[@]}" 2>/dev/null || {
            error_msg="Failed to create zip archive"
            bu_autohelp; bu_scope_pop_function; return 1
        }
        ;;
esac

local size
size=$(stat -c '%s' "$destination" 2>/dev/null) || size=0
file_count=$(tar -tf "$destination" 2>/dev/null | wc -l) || file_count=0

bu_out_record path="$destination" format="$format_type" size:="$size" file_count:="$file_count" | bu_out --format jsonl

bu_scope_pop_function
}

__bu_bu_compress_file_main "$@"
