#!/usr/bin/env bash
# Pipeline: producer
# Fields: command bash_completion on_path location
# Dispatch: source
# Synopsis: Show Fig completion status
function __bu_bu_get_fig_status_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local format=auto
local filter_on_path=false
local filter_no_bash=false
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --format)# FORMAT
        bu_parse_positional $# --enum ${BU_OUT_FORMATS[@]} enum-- --hint "Output format"
        format=${!shift_by}
        ;;
    --on-path)# _FLAG
        # Only show commands found on PATH
        filter_on_path=true
        ;;
    --no-bash)# _FLAG
        # Only show commands without a bash completion function
        filter_no_bash=true
        ;;
    --useful)# _FLAG
        # Shortcut for --on-path --no-bash
        filter_on_path=true
        filter_no_bash=true
        ;;
    -h|--help)# _FLAG
        is_help=true
        ;;
    *)
        bu_parse_error_enum "$1"
        break
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
        --description "Show Fig spec coverage: which CLIs have bash completions and which are on PATH." \
        --example "Default (all specs)" "" \
        --example "Only commands on PATH" "--on-path" \
        --example "Only commands without bash completion" "--no-bash" \
        --example "Useful gaps (on PATH, no bash)" "--useful" \
        --example "Useful gaps as JSON" "--useful --format json"
    return 0
fi

# Derive BashTab root from this script'\''s location
local -r script_dir=${BASH_SOURCE%/*}
local -r bu_root=$(realpath -- "$script_dir/../..")
local spec_dir="${BU_FIG_SPEC_DIR:-${bu_root}/fig_specs/build}"
[[ -d "$spec_dir" ]] || {
    bu_log_err "Fig specs directory not found: $spec_dir"
    bu_scope_pop_function
    return 1
}

# Collect stats for each Fig spec
local spec_file spec_name
local has_completion is_on_path path_location
local -a results_name=() results_completion=() results_onpath=() results_path=()

while IFS= read -r -d '' spec_file
do
    spec_name=$(basename "$spec_file" .json)
    [[ "$spec_name" == [-.]* ]] && continue
    [[ "$spec_name" == [0-9]* ]] && continue

    # Check bash completion (lazy-load first if needed)
    if ! complete -p "$spec_name" &>/dev/null
    then
        # Trigger lazy loading — only __load_completion (loads dedicated completion files),
        # NOT _completion_loader (which registers a generic fallback for everything)
        { declare -F __load_completion &>/dev/null && __load_completion "$spec_name" </dev/null 2>/dev/null; } || true
    fi
    if complete -p "$spec_name" &>/dev/null
    then
        has_completion=yes
    else
        has_completion=no
    fi

    # Check if on PATH
    path_location=$(type -P "$spec_name" 2>/dev/null)
    if [[ -n "$path_location" ]]
    then
        is_on_path=yes
    else
        is_on_path=no
        path_location=-
    fi

    # Apply filters
    "$filter_on_path" && [[ "$is_on_path" == no ]] && continue
    "$filter_no_bash" && [[ "$has_completion" == yes ]] && continue

    results_name+=("$spec_name")
    results_completion+=("$has_completion")
    results_onpath+=("$is_on_path")
    results_path+=("$path_location")
done < <(find "$spec_dir" -maxdepth 1 -name '*.json' -print0)

((${#results_name[@]})) || {
    bu_log_warn "No Fig specs found in $spec_dir"
    bu_scope_pop_function
    return 0
}

# Emit TSV and pipe through the structured output pipeline
{
    local i
    for ((i = 0; i < ${#results_name[@]}; i++))
    do
        printf '%s\t%s\t%s\t%s\n' \
            "${results_name[i]}" \
            "${results_completion[i]}" \
            "${results_onpath[i]}" \
            "${results_path[i]}"
    done
} | sort -t$'\t' -k2,2 -k3,3 | bu_out_from_tsv --columns command,bash_completion,on_path,location | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_get_fig_status_main "$@"
