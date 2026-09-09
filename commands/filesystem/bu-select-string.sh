#!/usr/bin/env bash
# Pipeline: recordify_lines
# Fields: path line_number line
# Dispatch: source
# Synopsis: Search for patterns in text and show matching lines
function __bu_bu_select_string_main()
{
# --is-compatible: magic flag checked by the framework at registration time.
# Exit 0 if this command can run on the current system, non-zero otherwise.
# stderr becomes the reason shown in `bu` help.
if [[ "$1" == "--is-compatible" ]]; then
    command -v grep &>/dev/null || { echo "grep is required" >&2; exit 1; }
    exit 0
fi
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local pattern=
local -a paths=()
local is_ignore_case=false
local is_invert=false
local is_recursive=false
local format=auto
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    -i|--ignore-case)# _FLAG
        # Case-insensitive matching
        is_ignore_case=true
        ;;
    -v|--invert-match)# _FLAG
        # Select lines that do NOT match
        is_invert=true
        ;;
    -r|--recursive)# _FLAG
        # Recurse into directory paths
        is_recursive=true
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
        if [[ -z "$pattern" ]]
        then
            pattern=$1
        else
            if bu_env_is_in_autocomplete
            then
                # Path positionals (after the pattern): complete files
                autocompletion=("${BU_AUTOCOMPLETE_SPEC_FILE[@]}")
            fi
            paths+=("$1")
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
Search text for a pattern, emitting one record per matching line (PowerShell Select-String, structured grep).
Records have path, line_number and line. The pattern is an extended
regular expression (grep -E). With no paths, reads stdin. Binary files
are skipped. No matches yields an empty stream (exit 0).
" \
        --example "Search one file" "'TODO' app.log" \
        --example "Recursive, ignore case" "-r -i 'error' /var/log" \
        --example "Filter a stream" "'GET /api' < access.log"
    return 0
fi

if [[ -z "$pattern" ]]
then
    error_msg="Missing required pattern (e.g. bu select-string 'TODO' app.log)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

local -a grep_args=(-E -n -H -I -e "$pattern")
"$is_ignore_case" && grep_args+=(-i)
"$is_invert" && grep_args+=(-v)
"$is_recursive" && grep_args+=(-r)

if ((${#paths[@]} > 0))
then
    grep_args+=(-- "${paths[@]}")
else
    # stdin: give matches a stable path label
    grep_args+=(--label '<stdin>' -)
fi

# grep exit 1 = no matches (fine, empty stream); errors go to stderr unmerged
grep "${grep_args[@]}" \
    | jq -R -c '
        select(. != "")
        | (capture("^(?<path>.*?):(?<line_number>[0-9]+):(?<line>.*)$")? // empty)
        | .line_number |= tonumber
    ' 2>/dev/null \
    | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_select_string_main "$@"
