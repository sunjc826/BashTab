#!/usr/bin/env bash
# Pipeline: producer
# Dispatch: source
# Tab-Execute: true
# Synopsis: List the CLI's registered aliases
# Help-Topic: aliases
# Fields: name root definition synopsis
function __bu_bu_get_alias_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local -a names=()
local root=
local format=auto
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --root)# ROOT
        # Glob pattern on the command each alias expands to
        bu_parse_positional $# --glob --ret __bu_bu_get_alias_complete_roots ret-- --hint "Root command or pattern"
        root=${!shift_by}
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
    *)# NAME
        # Alias name or pattern (repeatable); none lists every alias
        if bu_env_is_in_autocomplete && [[ "$1" != -* ]]
        then
            # Name positional: complete from registered alias names
            autocompletion=(--glob --ret __bu_bu_get_alias_complete_names ret-- --hint "Alias name or pattern")
        fi
        if [[ "$1" == -* ]]
        then
            bu_parse_error_enum "$1"
        else
            names+=("$1")
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
List the CLI's own registered aliases (type alias in bu get-command) as
{name, root, definition, synopsis} records. root is the first word of the
expansion — the command the alias maps to — so 'bu get-alias --root query-object'
answers which aliases map to a given command. For bash shell aliases (the
alias builtin), use bu get-shell-alias.
" \
        --example "All CLI aliases" "" \
        --example "Aliases for a command" "--root query-object" \
        --example "One alias" "gc" \
        --example "Aliases starting with g" "'g*'"
    return 0
fi

# Iterate the command registry, selecting type == alias. This reads the
# CLI's own alias table (BU_COMMANDS), never the bash alias builtin.
# Rows are built in this shell, not in the pipeline, so seen survives for
# the missing-name report.
local command
local _type
local _definition
local _root
local _synopsis
local -a rows=()
local -A seen=()
for command in "${!BU_COMMANDS[@]}"
do
    _type=${BU_COMMAND_PROPERTIES[$command,type]:-}
    [[ "$_type" == alias ]] || continue
    bu_glob_match "$command" "${names[@]}" || continue
    seen[$command]=1
    _definition=${BU_COMMANDS[$command]}
    _root=${_definition%% *}
    _synopsis=${BU_COMMAND_PROPERTIES[$command,synopsis]:-}
    [[ -z "$root" || "$_root" == $root ]] || continue
    rows+=("$command"$'\t'"$_root"$'\t'"$_definition"$'\t'"$_synopsis")
done
if ((${#rows[@]}))
then
    printf '%s\n' "${rows[@]}"
fi | sort | bu_out_from_tsv --columns name,root,definition,synopsis \
    | bu_out --format "$format"

local exit_code=0
bu_glob_report_missing alias seen "${names[@]}" || exit_code=1

bu_scope_pop_function
return "$exit_code"
}

# Completion helper: names of the CLI's registered aliases.
__bu_bu_get_alias_complete_names()
{
    BU_RET=()
    local c
    for c in "${!BU_COMMANDS[@]}"
    do
        [[ "${BU_COMMAND_PROPERTIES[$c,type]:-}" == alias ]] && BU_RET+=("$c")
    done
}

# Completion helper: distinct root commands of the CLI's registered aliases.
__bu_bu_get_alias_complete_roots()
{
    BU_RET=()
    local c _root
    local -A seen=()
    for c in "${!BU_COMMANDS[@]}"
    do
        [[ "${BU_COMMAND_PROPERTIES[$c,type]:-}" == alias ]] || continue
        _root=${BU_COMMANDS[$c]%% *}
        [[ -n "$_root" && -z "${seen[$_root]:-}" ]] || continue
        seen[$_root]=1
        BU_RET+=("$_root")
    done
}

__bu_bu_get_alias_main "$@"
