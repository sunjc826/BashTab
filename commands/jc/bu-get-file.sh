#!/usr/bin/env bash
# Pipeline: producer
# Dispatch: source
# Synopsis: List files with metadata
# Fields: filename flags links owner group size date
function __bu_bu_get_file_main()
{
# --is-compatible: magic flag checked by the framework at registration time.
# Exit 0 if this command can run on the current system, non-zero otherwise.
# stderr becomes the reason shown in `bu` help.
if [[ "$1" == "--is-compatible" ]]; then
    command -v jc &>/dev/null || { echo "jc is required" >&2; exit 1; }
    command -v ls &>/dev/null || { echo "ls is required" >&2; exit 1; }
    command -v find &>/dev/null || { echo "find is required (for --recurse/--file/--directory/--depth)" >&2; exit 1; }
    exit 0
fi
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local is_help=false
local format=auto
local path=
local is_recurse=false
local only_files=false
local only_dirs=false
local depth=
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --format)# FORMAT
        # Output format
        bu_parse_positional $# --enum ${BU_OUT_FORMATS[@]} enum-- --hint "Output format"
        format=${!shift_by}
        ;;
    -r|--recurse)# _FLAG
        # Descend into subdirectories (PowerShell Get-ChildItem -Recurse)
        is_recurse=true
        ;;
    --file)# _FLAG
        # Only regular files (PowerShell Get-ChildItem -File)
        only_files=true
        ;;
    -d|--directory)# _FLAG
        # Only directories (PowerShell Get-ChildItem -Directory)
        only_dirs=true
        ;;
    --depth)# N
        # Max directory depth (implies find mode; 0 = the path itself)
        bu_parse_positional $# --hint "Max depth"
        depth=${!shift_by}
        ;;
    -h|--help)# _FLAG
        is_help=true
        ;;
    --)
        # Remaining args are passed through to ls, replacing the default arguments
        shift
        break
        ;;
    *)
        if bu_env_is_in_autocomplete
        then
            # Path positional: complete directories
            autocompletion=("${BU_AUTOCOMPLETE_SPEC_DIRECTORY[@]}")
        fi
        if [[ -z "$path" ]]
        then
            path=$1
        else
            # Any further unrecognized arg: pass through to ls, replacing the default arguments
            break
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
local remaining_options=("$@")
if bu_env_is_in_autocomplete
then
    bu_autocomplete
    return 0
fi

if "$is_help"
then
    bu_autohelp \
        --description "
List files in a directory (jc ls parser wrapper, PowerShell Get-ChildItem).
Default lists the current directory in long format. The filter flags
(--recurse, --file, --directory, --depth) switch to find mode: entries
are located with find(1), then stat'd with ls for the same record shape.
" \
        --example "Current directory" "" \
        --example "One directory" "/var/log" \
        --example "All files below a path" "src --recurse --file" \
        --example "Shallow listing" "/etc --depth 1" \
        --example "With extra ls flags" "-- -lh /var/log"
    return 0
fi

if ! command -v jc &>/dev/null
then
    error_msg="jc is required. Install with: pip install jc"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

if "$is_recurse" || "$only_files" || "$only_dirs" || [[ -n "$depth" ]]
then
    # find mode: locate entries, stat them with ls for the jc record shape
    local -a find_args=("${path:-.}")
    [[ -n "$depth" ]] && find_args+=(-maxdepth "$depth")
    if "$only_files" && ! "$only_dirs"
    then
        find_args+=(-type f)
    elif "$only_dirs" && ! "$only_files"
    then
        find_args+=(-type d)
    fi
    find "${find_args[@]}" -exec ls -ld {} + 2>/dev/null \
        | jc --ls 2>/dev/null \
        | jq -c 'if type == "array" then .[] else . end' 2>/dev/null \
        | bu_out --format "$format"
else
    # ls mode: base command + provided args, otherwise base + default args
    local -a cmd=(ls)
    if ((${#remaining_options[@]} > 0))
    then
        cmd+=("${remaining_options[@]}")
    else
        cmd+=(-la "${path:-.}")
    fi
    "${cmd[@]}" 2>/dev/null \
        | jc --ls 2>/dev/null \
        | jq -c 'if type == "array" then .[] else . end' 2>/dev/null \
        | bu_out --format "$format"
fi

bu_scope_pop_function
}

__bu_bu_get_file_main "$@"
