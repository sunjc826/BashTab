#!/usr/bin/env bash
# Pipeline: producer
# Fields: path parent leaf extension stem
# Dispatch: source
# Synopsis: Split a file path into its components
function __bu_bu_split_path_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local -a paths=()
local format=auto
local is_help=false
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
    -h|--help)# _FLAG
        # Print help
        is_help=true
        ;;
    *)
        if bu_env_is_in_autocomplete
        then
            # Path positional: complete files
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
Split paths into their components (PowerShell Split-Path, dirname/basename as records).
Emits one record per path: path, parent (directory part), leaf (final
component), extension (including the dot, null when none), and stem
(leaf without extension). Hidden files like .bashrc have no extension.
" \
        --example "Split one path" "/usr/local/bin/tool.sh" \
        --example "Project just extensions" "--format jsonl"
    return 0
fi

if ((${#paths[@]} == 0))
then
    error_msg="Missing required path (e.g. bu split-path /usr/local/bin/tool.sh)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

local p parent leaf ext stem
{
    for p in "${paths[@]}"
    do
        parent=$(dirname -- "$p")
        leaf=$(basename -- "$p")
        ext=
        stem=$leaf
        # An extension requires a dot that is not the first character (.bashrc has none)
        if [[ "$leaf" == ?*.* ]]
        then
            ext=.${leaf##*.}
            stem=${leaf%.*}
        fi
        if [[ -n "$ext" ]]
        then
            bu_out_record path="$p" parent="$parent" leaf="$leaf" extension="$ext" stem="$stem"
        else
            bu_out_record path="$p" parent="$parent" leaf="$leaf" extension:=null stem="$stem"
        fi
    done
} | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_split_path_main "$@"
