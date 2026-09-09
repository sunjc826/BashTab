#!/usr/bin/env bash
# Pipeline: producer
# Fields: command compatible reason
# Dispatch: source
# Synopsis: Show platform compatibility information
function __bu_bu_get_compat_main()
{
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

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_scope_add_cleanup bu_popd_silent
bu_run_log_command "$@"

local is_refresh=false
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
    --refresh)# _FLAG
        # Force re-probe every --is-compatible script instead of using the cache
        is_refresh=true
        ;;
    --format)# FORMAT
        # Output format
        bu_parse_positional $# --enum ${BU_OUT_FORMATS[@]} enum-- --hint "Output format"
        format=${!shift_by}
        ;;
    --columns)# COLUMNS
        # Fields to display, in order (comma-separated)
        bu_parse_positional $# --delimited command compatible reason delimited-- --hint "Comma-separated fields"
        columns=${!shift_by}
        ;;
    -h|--help)# _FLAG
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
        --description "Check which gated commands are compatible with the current system.

Gated commands are those that declare --is-compatible in their script.
This command runs each check (or uses the warm cache) and reports the
results as a table.  Use --refresh to force a fresh probe." \
        --example "Default" "" \
        --example "Force refresh" "--refresh" \
        --example "JSON output" "--format json"
    return 0
fi

# Collect all gated commands: those in BU_COMMANDS + those in BU_COMMAND_UNAVAILABLE
# that have --is-compatible in their script.
local -a gated_commands=()
local cmd script_path
for cmd in "${!BU_COMMANDS[@]}"; do
    script_path=${BU_COMMANDS[$cmd]}
    if [[ -f "$script_path" ]] && grep -qE -- '--is-compatible[)"]' "$script_path" 2>/dev/null; then
        gated_commands+=("$cmd")
    fi
done
for cmd in "${!BU_COMMAND_UNAVAILABLE[@]}"; do
    # Already in the list? skip. Otherwise add.
    local already=false
    local c
    for c in "${gated_commands[@]}"; do
        [[ "$c" == "$cmd" ]] && already=true && break
    done
    if ! $already; then
        gated_commands+=("$cmd")
    fi
done

# Emit TSV: command, compatible, reason
{
    local cmd
    for cmd in "${gated_commands[@]}"; do
        local reason=
        local compatible=true

        # Check if already known unavailable from the cache
        if [[ -n "${BU_COMMAND_UNAVAILABLE[$cmd]:-}" ]]; then
            compatible=false
            reason=${BU_COMMAND_UNAVAILABLE[$cmd]}
        elif "$is_refresh"; then
            # Force re-probe
            local script_path=${BU_COMMANDS[$cmd]:-}
            if [[ -z "$script_path" ]]; then
                # Command exists only in UNAVAILABLE; find its script
                # Look through command search dirs
                local dir
                for dir in "${!BU_COMMAND_SEARCH_DIRS[@]}"; do
                    local candidate=$dir/bu-${cmd}.sh
                    if [[ -f "$candidate" ]]; then
                        script_path=$candidate
                        break
                    fi
                done
            fi
            if [[ -n "$script_path" && -f "$script_path" ]]; then
                if ! reason=$(BU_IS_COMPAT_PROBE=1 bash "$script_path" --is-compatible 2>&1); then
                    compatible=false
                fi
            else
                compatible=false
                reason="script not found"
            fi
        fi

        if "$compatible"; then
            printf '%s\t%s\t%s\n' "$cmd" "✓" ""
        else
            printf '%s\t%s\t%s\n' "$cmd" "✗" "$reason"
        fi
    done
} | sort | bu_out_from_tsv --columns command,compatible,reason \
  | bu_out --format "$format" ${columns:+--columns "$columns"}

bu_scope_pop_function
}

__bu_bu_get_compat_main "$@"
