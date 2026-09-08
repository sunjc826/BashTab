#!/usr/bin/env bash
# Pipeline: producer
# Dispatch: source
# Synopsis: Show bash shopt settings
# Fields: name value synopsis
function __bu_bu_get_shopt_option_main()
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
            # Name positional: complete from shopt option names
            autocompletion=(--ret __bu_bu_shopt_complete_names ret-- --hint "Option name")
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
List shopt shell options as records (bash's extended behavior switches).
Covers globstar, nullglob, dotglob, autocd, extglob, and ~50 more; each
record has name, value (boolean), and a one-line synopsis describing what
the option does. Runs in the current shell, so the values are the live
settings. Toggle them with bu set-shopt-option.

Site extension point: a site/*.sh file may declare the global associative
array BU_SHOPT_SYNOPSIS_OVERRIDES (option name → one-line synopsis) to
document distro-patched shopt options or reword a vanilla description;
entries merge over the built-in table. See site/README.md.
" \
        --example "All options" "" \
        --example "What is on right now" "" \
        --example "One option" "globstar"
    return 0
fi

# Static synopsis table: one-line condensed descriptions of each shopt
# option (stable since bash 4), noting surprising defaults. Options absent
# from this table get an empty synopsis — never an error — so the command
# stays forward-compatible with new bash releases.
local synopsis_table='{
  "assoc_expand_once": "Evaluate associative array subscripts once instead of twice (deprecated)",
  "autocd": "Treat a bare directory name as cd to that directory",
  "cdable_vars": "If the argument to cd is not a directory, treat it as a variable name",
  "cdspell": "Correct minor spelling errors in directory arguments to cd",
  "checkhash": "Check the hash table for a command existence before executing it",
  "checkjobs": "List stopped or running jobs and defer exit if any remain",
  "checkwinsize": "Check the window size after each command and update LINES and COLUMNS",
  "cmdhist": "Save multi-line commands to history as single lines",
  "compat31": "Change quoting and expansion behavior to match bash 3.1",
  "compat32": "Change quoting and expansion behavior to match bash 3.2",
  "compat40": "Change quoting and expansion behavior to match bash 4.0",
  "compat41": "Change quoting and expansion behavior to match bash 4.1",
  "compat42": "Change quoting and expansion behavior to match bash 4.2",
  "compat43": "Change quoting and expansion behavior to match bash 4.3",
  "compat44": "Change quoting and expansion behavior to match bash 4.4",
  "complete_fullquote": "Quote all shell metacharacters in completion matches; default on",
  "direxpand": "Filename completion replaces a directory name with the full match",
  "dirspell": "Correct minor spelling errors in directory names during completion",
  "dotglob": "Pathname expansion includes filenames beginning with a dot",
  "execfail": "A non-interactive shell does not exit if exec cannot run its file",
  "expand_aliases": "Expand aliases; default off in non-interactive shells",
  "extdebug": "Enable extended debugging with a DEBUG trap on every command",
  "extglob": "Enable extended pattern matching operators such as @(...) and +(...)",
  "extquote": "Allow ANSI-C and locale quoting inside double-quoted parameter expansions; default on",
  "failglob": "Patterns that match no filenames cause an expansion error",
  "force_fignore": "Completion ignores FIGNORE suffixes even if it would ignore everything; default on",
  "globasciiranges": "Bracket range expressions use ASCII (C locale) ordering; default on",
  "globskipdots": "Pathname expansion never matches dot or dot-dot; default on",
  "globstar": "Double-star matches files and zero or more directory levels recursively",
  "gnu_errfmt": "Error messages use the GNU file and line format",
  "histappend": "Append to the history file on exit instead of overwriting it",
  "histreedit": "Load a failed history substitution into the edit line for fixing",
  "histverify": "Load history substitutions for editing instead of executing them",
  "hostcomplete": "Attempt hostname completion for words containing an at-sign; default on",
  "huponexit": "Send SIGHUP to all jobs when an interactive login shell exits",
  "inherit_errexit": "Command substitutions inherit the errexit (set -e) setting",
  "interactive_comments": "Allow # to begin a comment in an interactive shell; default on",
  "lastpipe": "Run the last pipeline command in the current shell when job control is off",
  "lithist": "Save multi-line history entries with newlines instead of semicolons",
  "localvar_inherit": "Local variables inherit the value and attributes of same-named globals",
  "localvar_unset": "A variable unset as local stays unset in functions it calls",
  "login_shell": "Read-only; set when the shell is a login shell",
  "mailwarn": "Warn if the file checked for mail was accessed since the last check",
  "no_empty_cmd_completion": "Do not attempt completion on an empty command line",
  "nocaseglob": "Pathname expansion matches filenames case-insensitively",
  "nocasematch": "case and [[ matching is case-insensitive",
  "noexpand_translation": "Do not expand the text after a locale translation (deprecated)",
  "nullglob": "Patterns matching nothing expand to the empty string",
  "patsub_replacement": "Ampersand in pattern replacement expands to the matched text; default on",
  "progcomp": "Enable programmable completion facilities; default on",
  "progcomp_alias": "Expand aliases in the command name for programmable completion",
  "promptvars": "Prompt strings undergo parameter, command, and arithmetic expansion; default on",
  "restricted_shell": "Read-only; set when the shell runs in restricted mode",
  "shift_verbose": "shift prints an error if the count exceeds the number of arguments",
  "sourcepath": "source searches PATH when the filename is not found; default on",
  "varredir_close": "Automatically close brace-variable file descriptors opened for redirection",
  "xpg_echo": "echo expands backslash escape sequences by default"
}'

# Site extension point: BU_SHOPT_SYNOPSIS_OVERRIDES is an optional global
# associative array (option name → one-line synopsis) that site/*.sh files
# populate with `declare -A -g`. Entries merge OVER the static table so
# distro-patched options (e.g. Red Hat's downstream `syslog_history`) gain a
# description and a vanilla description can be reworded. Absent/empty map =
# byte-identical vanilla behavior. The merge is built with jq `--arg` (never
# string interpolation) so synopsis text containing quotes survives verbatim.
local synopsis_json=$synopsis_table
if declare -p BU_SHOPT_SYNOPSIS_OVERRIDES &>/dev/null && ((${#BU_SHOPT_SYNOPSIS_OVERRIDES[@]} > 0))
then
    local -a _so_jq_args=()
    local _so_key
    for _so_key in "${!BU_SHOPT_SYNOPSIS_OVERRIDES[@]}"
    do
        _so_jq_args+=(--arg "$_so_key" "${BU_SHOPT_SYNOPSIS_OVERRIDES[$_so_key]}")
    done
    synopsis_json=$(printf '%s' "$synopsis_table" | jq -c "${_so_jq_args[@]}" '. + $ARGS.named')
fi

# Runs sourced, so `shopt` reports the current shell's live settings
shopt | jq -R -c --arg name "$name" --argjson synopsis "$synopsis_json" '
    select(. != "")
    | capture("^(?<name>\\S+)\\s+(?<value>on|off)$")
    | select($name == "" or .name == $name)
    | .value |= (. == "on")
    | .synopsis = ($synopsis[.name] // "")
' | bu_out --format "$format"

bu_scope_pop_function
}

# Completion helper: valid shopt option names (shared with set-shopt-option).
__bu_bu_shopt_complete_names()
{
    BU_RET=()
    local o
    while IFS= read -r o
    do
        [[ -n "$o" ]] && BU_RET+=("$o")
    done < <(shopt | awk '{print $1}')
}

__bu_bu_get_shopt_option_main "$@"
