# Instead of implementing bu directly in a function, we place it in this script
# so that BASH_LINENO is relative to the file rather than relative to the start of the function

# shellcheck source=../core/bu_core_autocomplete.sh
source "$BU_NULL"
__bu_impl_process_alias()
{
    # Note: NOT readonly — bash 4.4 aborts on re-declaring a readonly
    # array local in a recursive call (alias-of-alias chain)
    local bu_alias_spec=($1)
    shift

    local -r bu_command=${bu_alias_spec[0]}
    local -r function_or_script_path=${BU_COMMANDS[$bu_command]}

    local exit_code=0

    local resolved_options=()

    local i=0
    local arg
    for arg in "${bu_alias_spec[@]:1}"
    do
        case "$arg" in
        '{?}')
            if ((!$#))
            then
                break
            fi
            ;;
        '{}')
            resolved_options+=("$1")
            if ((!$#))
            then
                bu_log_err "Insufficient arguments provided to satisfy ${BU_TPUT_BOLD}${BU_CLI_COMMAND_NAME} ${bu_alias_spec[*]:0:i+1} ${BU_TPUT_UNDERLINE}{REQUIRED}${BU_TPUT_NO_UNDERLINE} ${bu_alias_spec[*]:i+2}${BU_TPUT_RESET}"
                return 1
            fi
            shift
            ;;
        '{...}')
            resolved_options+=("$@")
            shift $#
            ;;
        *)
            resolved_options+=("$arg")
            ;;
        esac
        : "$((i++))"
    done

    
    __bu_cli_command_type "$bu_command"
    local -r type=$BU_RET
    BU_RET=()
    case "$type" in
    execute)
        BU_RET=("$function_or_script_path" "${resolved_options[@]}")
        ;;
    source)
        BU_RET=(builtin source "$function_or_script_path" "${resolved_options[@]}")
        ;;
    function)
        BU_RET=("$function_or_script_path" "${resolved_options[@]}")
        ;;
    alias)
        __bu_impl_process_alias "$function_or_script_path" "${resolved_options[@]}"
        ;;
    *)
        bu_log_err "Invalid aliased command[$bu_command] properties[$type]"
        return 1
        ;;
    esac
    return 0
}

__bu_impl()
{
    # Complete deferred command scan on first by-name dispatch.
    bu_ensure_command_scan

    if ((!$#))
    then
        bu_log_warn "No arguments specified, printing help"
        __bu_cli_help
        return
    fi
    # We expect the following values of BASH_SOURCE and FUNCNAME if bu was invoked directly on the command line:
    # .../lib/binsrc/bu_impl.sh .../lib/binsrc/bu_impl.sh ./lib/core/bu_core_cli.sh
    # __bu_impl                 source                    bu
    # Thus the depth of BASH_SOURCE would be 3 if the command is invoked directly
    # We will only write direct invocations to $BU_HISTORY to avoid spam. 
    if (( ${#BASH_SOURCE[@]} <= 3 ))
    then
        {
            printf "%q " "$BU_CLI_COMMAND_NAME" "$@"
            echo
        } >> "$BU_HISTORY"
        mapfile -t BU_RET <"$BU_HISTORY"
        if (( "${#BU_RET[@]}" > 1000 ))
        then
            bu_sync_cycle_file "$BU_HISTORY" false 500 true
        fi
    fi

    local -r bu_command_raw=$1
    shift
    # Note: NOT readonly — bash 4.4 aborts when a source-type command
    # sourced from this scope re-declares 'remaining_options' locally
    local remaining_options=("$@")

    # Settle any deferred --is-compatible probe for the raw command name
    # before resolving it, so a failed probe lands in the "known but
    # unavailable" branch below (which reports the reason and reprobes).
    bu_cap_ensure_compat "$bu_command_raw"

    # Resolve namespace-qualified commands: :<ns>:<verb-noun>
    local bu_command=$bu_command_raw
    local function_or_script_path=
    if [[ "$bu_command_raw" == :*:* ]]
    then
        local ns_name=${bu_command_raw#:}
        ns_name=${ns_name%%:*}
        local ns_prefix=":$ns_name:"
        local ns_cmd=${bu_command_raw#$ns_prefix}
        local cmd
        for cmd in "${!BU_COMMANDS[@]}"
        do
            if [[ "${BU_COMMAND_PROPERTIES[$cmd,namespace]}" == "$ns_name" ]] \
               && [[ "$cmd" == "$ns_cmd" ]]
            then
                function_or_script_path=${BU_COMMANDS[$cmd]}
                bu_command=$cmd
                break
            fi
        done
        if [[ -z "$function_or_script_path" ]]
        then
            # Fall back to the qualified side-store (a collision-parked loser).
            # Read-only: never write the resolved definition back into
            # BU_COMMANDS, or the parked loser would become a bare-name
            # claimant on first use.
            function_or_script_path=${BU_COMMANDS_QUALIFIED[$bu_command_raw]:-}
        fi
        if [[ -z "$function_or_script_path" ]]
        then
            bu_log_err "Command not found in namespace[$ns_name]: $ns_cmd"
            __bu_cli_help
            return 1
        fi
    else
        function_or_script_path=${BU_COMMANDS[$bu_command_raw]}
        if [[ -z "$function_or_script_path" ]] && [[ -n "${BU_COMMAND_UNAVAILABLE[$bu_command_raw]:-}" ]]
        then
            # Command is known but unavailable — try to re-probe
            if bu_cap_reprobe_unavailable "$bu_command_raw"
            then
                function_or_script_path=${BU_COMMANDS[$bu_command_raw]}
                bu_command=$bu_command_raw
            else
                bu_log_err "Command[$bu_command_raw] is unavailable: ${BU_COMMAND_UNAVAILABLE[$bu_command_raw]}"
                return 1
            fi
        fi
    fi
    __bu_cli_command_type "$bu_command"
    local -r type=$BU_RET
    local exit_code=0
    case "$type" in
    execute)
        "$function_or_script_path" "${remaining_options[@]}"
        exit_code=$?
        ;;
    source)
        builtin source "$function_or_script_path" "${remaining_options[@]}"
        exit_code=$?
        ;;
    function)
        "$function_or_script_path" "${remaining_options[@]}"
        exit_code=$?
        ;;
    alias)
        # A sole --help/-h addressed to the alias itself is a help request,
        # not slot data. Short-circuit before slot splicing: print the
        # expansion, then dispatch --help to the root command (first word of
        # the expansion) so the user lands on the real flag documentation.
        # Alias-of-alias chains re-enter this arm naturally via that dispatch.
        local _alias_root_cmd=${function_or_script_path%% *}
        if (( $# == 1 )) && { [[ "$1" == "--help" || "$1" == "-h" ]]; }
        then
            printf '%s\n' "${BU_TPUT_BOLD}ALIAS${BU_TPUT_RESET}"
            printf '%s %s => %s %s\n\n' \
                "$BU_CLI_COMMAND_NAME" "$bu_command" \
                "$BU_CLI_COMMAND_NAME" "$function_or_script_path"
            __bu_impl "$_alias_root_cmd" --help
            exit_code=$?
            return "$exit_code"
        fi
        # Settle a deferred --is-compatible probe on the alias root command
        # before expanding the alias: alias execution does not round-trip
        # through the top-level lookup, so without this an incompatible gated
        # command behind an alias would execute unprobed.
        bu_cap_ensure_compat "$_alias_root_cmd"
        if [[ -z "${BU_COMMANDS[$_alias_root_cmd]:-}" && -n "${BU_COMMAND_UNAVAILABLE[$_alias_root_cmd]:-}" ]]
        then
            bu_log_err "Command[$_alias_root_cmd] is unavailable: ${BU_COMMAND_UNAVAILABLE[$_alias_root_cmd]}"
            return 1
        fi
        if ! __bu_impl_process_alias "$function_or_script_path" "$@"
        then
            bu_log_err "Processing of alias[$bu_command] failed"
            return 1
        fi
        "${BU_RET[@]}"
        exit_code=$?
        ;;
    *)
        bu_log_err "Invalid command[$bu_command] properties[$type]"
        __bu_cli_help
        return 1
        ;;
    esac

    return "$exit_code"
}

__bu_impl "$@"
