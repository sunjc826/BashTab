#!/usr/bin/env bash
# Pipeline: producer
# Dispatch: source
# Tab-Execute: true
# Synopsis: Show subsystem-level help topics
# Fields: topic synopsis file module source

# Render one topic, prefixing a "Module:" line when the topic is owned by a
# module (core/user-local topics have no module).
__bu_bu_get_help_render_one()
{
    local file=$1
    local module=$2
    local bold=$3
    local reset=$4
    if [[ -n "$module" ]]
    then
        printf '%s\n\n' "${bold}Module:${reset} $module"
    fi
    __bu_help_topic_render "$file" "$bold" "$reset"
}

function __bu_bu_get_help_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local format=auto
local columns=
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
local -a topics=()
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --format)# FORMAT
        # Output format
        bu_parse_positional $# --enum ${BU_OUT_FORMATS[@]} enum-- --hint "Output format"
        bu_validate_positional "${!shift_by}"
        format=${!shift_by}
        ;;
    --columns)# COLUMNS
        # Fields to display, in order (comma-separated)
        bu_parse_positional $# --delimited topic synopsis file module source delimited-- --hint "Comma-separated fields"
        columns=${!shift_by}
        ;;
    -h|--help)# _FLAG
        # Print help
        is_help=true
        ;;
    *)
        if bu_env_is_in_autocomplete && [[ "$1" != -* ]]
        then
            autocompletion=(--ret bu_help_topic_names ret-- --hint "Help topic name")
        fi
        if [[ "$1" == -* ]]
        then
            bu_parse_error_enum "$1"
        else
            topics+=("$1")
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
Help topics are the subsystem-level documentation layer: what a command
suite is for, how its commands compose, typical flows, and failure
signatures.  Each topic is a bash script sourced in a subshell, so its text
can reflect THIS machine (real paths, live session state) rather than a
stale snapshot.

With no topic names, lists registered topics as records.
With one or more topic names, renders each topic's help text.
" \
        --example "List all topics" "" \
        --example "List topics as JSON" "--format json" \
        --example "Render one topic" "widgets" \
        --example "Render several topics" "widgets networking"
    return 0
fi

# ── No positional args: list topics as records ──
if ((${#topics[@]} == 0))
then
    bu_help_topic_names
    local -a topic_names=("${BU_RET[@]}")
    local name file synopsis module src
    {
        for name in "${topic_names[@]}"
        do
            [[ -z "$name" ]] && continue
            file=${BU_HELP_TOPIC_REGISTRY[$name]:-}
            module=${BU_HELP_TOPIC_PROPERTIES[$name,module]:-}
            src=${BU_HELP_TOPIC_PROPERTIES[$name,source]:-}
            __bu_help_topic_synopsis "$file"
            synopsis=$BU_RET
            printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$synopsis" "$file" "$module" "$src"
        done
    } | bu_out_from_tsv --columns topic,synopsis,file,module,source \
        | bu_out --format "$format" ${columns:+--columns "$columns"}

    bu_scope_pop_function
    return 0
fi

# ── One or more topic names: render each ──
# Validate ALL names BEFORE rendering: the render pipeline's left side runs
# in a subshell, so an error detected there could not set our return code.
local topic
local -a render_files=()
local -a render_modules=()
local -a unknown=()
for topic in "${topics[@]}"
do
    local resolved=${BU_HELP_TOPIC_REGISTRY[$topic]:-}
    if [[ -n "$resolved" ]]
    then
        render_files+=("$resolved")
        render_modules+=("${BU_HELP_TOPIC_PROPERTIES[$topic,module]:-}")
    else
        unknown+=("$topic")
    fi
done

local exit_code=0
if ((${#unknown[@]} > 0))
then
    bu_help_topic_names
    local -a avail=("${BU_RET[@]}")
    bu_log_err "Unknown help topic(s): ${unknown[*]}; available: ${avail[*]:-none}"
    exit_code=1
fi

if ((${#render_files[@]} > 0))
then
    if [[ -t 1 ]]
    then
        local bold=$BU_TPUT_BOLD
        local reset=$BU_TPUT_RESET
        {
            local i
            for i in "${!render_files[@]}"
            do
                __bu_bu_get_help_render_one "${render_files[$i]}" "${render_modules[$i]}" "$bold" "$reset"
            done
        } | less -FRX
    else
        {
            local i
            for i in "${!render_files[@]}"
            do
                __bu_bu_get_help_render_one "${render_files[$i]}" "${render_modules[$i]}" "" ""
            done
        } | cat
    fi
fi

bu_scope_pop_function
return "$exit_code"
}

__bu_bu_get_help_main "$@"
