#!/usr/bin/env bash
# Pipeline: producer
# Dispatch: source
# Synopsis: Show bash shell options (set -o)
# Fields: name value synopsis
function __bu_bu_get_shell_option_main()
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
            # Name positional: complete from set -o option names
            autocompletion=(--ret __bu_bu_shell_option_complete_names ret-- --hint "Option name")
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
List set -o shell options as records (the $ErrorActionPreference-style switches of bash).
Covers errexit, nounset, pipefail, xtrace, and friends; each record has
name, value (boolean), and a one-line synopsis describing what the option
does (including the set short-flag equivalent where one exists). Runs in
the current shell, so the values are the live settings. Toggle them with
bu set-shell-option.
" \
        --example "All options" "" \
        --example "Options currently off" "" \
        --example "One option" "pipefail"
    return 0
fi

# Static synopsis table: one-line condensed descriptions of each set -o
# option (stable since bash 4), including the set short-flag equivalent
# where one exists, and noting surprising defaults. igncr is Cygwin/MinGW
# only. Options absent from this table get an empty synopsis — never an
# error — so the command stays forward-compatible with new bash releases.
local synopsis_table='{
  "allexport": "Export all subsequently defined variables and functions to the environment (set -a)",
  "braceexpand": "Perform brace expansion on words (set -B); default on",
  "emacs": "Use Emacs-style command line editing",
  "errexit": "Exit on any command failure (set -e)",
  "errtrace": "Inherit the ERR trap in functions, command substitutions, and subshells (set -E)",
  "functrace": "Inherit DEBUG and RETURN traps in functions, command substitutions, and subshells (set -T)",
  "hashall": "Remember command locations for faster lookup (set -h); default on",
  "histexpand": "Perform history expansion using ! (set -H)",
  "history": "Enable command history",
  "ignoreeof": "Do not exit on end-of-file; type exit instead",
  "interactive-comments": "Allow # to begin a comment in an interactive shell; default on",
  "keyword": "Put assignment arguments in the environment of a simple command (set -k)",
  "monitor": "Enable job control (set -m)",
  "noclobber": "Refuse to overwrite files with > redirection (set -C)",
  "noexec": "Read commands without executing them (set -n)",
  "noglob": "Disable pathname expansion (set -f)",
  "nolog": "Currently ignored; reserved for a historical feature",
  "notify": "Report terminated background jobs immediately (set -b)",
  "nounset": "Treat unset variables as an error when expanding (set -u)",
  "onecmd": "Exit after reading and executing one command (set -t)",
  "physical": "cd/pwd use the physical directory structure, resolving symlinks (set -P)",
  "pipefail": "Pipeline exit status is the last non-zero exit, not the last command",
  "posix": "Match the POSIX standard where bash defaults differ",
  "privileged": "Do not read environment files for the privileged user (set -p)",
  "verbose": "Echo each command line as it is read (set -v)",
  "vi": "Use vi-style command line editing",
  "xtrace": "Trace each command before executing it (set -x)",
  "igncr": "Ignore carriage returns in input (Cygwin and MinGW bashes)"
}'

# Runs sourced, so `set -o` reports the current shell's live settings
set -o | jq -R -c --arg name "$name" --argjson synopsis "$synopsis_table" '
    select(. != "")
    | capture("^(?<name>\\S+)\\s+(?<value>on|off)$")
    | select($name == "" or .name == $name)
    | .value |= (. == "on")
    | .synopsis = ($synopsis[.name] // "")
' | bu_out --format "$format"

bu_scope_pop_function
}

# Completion helper: valid set -o option names (shared with set-shell-option).
__bu_bu_shell_option_complete_names()
{
    BU_RET=()
    local o
    while IFS= read -r o
    do
        [[ -n "$o" ]] && BU_RET+=("$o")
    done < <(set -o | awk '{print $1}')
}

__bu_bu_get_shell_option_main "$@"
