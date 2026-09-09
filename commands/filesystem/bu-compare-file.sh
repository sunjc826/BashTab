#!/usr/bin/env bash
# Pipeline: producer
# Fields: reference difference status type line_number line path
# Dispatch: source
# Synopsis: Compare two files line by line
function __bu_bu_compare_file_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local reference=
local difference=
local is_recursive=false
local is_brief=false
local format=auto
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --reference)# PATH
        # Reference file or directory
        bu_parse_positional $# "${BU_AUTOCOMPLETE_SPEC_FILE[@]}" --hint "Reference path"
        reference=${!shift_by}
        ;;
    --difference)# PATH
        # File or directory to compare against reference
        bu_parse_positional $# "${BU_AUTOCOMPLETE_SPEC_FILE[@]}" --hint "Difference path"
        difference=${!shift_by}
        ;;
    -r|--recursive)# _FLAG
        # Recursively compare directories (diff -r)
        is_recursive=true
        ;;
    -q|--brief)# _FLAG
        # Only report whether files differ, not the actual differences
        is_brief=true
        ;;
    --format)# FORMAT
        bu_parse_positional $# --enum ${BU_OUT_FORMATS[@]} enum-- --hint "Output format"
        format=${!shift_by}
        ;;
    -h|--help)# _FLAG
        is_help=true
        ;;
    *)
        if [[ -z "$reference" ]]; then
            reference=$1
        elif [[ -z "$difference" ]]; then
            difference=$1
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
Compare two files or directories (PowerShell Compare-Object / Diff analog).

Produces structured diff records.  For files: added, removed, and context lines.
For directories with --recursive: one record per differing file.

Output fields (file mode): type (+/-/ /@@), line_number, line
Output fields (directory mode): path, status (differ/only-in-ref/only-in-diff)
" \
        --example "Compare files" "old.txt new.txt" \
        --example "Brief comparison" "--brief old.txt new.txt" \
        --example "Compare directories" "--recursive dir1/ dir2/" \
        --example "Bare positionals" "a.txt b.txt"
    return 0
fi

if [[ -z "$reference" || -z "$difference" ]]; then
    error_msg="Both reference and difference paths are required"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

if [[ -d "$reference" && -d "$difference" ]]; then
    # Directory comparison
    if "$is_brief"; then
        diff -rq "$reference" "$difference" 2>/dev/null | while IFS= read -r line; do
            local status path_ref
            if [[ "$line" == *" differ" ]]; then
                path_ref="${line#Files }"
                path_ref="${path_ref% and * differ}"
                printf '%s\t%s\n' "$path_ref" "differ"
            elif [[ "$line" == *"Only in $reference"* ]]; then
                local f="${line#Only in $reference}"
                f="${f#: }"
                printf '%s\t%s\n' "$reference/$f" "only-in-ref"
            elif [[ "$line" == *"Only in $difference"* ]]; then
                local f="${line#Only in $difference}"
                f="${f#: }"
                printf '%s\t%s\n' "$difference/$f" "only-in-diff"
            fi
        done | bu_out_from_tsv --columns path,status | bu_out --format "$format"
    else
        diff -r "$reference" "$difference" 2>/dev/null | awk -v ref="$reference" -v diff="$difference" '
            /^diff -r/ {
                # Extract the two paths after the diff command
                sub(/^diff -r /, "")
                # Just output header as a comment-like record
                printf "%s\t%s\n", $0, "diff-header"
            }
        ' | bu_out_from_tsv --columns line,type | bu_out --format "$format"
    fi
else
    # File comparison
    if "$is_brief"; then
        if diff -q "$reference" "$difference" &>/dev/null; then
            bu_out_record reference="$reference" difference="$difference" status="identical" | bu_out --format "$format"
        else
            bu_out_record reference="$reference" difference="$difference" status="differ" | bu_out --format "$format"
        fi
    else
        # Unified diff as structured records
        diff -u "$reference" "$difference" 2>/dev/null | awk '
            /^--- / { next }
            /^\+\+\+ / { next }
            /^@@ / {
                hunk = $0
                next
            }
            /^\+/  { printf "%s\t%s\t%s\n", "+", NR, substr($0, 2) }
            /^-/   { printf "%s\t%s\t%s\n", "-", NR, substr($0, 2) }
            /^ /   { printf "%s\t%s\t%s\n", " ", NR, substr($0, 2) }
        ' | bu_out_from_tsv --columns type,line_number,line \
          | jq -c '.line_number |= tonumber' \
          | bu_out --format "$format"
    fi
fi

bu_scope_pop_function
}

__bu_bu_compare_file_main "$@"
