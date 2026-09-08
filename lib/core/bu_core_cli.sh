# bash-ide source=./bu_core_autocomplete.sh

# MARK: Top-level CLI
# ```
# *Description*:
# Sorts keys alphabetically
# *Params*:
# - stdin: Keys (space or line separated)
# *Returns*:
# - stdout: Sorted keys (one per line)
# ```
__bu_cli_sort_keys()
{
    tr ' ' '\n' | sort
}

# ```
# *Description*:
# Gets the properties of a bu sub-command
#
# *Params*
# - `$1`: bu sub-command
#
# *Returns*
# - `$BU_RET`: Properties of the command. One of `function`, `source`, `execute`, or `no-default-found`.
# ```
__bu_cli_command_type()
{
    local bu_command=$1
    local function_or_script_path=${BU_COMMANDS[$bu_command]:-}
    if [[ -z "$function_or_script_path" ]]
    then
        # Collision-parked losers live in the qualified side-store.
        function_or_script_path=${BU_COMMANDS_QUALIFIED[$bu_command]:-}
    fi
    if [[ -z "$function_or_script_path" ]]
    then
        # Also accept non bu command
        function_or_script_path=$bu_command
    fi
    local properties="${BU_COMMAND_PROPERTIES[$bu_command,type]:-}"
    if [[ -z "$properties" ]]
    then
        if bu_symbol_is_function "$function_or_script_path"
        then
            properties=function
        elif [[ -x "$function_or_script_path" ]]
        then
            properties=execute
        elif [[ -f "$function_or_script_path" ]]
        then
            properties=source
            # Fallback demotion: a plain file with no exec bit and no
            # declared dispatch intent is silently sourced into the caller.
            # Surface the ambiguity so it doesn't surface later as unrelated
            # breakage (cwd/env/PATH hijack).
            bu_log_warn "Command[$bu_command] at '$function_or_script_path' has no exec bit and no '# Dispatch: source' declaration; it is being sourced into the caller's shell. Add '# Dispatch: source' to declare mutating intent, or 'chmod +x' to run it as a separate process."
        else
            properties=no-default-found
        fi

        # Cache it
        BU_COMMAND_PROPERTIES[$bu_command,type]=$properties
    fi
    BU_RET=$properties
}

# ```
# *Description*:
# Format a command name with verb and noun colorized separately.
# When the command has parsed verb/noun properties, the verb is colored blue,
# the noun green, and the dash grey.  Otherwise the name is bold as-is.
# Output is a %b-ready string already padded to COLWIDTH visible characters.
#
# *Params*:
# - `$1`: command key
# - `$2`: column width (default 30)
#
# *Returns*: stdout: padded, colorized command name
# ```
__bu_cli_colorize_command_name()
{
    local -r key=$1
    local -r colw=${2:-30}
    local verb=${BU_COMMAND_PROPERTIES[$key,verb]:-}
    local noun=${BU_COMMAND_PROPERTIES[$key,noun]:-}
    local display

    if [[ -n "$verb" && -n "$noun" ]]
    then
        # Verb (bold blue), dash (grey), noun (bold green)
        display="${BU_TPUT_BOLD}${BU_TPUT_BLUE}${verb}${BU_TPUT_RESET}"
        display+="${BU_TPUT_GREY}-${BU_TPUT_RESET}"
        display+="${BU_TPUT_BOLD}${BU_TPUT_GREEN}${noun}${BU_TPUT_RESET}"
    else
        # Fallback: bold-only (no verb/noun split)
        display="${BU_TPUT_BOLD}${key}${BU_TPUT_RESET}"
    fi

    local visible_len=${#key}
    local padding=$((colw - visible_len))
    ((padding < 1)) && padding=1
    printf '%s%*s' "$display" "$padding" ''
}

# ```
# *Description*:
# Convert a readline key-binding escape sequence to a human-readable
# label (e.g. `\C-x` → `Ctrl-X`, `\ea` → `Alt-A`).
#
# *Params*:
# - `$1`: Raw key sequence as stored in BU_KEY_BINDINGS
#
# *Returns*: stdout: colored human-readable label
# ```
__bu_cli_format_keybinding()
{
    local -r raw=$1
    local label

    if [[ "$raw" == '\C-'* ]]
    then
        local chord=${raw#\\C-}
        case "$chord" in
        @) label='Ctrl-Space' ;;
        *)  label="Ctrl-${chord^^}" ;;
        esac
        printf '%s%s%s' "${BU_TPUT_BOLD}${BU_TPUT_YELLOW}" "$label" "${BU_TPUT_RESET}"
    elif [[ "$raw" == '\e'* ]]
    then
        local chord=${raw#\\e}
        label="Alt-${chord^^}"
        printf '%s%s%s' "${BU_TPUT_BOLD}${BU_TPUT_VIOLET}" "$label" "${BU_TPUT_RESET}"
    else
        printf '%s' "$raw"
    fi
}

# ```
# *Description*:
# Render the environment diagnostics section for the top-level help.
# Shows platform, bash version, key capability status, and a summary
# of any commands that are unavailable due to missing dependencies.
#
# *Params*: None
#
# *Returns*: None
# ```
__bu_cli_environment_section()
{
    local -r dim="${BU_TPUT_GREY}"
    local -r rst="${BU_TPUT_RESET}"
    local -r em="${BU_TPUT_BOLD}"
    local -r green="${BU_TPUT_GREEN}"
    local -r red="${BU_TPUT_RED}"
    local -r yellow="${BU_TPUT_YELLOW}"

    echo
    echo "${em}Environment${rst}"
    echo

    # Platform line
    local platform_display
    if [[ -n "${BU_PLATFORM_NAME:-}" ]]; then
        platform_display="${BU_PLATFORM_NAME}"
        if [[ -n "${BU_PLATFORM_ID:-}" ]]; then
            platform_display+=" ${dim}(${BU_PLATFORM_ID}"
            [[ -n "${BU_PLATFORM_FAMILY:-}" && "${BU_PLATFORM_FAMILY}" != "${BU_PLATFORM_ID}" ]] && \
                platform_display+=", ${BU_PLATFORM_FAMILY}"
            platform_display+=")${rst}"
        fi
    else
        platform_display="${dim}unknown${rst}"
    fi
    printf '  %-13s %b\n' 'Platform' "$platform_display"

    # Bash version
    printf '  %-13s %s\n' 'Bash' "${BASH_VERSION:-unknown}"

    # Capability table — key capabilities with check/cross
    local caps=(fzf jq node jc docker dpkg pacman)
    local cap label hint version_str

    for cap in "${caps[@]}"; do
        if [[ -n "${BU_CAP[$cap]:-}" ]]; then
            # Try to get a version string
            version_str=
            case "$cap" in
                fzf)    version_str=$(fzf --version 2>/dev/null | head -1) ;;
                jq)     version_str=$(jq --version 2>/dev/null | head -1) ;;
                node)   version_str=$(node --version 2>/dev/null | head -1) ;;
                jc)     version_str=$(jc --version 2>/dev/null | head -1) ;;
                docker) version_str=$(docker --version 2>/dev/null | head -1 | sed 's/Docker version //') ;;
                dpkg)   version_str=$(dpkg --version 2>/dev/null | head -1 | grep -oP '[0-9.]+' | head -1) ;;
                pacman) version_str=$(pacman --version 2>/dev/null | head -1 | grep -oP '[0-9.]+' | head -1) ;;
            esac
            local check="${green}✓${rst}"
            [[ -n "$version_str" ]] && check+=" ${dim}${version_str}${rst}"
            printf '  %-13s %b\n' "$cap" "$check"
        else
            bu_install_hint "$cap" 2>/dev/null || true
            local cross="${red}✗${rst}"
            if [[ -n "${BU_RET:-}" ]]; then
                cross+=" ${dim}— ${BU_RET}${rst}"
            fi
            printf '  %-13s %b\n' "$cap" "$cross"
        fi
    done

    # Tree-sitter status (derived, not a cap)
    if [[ -n "${BU_CAP[node]:-}" ]]; then
        if "${BU_AUTOCOMPLETE_USE_TREE_SITTER:-false}"; then
            printf '  %-13s %b\n' 'tree-sitter' "${green}✓${rst} ${dim}enabled${rst}"
        else
            printf '  %-13s %b\n' 'tree-sitter' "${dim}disabled${rst}"
        fi
    else
        printf '  %-13s %b\n' 'tree-sitter' "${red}✗${rst} ${dim}node not found${rst}"
    fi

    # Command availability summary
    local total=$((${#BU_COMMANDS[@]} + ${#BU_COMMAND_UNAVAILABLE[@]}))
    local available=${#BU_COMMANDS[@]}
    local -a unavailable_entries=()
    local cmd reason
    for cmd in "${!BU_COMMAND_UNAVAILABLE[@]}"; do
        reason=${BU_COMMAND_UNAVAILABLE[$cmd]}
        unavailable_entries+=("$cmd — $reason")
    done

    echo
    if ((total == available)); then
        printf '  %-13s %s/%s commands available\n' 'Commands' "$available" "$total"
    elif ((available == 0)); then
        printf '  %-13s %s/%s commands available\n' 'Commands' "${red}$available${rst}" "$total"
    else
        printf '  %-13s %s/%s commands available\n' 'Commands' "${yellow}$available${rst}" "$total"
        if ((${#unavailable_entries[@]} <= 5)); then
            local u
            for u in "${unavailable_entries[@]}"; do
                printf '  %-13s   %b\n' '' "${dim}— ${u}${rst}"
            done
        else
            printf '  %-13s   %b\n' '' "${dim}— ${#unavailable_entries[@]} commands unavailable${rst}"
        fi
    fi
    echo
}

# ```
# *Description*:
# Displays help information for the master command
#
# *Params*: None
#
# *Returns*: None
# ```
__bu_cli_help()
{
    local -r title="${BU_TPUT_BOLD}${BU_TPUT_DARK_BLUE}Help for ${BU_CLI_COMMAND_NAME}${BU_TPUT_RESET}"
    local -r dim="${BU_TPUT_GREY}"
    local -r rst="${BU_TPUT_RESET}"
    local -r em="${BU_TPUT_BOLD}"
    local -r ul="${BU_TPUT_UNDERLINE}"
    local -r cli=$BU_CLI_COMMAND_NAME

    echo "$title"
    echo
    echo "${em}${cli}${rst} is a ${em}Verb-Noun${rst} CLI with fzf-powered tab completion and a"
    echo "PowerShell-inspired JSONL object pipeline."
    echo
    echo "${em}Getting started${rst}"
    echo "  Type ${em}${cli}${rst} ${dim}<TAB>${rst} to explore commands in a fuzzy-search dropdown."
    echo "  Command names follow ${em}Verb-Noun${rst} — the verb is ${BU_TPUT_BOLD}${BU_TPUT_BLUE}blue${rst} and the"
    echo "  noun is ${BU_TPUT_BOLD}${BU_TPUT_GREEN}green${rst} in the listing below."
    echo "  Run ${em}${cli} <command> --help${rst} for details on any subcommand."
    echo
    echo "${em}Pipelines${rst}"
    echo "  Commands emit ${em}JSONL${rst} (one JSON object per line). Chain them with | :"
    echo "    ${dim}${cli} get-command | ${cli} where '.type == \"source\"' | ${cli} format-table${rst}"
    echo "  Or use classic Unix pipes — jq, awk, etc. work on the JSONL stream."
    echo
    # Teaser: list the LIVE key-binding registry (sorted, same order as the
    # full table below), so it never goes stale when defaults change or an
    # embedder overrides a chord.  Guarded on a non-empty registry.
    if ((${#BU_KEY_BINDINGS[@]}))
    then
        echo "${em}Key bindings${rst} (see bottom of this page for the full list)"
        local _kb_key _kb_label _kb_doc
        for _kb_key in $(__bu_cli_sort_keys <<<"${!BU_KEY_BINDINGS[*]}")
        do
            _kb_label=$(__bu_cli_format_keybinding "$_kb_key")
            _kb_doc=${BU_KEY_BINDING_DOCS[$_kb_key]:-${BU_KEY_BINDINGS[$_kb_key]}}
            printf '  %b  %s\n' "$_kb_label" "$_kb_doc"
        done
    fi

    # ── Environment diagnostics ──────────────────────────────────
    __bu_cli_environment_section

    local key value properties

    local -A executable_scripts=()
    local -A source_scripts=()
    local -A functions=()
    local -A aliases=()
    for key in "${!BU_COMMANDS[@]}"
    do
        value=${BU_COMMANDS[$key]}
        __bu_cli_command_type "$key"
        properties=$BU_RET
        case "$properties" in
        execute)
            executable_scripts[$key]=$value
            ;;
        source)
            source_scripts[$key]=$value
            ;;
        function)
            functions[$key]=$value
            ;;
        alias)
            aliases[$key]=$value
            ;;
        *)
            bu_log_warn "Unrecognized properties[$properties] for command[$key]"
            ;;
        esac
    done

    # Helper: emit tab-separated rows from a command array, then pipe
    # through bu_out_from_tsv -> bu_format_table for auto-width rendering.
    __bu_cli_emit_command_table()
    {
        local -n _arr=$1
        local _key _name _path _first=1
        for _key in $(__bu_cli_sort_keys <<<"${!_arr[*]}")
        do
            _path=${_arr[$_key]}
            _name=$(__bu_cli_colorize_command_name "$_key" 0)
            _name=${_name%"${_name##*[! ]}"}
            [[ -z "$_name" ]] && _name=$_key
            printf '%s	%s\n' "$_name" "$_path"
        done
    }

    # Helper: run a section header + sorted TSV through the table pipeline.
    __bu_cli_emit_command_section()
    {
        local -n _arr=$1
        local _header=$2
        ((${#_arr[@]})) || return 0
        echo
        echo "$_header"
        echo
        __bu_cli_emit_command_table "$1" \
        | bu_out_from_tsv --columns name,path \
        | bu_format_table --columns name,path
    }

    __bu_cli_emit_command_section executable_scripts \
        "The following commands using a ${BU_TPUT_UNDERLINE}new${BU_TPUT_RESET} shell context are available"

    __bu_cli_emit_command_section source_scripts \
        "The following commands using the ${BU_TPUT_UNDERLINE}current${BU_TPUT_RESET} shell context are available"

    __bu_cli_emit_command_section functions \
        "The following functions are available"

    __bu_cli_emit_command_section aliases \
        "The following aliases are available"

    # --- Key bindings ---
    if ((${#BU_KEY_BINDINGS[@]}))
    then
        echo
        echo "The following ${BU_TPUT_UNDERLINE}key bindings${BU_TPUT_NO_UNDERLINE} are available"
        echo
        {
            local _kb_key
            for _kb_key in $(__bu_cli_sort_keys <<<"${!BU_KEY_BINDINGS[*]}")
            do
                printf '%s	%s	%s	%s\n' \
                    "$(__bu_cli_format_keybinding "$_kb_key")" \
                    "${BU_KEY_BINDINGS[$_kb_key]}" \
                    "${BU_KEY_BINDING_MODULES[$_kb_key]:-}" \
                    "${BU_KEY_BINDING_DOCS[$_kb_key]:-}"
            done
        } | bu_out_from_tsv --columns chord,function,module,description \
          | bu_format_table --columns chord:Chord,function:Function,module:Module,description:Description
    fi
} >&2

# ```
# *Description*:
# Generates automatic help documentation for a CLI script
#
# *Params*:
# - `--description <description>`: Description of the script
# - `--example <purpose> <command-line>`: Example command line and its purpose. Can be specified multiple times.
#
# *Returns*: None
# ```
bu_autohelp()
{
    set +e
    bu_log_trace "bu_autohelp start"
    local description=
    local example_purposes=()
    local example_command_lines=()
    local shift_by
    while (($#))
    do
        shift_by=1
        case "$1" in
        --description)
            description=$2
            shift_by=2
            ;;
        --example)
            local purpose=$2
            local command_line=$3
            example_purposes+=("$purpose")
            example_command_lines+=("$command_line")
            shift_by=3
            ;;
        *)
            bu_log_unrecognized_option "$1"
            ;;
        esac
        if (( $# < shift_by ))
        then
            bu_log_err "Expected $((shift_by-1)) arguments for option $1"
        fi
        shift "$shift_by"
    done
    local script_path=${BASH_SOURCE[1]}
    bu_basename "$script_path"
    local script_name=$BU_RET

    local exit_code=0
    if [[ -n "$error_msg" ]]
    then
        bu_log_err "$error_msg"
        exit_code=1
    fi

    local command
    for command in "${!BU_COMMANDS[@]}"
    do
        if [[ "${BU_COMMANDS[$command]}" = "$script_path" ]]
        then
            break
        fi
    done

    if [[ "${BU_COMMANDS[${command:-}]:-}" != "$script_path" ]]
    then
        command=
    fi
    local padding=$'\t'
    local -a bu_script_options=()
    local -a bu_script_option_synopsis=()
    local -a bu_script_option_docs=()
    bu_log_trace "bu_autohelp before parse_case"
    eval "$(bu_autohelp_parse_case_block_help "${script_path}" "" "" "${BASH_LINENO[0]}")"
    bu_log_trace "bu_autohelp after parse_case"

    # ── Resolve static synopsis ──
    # Precedence: registry → file scan → alias synthesis → empty
    local autohelp_synopsis=${BU_COMMAND_PROPERTIES[$command,synopsis]:-}
    if [[ -z "$autohelp_synopsis" && -n "$command" ]]
    then
        local _ah_type
        __bu_cli_command_type "$command"
        _ah_type=$BU_RET
        case "$_ah_type" in
        execute|source)
            # Scan script_path (which is BU_COMMANDS[$command]) for # Synopsis:
            __bu_command_header_get "$script_path" "Synopsis" autohelp_synopsis
            ;;
        alias)
            autohelp_synopsis="alias for: ${BU_COMMANDS[$command]}"
            ;;
        esac
    fi

    printf '%s\n' "${BU_TPUT_BOLD}NAME${BU_TPUT_RESET}"
    printf "$padding%s\n" "${command:+$BU_CLI_COMMAND_NAME }${command}${command:+ - }${script_path}"
    if [[ -n "$autohelp_synopsis" ]]
    then
        printf "$padding%s\n" "$autohelp_synopsis"
    fi

    printf '\n%s\n\n' "${BU_TPUT_BOLD}SYNOPSIS${BU_TPUT_RESET}"
    
    local option
    local option_parameter_description
    printf '\t%s ' "${command:+$BU_CLI_COMMAND_NAME }${command:-$script_path}" 
    for i in "${!bu_script_options[@]}"
    do
        option=${bu_script_options[i]}
        option_parameter_description=${bu_script_option_synopsis[i]}
        option_parameter_description="${option_parameter_description#"${option_parameter_description%%[![:space:]]*}"}"
        option_parameter_description="${option_parameter_description%"${option_parameter_description##*[![:space:]]}"}"
        bu_script_option_synopsis[i]=$option_parameter_description
        if [[ "$option" == '*' ]]
        then
            # Positional catch-all: print the synopsis as an underlined argument
            printf '%s ' "${BU_TPUT_UNDERLINE}$option_parameter_description${BU_TPUT_NO_UNDERLINE}"
        else
            case "$option_parameter_description" in
            '')
                printf "[%s ?] " "${BU_TPUT_BOLD}$option${BU_TPUT_RESET}"
                ;;
            _FLAG)
                printf "[%s] " "${BU_TPUT_BOLD}$option${BU_TPUT_RESET}"
                ;;
            *)
                printf "[%s %s] " "${BU_TPUT_BOLD}$option${BU_TPUT_RESET}" "${BU_TPUT_UNDERLINE}$option_parameter_description${BU_TPUT_NO_UNDERLINE}" 
                ;;
            esac
        fi
    done
    printf "\n"

    if [[ -n "$description" ]]
    then
        printf '\n%s\n\n' "${BU_TPUT_BOLD}DESCRIPTION${BU_TPUT_RESET}"

        if [[ -n "$command" ]]
        then
            local namespace=${BU_COMMAND_PROPERTIES[$command,namespace]:-}
            local verb=${BU_COMMAND_PROPERTIES[$command,verb]:-}
            local noun=${BU_COMMAND_PROPERTIES[$command,noun]:-}
            printf "$padding%s\n" "Namespace: $namespace" "Verb: $verb" "Noun: $noun"
            echo
        fi  

        local -a description_lines
        mapfile -t description_lines < <(bu_gen_remove_empty_lines <<<"$description" | bu_gen_trim)
        printf "$padding%s\n" "${description_lines[@]}"
    fi

    # Pipeline context section: show the command's role in a JSONL pipeline
    if [[ -n "$command" ]]
    then
        local _plh_cmd_name="${BU_CLI_COMMAND_NAME} ${command}"
        local _plh_text=
        __bu_out_pipeline_help "$_plh_cmd_name" "$padding" _plh_text
        if [[ -n "$_plh_text" ]]
        then
            printf '\n%s\n\n' "${BU_TPUT_BOLD}PIPELINE${BU_TPUT_RESET}"
            printf '%s\n' "$_plh_text"
        fi
    fi

    printf '\n%s\n\n' "${BU_TPUT_BOLD}OPTIONS${BU_TPUT_RESET}"
    local i
    local option
    local option_docs
    for i in "${!bu_script_options[@]}"
    do
        option=${bu_script_options[i]}
        option_parameter_description=${bu_script_option_synopsis[i]}
        option_docs=${bu_script_option_docs[i]}

        if [[ "$option" == '*' ]]
        then
            # Positional catch-all: show synopsis as the name, labeled (positional)
            local _pos_name="${BU_TPUT_BOLD}${option_parameter_description}${BU_TPUT_RESET}"
            local _pos_label="${BU_TPUT_GREY}(positional)${BU_TPUT_RESET}"
            if [[ -z "$option_docs" ]]
            then
                printf "$padding%s %s (No additional help)\n\n" "$_pos_name" "$_pos_label"
            else
                printf "$padding%s %s\n$padding$padding%s\n" "$_pos_name" "$_pos_label" "${option_docs//$'\n'/$'\n'$padding$padding}"
            fi
        else
            option=${option//\|/${BU_TPUT_BLUE},${BU_TPUT_RESET}${BU_TPUT_BOLD}}

        case "$option_parameter_description" in
        '')
            option_parameter_description='?'
            ;;
        _FLAG)
            option_parameter_description=
            ;;
        *)
            ;;
        esac

        if [[ -z "$option_docs" ]]
        then
            printf "$padding%s%s (No additional help)\n\n" "${BU_TPUT_BOLD}$option${BU_TPUT_RESET}" "${option_parameter_description:+ ${BU_TPUT_UNDERLINE}$option_parameter_description${BU_TPUT_NO_UNDERLINE}}"
        else
            printf "$padding%s%s\n$padding$padding%s\n" "${BU_TPUT_BOLD}$option${BU_TPUT_RESET}" "${option_parameter_description:+ ${BU_TPUT_UNDERLINE}$option_parameter_description${BU_TPUT_NO_UNDERLINE}}" "${option_docs//$'\n'/$'\n'$padding$padding}"
        fi
        fi
    done

    if ((${#example_purposes[@]}))
    then
        printf "\n%s\n\n" "${BU_TPUT_BOLD}EXAMPLES${BU_TPUT_RESET}"

        __bu_cli_command_type "${script_path}"
        local opt_source=
        case "$BU_RET" in
        source) opt_source='source ';;
        esac

        local i
        for i in "${!example_purposes[@]}"
        do
            printf "$padding%s:\n\n" "${example_purposes[i]}"
            printf "$padding$padding%s %s\n\n" "${BU_TPUT_BOLD}\$ ${opt_source}${script_name}" "${example_command_lines[i]}${BU_TPUT_RESET}"
        done
    fi

    # SEE ALSO back-reference: point at this command's subsystem topic when
    # one is registered (explicit # Help-Topic: header, else parent dir).
    # Guarded with type -t so autohelp still works in stripped-down contexts
    # where the help-topic core was not sourced.
    if type -t bu_help_topic_for_script &>/dev/null
    then
        if bu_help_topic_for_script "$script_path"
        then
            local _see_also_topic=$BU_RET
            printf '\n%s\n\n' "${BU_TPUT_BOLD}SEE ALSO${BU_TPUT_RESET}"
            printf "$padding%s\n" "${BU_CLI_COMMAND_NAME} get-help ${_see_also_topic} (the ${_see_also_topic} subsystem topic)"
        fi
    fi

    bu_scope_pop_function 2>/dev/null || true
    return "$exit_code"
}

# ```
# *Description*:
# The top-level CLI command `$BU_CLI_COMMAND_NAME` (default `bu`)
#
# *Params*:
# - `$1`: Sub-command
# - `...`: All parameters are passed to the sub-command
#
# *Returns*:
# - Exit code of the sub-command
# ```
eval "$BU_CLI_COMMAND_NAME"'() { builtin source bu_impl.sh "$@"; }'

# Always define bu
if [[ "$BU_CLI_COMMAND_NAME" != bu ]]
then
    bu() { builtin source bu_impl.sh "$@"; }
fi


BU_ENUM_NAMESPACE_STYLE=(
    none # default
    prefix-keep
    powershell-keep
    prefix
    powershell
)
