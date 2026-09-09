#!/usr/bin/env bash
# Pipeline: producer
# Dispatch: source
# Synopsis: List registered named locations
# Help-Topic: locations
# Fields: name kind path_expr resolved description tags aliases on_enter source
function __bu_bu_get_location_registry_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local kind=
local tag=
local format=auto
local columns=
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --kind)# KIND
        # Filter by location kind (dir, file, multi)
        bu_parse_positional $# --enum dir file multi enum-- --hint "Location kind"
        kind=${!shift_by}
        ;;
    --tag)# TAG
        # Filter by tag (comma-separated tags CSV)
        bu_parse_positional $# --stdout __bu_bu_get_location_registry_complete_tags stdout-- --hint "Location tag"
        tag=${!shift_by}
        ;;
    --format)# FORMAT
        # Output format
        bu_parse_positional $# --enum ${BU_OUT_FORMATS[@]} enum-- --hint "Output format"
        format=${!shift_by}
        ;;
    --columns)# COLUMNS
        # Display columns as key:Label (comma-separated)
        bu_parse_positional $# --hint "Comma-separated columns, key:Label renames headers" --pipeline-fields pipeline-fields--
        columns=${!shift_by}
        ;;
    -h|--help)# _FLAG
        # Print help
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

if bu_env_is_in_autocomplete
then
    bu_autocomplete
    return 0
fi

if "$is_help"
then
    bu_autohelp \
        --description "
List the named-location registry as records. Each entry shows its unexpanded
path expression and a best-effort resolved value (empty when the resolver
fails or a referenced environment variable is unset). Filter by kind and tag.
" \
        --example "All locations" "" \
        --example "Only directories" "--kind dir" \
        --example "Only repos" "--tag repo"
    return 0
fi

{
    local key k display path_expr resolved description tags aliases_csv on_enter source
    local a
    for key in "${!BU_LOCATION_REGISTRY[@]}"
    do
        k=${BU_LOCATION_REGISTRY[$key]}
        [[ -n "$kind" && "$k" != "$kind" ]] && continue
        if [[ -n "$tag" ]]
        then
            __bu_location_tag_match "${BU_LOCATION_PROPERTIES[$key,tags]:-}" "$tag" || continue
        fi

        display=$key
        [[ "$key" == *:* ]] && display=${key#*:}

        path_expr=${BU_LOCATION_PROPERTIES[$key,path]:-}
        description=${BU_LOCATION_PROPERTIES[$key,description]:-}
        tags=${BU_LOCATION_PROPERTIES[$key,tags]:-}
        on_enter=${BU_LOCATION_PROPERTIES[$key,on_enter]:-}
        source=${BU_LOCATION_PROPERTIES[$key,source]:-}

        # Best-effort resolution: empty on failure (never fails the listing).
        resolved=
        if bu_location_resolve "$key" --no-verify 2>/dev/null
        then
            resolved=$(printf '%s ' "${BU_RET[@]}")
            resolved=${resolved% }
        fi

        aliases_csv=
        for a in "${!BU_LOCATION_ALIASES[@]}"
        do
            if [[ "${BU_LOCATION_ALIASES[$a]}" == "$key" ]]
            then
                aliases_csv+="${aliases_csv:+,}$a"
            fi
        done

        bu_out_record \
            name="$display" kind="$k" path_expr="$path_expr" resolved="$resolved" \
            description="$description" tags="$tags" aliases="$aliases_csv" \
            on_enter="$on_enter" source="$source"
    done
} | bu_out --format "$format" ${columns:+--columns "$columns"}

bu_scope_pop_function
}

# Completion helper: distinct tags in the registry.
__bu_bu_get_location_registry_complete_tags()
{
    BU_RET=()
    local key tags ifs=$IFS t
    local -A seen=()
    for key in "${!BU_LOCATION_REGISTRY[@]}"
    do
        tags=${BU_LOCATION_PROPERTIES[$key,tags]:-}
        IFS=','
        for t in $tags
        do
            [[ -n "$t" && -z "${seen[$t]:-}" ]] || continue
            seen[$t]=1
            BU_RET+=("$t")
        done
        IFS=$ifs
    done
}

__bu_bu_get_location_registry_main "$@"
