#!/usr/bin/env bash
# Pipeline: producer
# Fields: path name type size mode owner group mtime ctime
# Dispatch: source
# Synopsis: Search for files matching a pattern
function __bu_bu_find_file_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local -a paths=()
local name=
local type_filter=
local mindepth=
local maxdepth=
local size_larger=
local size_smaller=
local newer=
local older=
local owner_filter=
local group_filter=
local mode_filter=
local is_empty=false
local format=auto
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --name)# PATTERN
        # File name glob pattern (e.g. '*.sh', '*.{js,ts}')
        bu_parse_positional $# --hint "Name glob pattern"
        name=${!shift_by}
        ;;
    -t|--type)# TYPE
        # Filter by type: file, directory, symlink, block, char, fifo, socket
        bu_parse_positional $# --enum f d l b c p s enum-- --hint "File type"
        type_filter=${!shift_by}
        ;;
    --mindepth)# N
        # Minimum directory depth (0 = start paths themselves)
        bu_parse_positional $# --hint "Min depth"
        mindepth=${!shift_by}
        ;;
    --maxdepth)# N
        # Maximum directory depth
        bu_parse_positional $# --hint "Max depth"
        maxdepth=${!shift_by}
        ;;
    --larger)# SIZE
        # Files larger than this (e.g. 10k, 5M, 1G)
        bu_parse_positional $# --hint "Size (e.g. 10k, 5M)"
        size_larger=${!shift_by}
        ;;
    --smaller)# SIZE
        # Files smaller than this (e.g. 1M)
        bu_parse_positional $# --hint "Size (e.g. 1M)"
        size_smaller=${!shift_by}
        ;;
    --newer)# PATH
        # Files modified more recently than this reference file
        bu_parse_positional $# "${BU_AUTOCOMPLETE_SPEC_FILE[@]}" --hint "Reference file path"
        newer=${!shift_by}
        ;;
    --older)# PATH
        # Files modified before this reference file
        bu_parse_positional $# "${BU_AUTOCOMPLETE_SPEC_FILE[@]}" --hint "Reference file path"
        older=${!shift_by}
        ;;
    --owner)# USER
        # Files owned by this user
        bu_parse_positional $# --hint "User name or UID"
        owner_filter=${!shift_by}
        ;;
    --group)# GROUP
        # Files belonging to this group
        bu_parse_positional $# --hint "Group name or GID"
        group_filter=${!shift_by}
        ;;
    --mode)# MODE
        # Permission mode filter (e.g. 644, +x)
        bu_parse_positional $# --hint "Mode (e.g. 644)"
        mode_filter=${!shift_by}
        ;;
    --empty)# _FLAG
        # Only empty files or directories
        is_empty=true
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
            autocompletion=("${BU_AUTOCOMPLETE_SPEC_DIRECTORY[@]}")
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
Find files recursively with structured output (PowerShell Get-ChildItem -Recurse
on steroids).  Wraps find(1) and enriches each result with stat(1) metadata.

Default searches from the current directory.  All filters map to native find
predicates for zero-overhead filtering.

Output fields: path, name, type, size, mode, owner, group, mtime, ctime

Filters: --name (glob), --type (f/d/l), --mindepth, --maxdepth,
         --larger/--smaller (size), --newer/--older (time), --owner, --group,
         --mode, --empty
" \
        --example "All files recursively" "" \
        --example "Shell scripts" "--name '*.sh' --type f" \
        --example "Large files" "--larger 10M --type f" \
        --example "Recent changes" "--newer . --maxdepth 2" \
        --example "Find + act pipeline" "| bu sort size --desc | bu select path,size"
    return 0
fi

# Default search path
((${#paths[@]} == 0)) && paths=(.)

# Build find arguments
local -a find_args=("${paths[@]}")

# Depth constraints
[[ -n "$mindepth" ]] && find_args+=(-mindepth "$mindepth")
[[ -n "$maxdepth" ]] && find_args+=(-maxdepth "$maxdepth")

# Type filter
if [[ -n "$type_filter" ]]; then
    case "$type_filter" in
        f) find_args+=(-type f) ;;
        d) find_args+=(-type d) ;;
        l) find_args+=(-type l) ;;
        b) find_args+=(-type b) ;;
        c) find_args+=(-type c) ;;
        p) find_args+=(-type p) ;;
        s) find_args+=(-type s) ;;
    esac
fi

# Name filter
[[ -n "$name" ]] && find_args+=(-name "$name")

# Size filters
[[ -n "$size_larger" ]] && find_args+=(-size "+$size_larger")
[[ -n "$size_smaller" ]] && find_args+=(-size "-$size_smaller")

# Time filters
[[ -n "$newer" ]] && find_args+=(-newer "$newer")
[[ -n "$older" ]] && find_args+=(-not -newer "$older")

# Owner/group
[[ -n "$owner_filter" ]] && find_args+=(-user "$owner_filter")
[[ -n "$group_filter" ]] && find_args+=(-group "$group_filter")

# Mode
[[ -n "$mode_filter" ]] && find_args+=(-perm "$mode_filter")

# Empty
"$is_empty" && find_args+=(-empty)

# Use find + stat to produce TSV: path<TAB>name<TAB>type<TAB>size<TAB>mode<TAB>owner<TAB>group<TAB>mtime<TAB>ctime
find "${find_args[@]}" 2>/dev/null | while IFS= read -r filepath; do
    [[ -z "$filepath" ]] && continue
    local fname ftype fsize fmode fowner fgroup fmtime fctime
    fname=$(basename "$filepath")
    if [[ -d "$filepath" ]]; then ftype=d
    elif [[ -L "$filepath" ]]; then ftype=l
    elif [[ -b "$filepath" ]]; then ftype=b
    elif [[ -c "$filepath" ]]; then ftype=c
    elif [[ -p "$filepath" ]]; then ftype=p
    elif [[ -S "$filepath" ]]; then ftype=s
    else ftype=f
    fi
    read -r fmode fowner fgroup fsize fmtime fctime < <(
        stat -c '%a %U %G %s %Y %Z' "$filepath" 2>/dev/null || echo '0 unknown unknown 0 0 0'
    )
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$filepath" "$fname" "$ftype" "$fsize" "$fmode" "$fowner" "$fgroup" "$fmtime" "$fctime"
done | bu_out_from_tsv --columns path,name,type,size,mode,owner,group,mtime,ctime \
    | jq -c '.size |= tonumber | .mtime |= tonumber | .ctime |= tonumber' \
    | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_find_file_main "$@"
