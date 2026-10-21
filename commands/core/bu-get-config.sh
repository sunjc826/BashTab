#!/usr/bin/env bash
# Pipeline: producer
# Dispatch: source
# Synopsis: List BashTab configuration settings
# Help-Topic: config
# Fields: name value origin phase default allowed module description location
function __bu_bu_get_config_main()
{
# --is-compatible: no external dependencies
if [[ "$1" == "--is-compatible" ]]; then
    exit 0
fi

local -r invocation_dir=$PWD
local script_name script_dir
case "$BASH_SOURCE" in
*/*)
    script_name=${BASH_SOURCE##*/}
    script_dir=${BASH_SOURCE%/*}
    ;;
*)
    script_name=$BASH_SOURCE
    script_dir=.
    ;;
esac
pushd "$script_dir" &>/dev/null

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_scope_add_cleanup bu_popd_silent
bu_run_log_command "$@"

local -a names=()
local -a excludes=()
local format=${BU_OUTPUT_FORMAT:-auto}
local columns=
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
    --columns)# COLUMNS
        # Fields to display, in order (comma-separated)
        bu_parse_positional $# --hint "Comma-separated fields: name value origin phase default allowed module description location"
        columns=${!shift_by}
        ;;
    --exclude)# PATTERN
        # Leave out settings matching this name or pattern (repeatable)
        bu_parse_positional $# --glob --ret __bu_config_completion_names ret-- --hint "Setting name or pattern"
        excludes+=("${!shift_by}")
        ;;
    -h|--help)# _FLAG
        # Print help
        is_help=true
        ;;
    *)# NAME
        # Setting name or pattern (repeatable); none lists every setting
        if bu_env_is_in_autocomplete && [[ "$1" != -* ]]
        then
            autocompletion=(--glob --ret __bu_config_completion_names ret-- --hint "Setting name or pattern")
        fi
        if [[ "$1" == -* ]]
        then
            bu_parse_error_enum "$1"
            break
        fi
        names+=("$1")
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
        --example "Every setting" "" \
        --example "One setting" "BU_OUT_DIR" \
        --example "Output settings" "'BU_OUT*'"
    return 0
fi

# Last assignment line of each setting in the settings files that set one,
# for the location column (each file read once, in-process).
local -A assign_line=()
local -a file_lines=()
local -r assign_re='^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)='
local file i
for file in "${BU_CONFIG_SOURCE_FILE[@]}"
do
    [[ -v "assign_line[$file,]" ]] && continue
    assign_line[$file,]=scanned
    [[ -r "$file" ]] || continue
    mapfile -t file_lines < "$file"
    for i in "${!file_lines[@]}"
    do
        if [[ "${file_lines[i]}" =~ $assign_re ]]
        then
            assign_line[$file,${BASH_REMATCH[2]}]=$((i + 1))
        fi
    done
done

# Select names in this shell: the record loop below runs in a pipeline
# subshell, and seen must survive it for the missing-name report.
local key name
local -a selected=()
local -A seen=()
for key in "${!BU_CONFIG_PROPERTIES[@]}"
do
    [[ "$key" == *,registered ]] || continue
    name=${key%,registered}
    bu_glob_match "$name" "${names[@]}" || continue
    seen[$name]=1
    bu_glob_excludes "$name" "${excludes[@]}" && continue
    selected+=("$name")
done

# Stream TSV records (zero forks in the loop), recordify once, then
# let bu_out decide presentation (table on a terminal, JSONL when piped).
{
    local current origin location phase_label
    for name in "${selected[@]}"
    do
        current=${!name:-}
        phase_label=${BU_CONFIG_PROPERTIES[$name,phase]:-}
        [[ -n "${__BU_CONFIG_PHASE_VARIANT[$phase_label]:-}" ]] && phase_label+="[${__BU_CONFIG_PHASE_VARIANT[$phase_label]}]"
        # Origin: changed in the shell since its phase ran, else who set it
        # then (env, local, site, callback, layer), else the default.
        __bu_config_origin "$name"
        origin=$BU_RET
        case "$origin" in
        shell)
            location=
            ;;
        default)
            location=${BU_CONFIG_PROPERTIES[$name,defined_at]:-}
            ;;
        *)
            file=${BU_CONFIG_SOURCE_FILE[$name]:-}
            location=$file${assign_line[$file,$name]:+:${assign_line[$file,$name]}}
            ;;
        esac
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$name" \
            "${current:-(unset)}" \
            "$origin" \
            "$phase_label" \
            "${BU_CONFIG_PROPERTIES[$name,default]:-}" \
            "${BU_CONFIG_PROPERTIES[$name,enum]:-${BU_CONFIG_PROPERTIES[$name,bool]:+true|false}}" \
            "${BU_CONFIG_PROPERTIES[$name,module]:-}" \
            "${BU_CONFIG_PROPERTIES[$name,hint]:-}" \
            "$location"
    done
} | bu_out_from_tsv --columns name,value,origin,phase,default,allowed,module,description,location | bu_out --format "$format" ${columns:+--columns "$columns"}

local exit_code=0
bu_glob_report_missing setting seen "${names[@]}" || exit_code=1

bu_scope_pop_function
return "$exit_code"
}

__bu_bu_get_config_main "$@"
