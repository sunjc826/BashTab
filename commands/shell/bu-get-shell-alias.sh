#!/usr/bin/env bash
# Pipeline: producer
# Dispatch: source
# Synopsis: Show bash shell aliases (alias builtin)
# Help-Topic: aliases
# Fields: name definition
function __bu_bu_get_shell_alias_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local name=
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
            # Name positional: complete from defined aliases
            autocompletion=(--ret __bu_bu_get_shell_alias_complete_names ret-- --hint "Alias name")
        fi
        if [[ -z "$name" ]]
        then
            name=$1
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
List bash shell aliases (the alias builtin) as records.
Runs in the current shell, so it sees your interactive aliases. Each
record has name and definition. Give a name to show just that alias.
For the CLI's own registered aliases use get-alias.
" \
        --example "All aliases" "" \
        --example "One alias" "ll"
    return 0
fi

# Runs sourced, so `alias` (builtin) sees the current shell's aliases.
# Output form: alias name='definition'  (definition may itself contain quotes)
if [[ -n "$name" ]]
then
    alias "$name" 2>/dev/null
else
    alias
fi | jq -R -c '
    select(startswith("alias "))
    | .[6:]
    | capture("^(?<name>[^=]+)=(?<definition>.*)$")
    | .definition |= (
        . as $d
        | if ($d | startswith("\u0027")) and ($d | endswith("\u0027"))
          then $d[1:-1] | gsub("\u0027\\\\\u0027\u0027"; "\u0027")
          else $d
          end
    )
' | bu_out --format "$format"

bu_scope_pop_function
}

# Completion helper: defined alias names.
__bu_bu_get_shell_alias_complete_names()
{
    BU_RET=()
    local a
    while IFS= read -r a
    do
        [[ -n "$a" ]] && BU_RET+=("$a")
    done < <(alias | sed -n "s/^alias \([^=]*\)=.*/\1/p")
}

__bu_bu_get_shell_alias_main "$@"
