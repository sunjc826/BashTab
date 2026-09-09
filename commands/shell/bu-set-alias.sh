#!/usr/bin/env bash
# Pipeline: transform
# Requires-All: name
# Fields: name definition set error
# Dispatch: source
# Synopsis: Register a new command alias
# Help-Topic: aliases
# Completion helper: defined alias names.
__bu_bu_set_alias_complete_names()
{
    BU_RET=()
    local a
    while IFS= read -r a
    do
        [[ -n "$a" ]] && BU_RET+=("$a")
    done < <(alias | sed -n "s/^alias \([^=]*\)=.*/\1/p")
}

function __bu_bu_set_alias_main()
{
set -e
local -r invocation_dir=$PWD
local script_name
local script_dir
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
script_dir=$PWD

if [[ -z "$COMP_CWORD" ]]
then
# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_DIR"/bu_entrypoint.sh
fi

bu_exit_handler_setup
bu_scope_push_function
bu_scope_add_cleanup bu_popd_silent
bu_run_log_command "$@"

local -a names=()
local -a definitions=()
local is_what_if=false
local format=auto
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --what-if)# _FLAG
        # Show what would happen without changing anything
        is_what_if=true
        ;;
    --format)# FORMAT
        # Output format
        bu_parse_positional $# --enum ${BU_OUT_FORMATS[@]} enum-- --hint "Output format"
        format=${!shift_by}
        ;;
    --name)# NAME
        # Alias name (repeatable)
        bu_parse_positional $# --ret __bu_bu_set_alias_complete_names ret-- --hint "Alias name"
        names+=("${!shift_by}")
        ;;
    --definition)# DEFINITION
        # Alias definition (repeatable; pairs with --name by position)
        bu_parse_positional $# --hint "Alias definition (shell command)"
        definitions+=("${!shift_by}")
        ;;
    -h|--help)# _FLAG
        # Print help
        is_help=true
        ;;
    *)
        if bu_env_is_in_autocomplete && [[ "$1" != -* ]]
        then
            if ((${#names[@]} == ${#definitions[@]}))
            then
                autocompletion=(--ret __bu_bu_set_alias_complete_names ret-- --hint "Alias name")
            else
                autocompletion=(--hint "Alias definition")
            fi
            bu_autocomplete
            return 0
        fi
        if ((${#names[@]} == ${#definitions[@]}))
        then
            names+=("$1")
        else
            definitions+=("$1")
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
Set shell aliases (PowerShell Set-Alias analog, structured alias).
Runs sourced in the current shell. Unmatched names get the last-seen
definition. Emits one record per alias.

Accepts pipeline input from get-shell-alias (reads .name and .definition fields).
" \
        --example "Simple alias" "ll 'ls -la'" \
        --example "Named flags" "--name gs --definition 'git status'" \
        --example "Pipeline from get-shell-alias" ""
    return 0
fi

# Pipeline input: when no names are given and stdin is a pipe,
# read JSONL records and extract .name and .definition.
if ((${#names[@]} == 0)) && [[ ! -t 0 ]]
then
    local _name _def
    while IFS=$'\t' read -r _name _def
    do
        [[ -n "$_name" ]] || continue
        names+=("$_name")
        definitions+=("${_def:-}")
    done < <(jq -r '[.name, (.definition // "")] | @tsv' 2>/dev/null)
fi

# Align names and definitions: if more names than defs, last def repeats.
if ((${#names[@]} == 0))
then
    error_msg="Missing required alias name (e.g. bu set-alias ll 'ls -la')"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

local records_file
records_file=$(mktemp)
bu_scope_add_cleanup rm -f "$records_file"

local rc=0
local i name definition
{
    for i in "${!names[@]}"
    do
        name=${names[$i]}
        definition=${definitions[$i]:-}
        if "$is_what_if"
        then
            bu_log_info "What if: alias $name=${definition@Q}"
            continue
        fi
        if alias "$name"="$definition" 2>/dev/null
        then
            bu_out_record name="$name" definition="$definition" set:=true
        else
            bu_out_record name="$name" definition="$definition" set:=false error="alias failed (invalid name)"
            rc=1
        fi
    done
} > "$records_file"

bu_out --format "$format" < "$records_file"

bu_scope_pop_function
return $rc
}

__bu_bu_set_alias_main "$@"
