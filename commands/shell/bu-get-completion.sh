#!/usr/bin/env bash
# Pipeline: producer
# Fields: command spec handler
# Dispatch: source
# Synopsis: Generate autocomplete candidates for the current command line
function __bu_bu_get_completion_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local command_name=
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
        if bu_env_is_in_autocomplete && [[ "$1" != -* ]]
        then
            # Command positional: complete from registered completion specs
            autocompletion=(--ret __bu_bu_get_completion_complete_names ret-- --hint "Command name")
        fi
        if [[ -z "$command_name" ]]
        then
            command_name=$1
        else
            bu_parse_error_enum "$1"
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
List registered readline completions (structured complete -p).
Each record: command, spec (the full option string, e.g. -F _func), and
handler (the -F function or -W word list when present). Default/-D/-E
fallback specs are reported with command '(default)'. Handy for
debugging completion registration.
" \
        --example "All completions" "" \
        --example "One command" "git"
    return 0
fi

# complete -p prints: complete <opts...> <name>   (one per line)
local line last spec handler
{
    while IFS= read -r line
    do
        [[ "$line" == complete\ * ]] || continue
        last=${line##* }
        spec=${line:9}
        spec=${spec% "$last"}
        # Default-completion specs (-D, -E, -I) have no command name
        if [[ "$last" == -* ]]
        then
            last='(default)'
            spec=${line:9}
        fi
        handler=
        case "$spec" in
        *-F\ *) handler=${spec#*-F }; handler=${handler%% *} ;;
        *-W\ *) handler=${spec#*-W }; handler=${handler%% *} ;;
        esac
        if [[ -n "$command_name" && "$last" != "$command_name" ]]
        then
            continue
        fi
        bu_out_record command="$last" spec="$spec" handler="$handler"
    done < <(complete -p)
} | bu_out --format "$format"

bu_scope_pop_function
}

# Completion helper: commands that have a registered completion spec.
__bu_bu_get_completion_complete_names()
{
    BU_RET=()
    local c
    while IFS= read -r c
    do
        [[ -n "$c" ]] && BU_RET+=("$c")
    done < <(complete -p | awk '{print $NF}' | grep -v '^-')
}

__bu_bu_get_completion_main "$@"
