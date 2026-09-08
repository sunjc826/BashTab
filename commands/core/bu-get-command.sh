#!/usr/bin/env bash
# Pipeline: producer
# Dispatch: source
# Tab-Execute: true
# Synopsis: List registered commands and their properties
# Help-Topic: commands
# Fields: name verb noun namespace type definition synopsis fields stage input output requires module shadows shadowed_by
function __bu_bu_get_command_main()
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

# Note that we do not source bu_entrypoint inside the sourceable script template
# as it is assumed that sourceable scripts are sourced AFTER 
# bu_entrypoint has been sourced by the user.

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_scope_add_cleanup bu_popd_silent
bu_run_log_command "$@"

local verb_filter=
local noun_filter=
local namespace_filter=
local type_filter=
local is_allow_empty_verb=false
local is_allow_empty_noun=false
local is_allow_empty_namespace=false
local format=auto
local columns=
local is_all=false
local is_help=false
local error_msg=
local options_finished=false
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    -v|--verb)# VERB_FILTER
        # Glob pattern to filter by verb
        bu_parse_positional $# --enum "${!BU_COMMAND_VERBS[@]}" enum-- --hint "Command verb glob"
        verb_filter=${!shift_by}
        ;;
    +v|--allow-empty-verb)# _FLAG
        # If a command has no associated verb, it is also included in the results
        is_allow_empty_verb=true
        ;;
    -n|--noun)# NOUN_FILTER
        # Glob pattern to filter by noun
        bu_parse_positional $# --enum "${!BU_COMMAND_NOUNS[@]}" enum-- --hint "Command noun glob"
        noun_filter=${!shift_by}
        ;;
    +n|--allow-empty-noun)# _FLAG
        # If a command has no associated noun, it is also included in the results
        is_allow_empty_noun=true
        ;;
    -ns|--namespace)# NS_FILTER
        # Glob pattern to filter by namespace
        bu_parse_positional $# --enum "${!BU_COMMAND_NAMESPACES[@]}" enum-- --hint "Command namespace glob"
        namespace_filter=${!shift_by}
        ;;
    +ns|--allow-empty-namespace)# _FLAG
        # If a command has no associated namespace, it is also included in the results
        is_allow_empty_namespace=true
        ;;
    -t|--type)# TYPE_FILTER
        # Type of the command
        bu_parse_positional $# --enum function execute source alias enum-- --hint "Command type"
        bu_validate_positional "${!shift_by}"
        type_filter=${!shift_by}
        ;;
    --format)# FORMAT
        # Output format
        bu_parse_positional $# --enum "${BU_OUT_FORMATS[@]}" enum-- --hint "Output format"
        bu_validate_positional "${!shift_by}"
        format=${!shift_by}
        ;;
    -a|--all)# _FLAG
        # Include collision-parked (shadowed) commands from the qualified store
        is_all=true
        ;;
    --columns)# COLUMNS
        # Fields to display, in order (comma-separated)
        bu_parse_positional $# --delimited name verb noun namespace type definition synopsis fields stage input output requires module shadows shadowed_by delimited-- --hint "Comma-separated fields"
        columns=${!shift_by}
        ;;
    -h|--help)# _FLAG
        # Print help
        is_help=true
        ;;
    --)# _FLAG
        # Remaining options will be collected
        options_finished=true
        shift
        break
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
local remaining_options=("$@")
if bu_env_is_in_autocomplete
then
    bu_autocomplete
    return 0
fi

if "$is_help"
then
    bu_autohelp
    return 0
fi

local command
local command_verb
local command_noun
local command_namespace
local command_type

local filtered_commands=()
local -a sweep_commands=()
if "$is_all"
then
    sweep_commands=("${!BU_COMMANDS[@]}" "${!BU_COMMANDS_QUALIFIED[@]}")
else
    sweep_commands=("${!BU_COMMANDS[@]}")
fi

for command in "${sweep_commands[@]}"
do
    if [[ -n "$verb_filter" ]]
    then
        command_verb=${BU_COMMAND_PROPERTIES[$command,verb]}
        if ! { { [[ -z "$command_verb" ]] && "$is_allow_empty_verb" ; } || [[ "$command_verb" == $verb_filter ]] ; }
        then
            continue
        fi
    fi

    if [[ -n "$noun_filter" ]]
    then
        command_noun=${BU_COMMAND_PROPERTIES[$command,noun]}
        if ! { { [[ -z "$command_noun" ]] && "$is_allow_empty_noun" ; } || [[ "$command_noun" == $noun_filter ]] ; }
        then
            continue
        fi
    fi

    if [[ -n "$namespace_filter" ]]
    then
        command_namespace=${BU_COMMAND_PROPERTIES[$command,namespace]}
        if ! { { [[ -z "$command_namespace" ]] && "$is_allow_empty_namespace" ; } || [[ "$command_namespace" == $namespace_filter ]] ; }
        then
            continue
        fi
    fi

    if [[ -n "$type_filter" ]]
    then
        __bu_cli_command_type "$command"
        command_type=$BU_RET
        if [[ "$command_type" != "$type_filter" ]]
        then
            continue
        fi
    fi

    filtered_commands+=("$command")
done

# ── Phase 1: Build path→name mapping for file-backed commands ──
# Only scan files for types 'execute' and 'source' (function types have
# a function name as the value, not a file path; alias types have an
# expansion spec).
local -A path_to_name=()
local -a awk_file_list=()
for command in "${filtered_commands[@]}"
do
    __bu_cli_command_type "$command"
    local _ct=$BU_RET
    local _path=${BU_COMMANDS[$command]:-${BU_COMMANDS_QUALIFIED[$command]:-}}
    case "$_ct" in
    execute|source)
        if [[ -f "$_path" ]]
        then
            path_to_name[$_path]=$command
            awk_file_list+=("$_path")
        fi
        ;;
    esac
done

# ── Phase 2: Single awk pass to extract # Synopsis: headers ──
# Scans up to line 30 per file; first match wins.
# Values are extracted verbatim (no variable/command substitution).
local -A file_synopsis=()
if ((${#awk_file_list[@]}))
then
    while IFS=: read -r _fpath _syn
    do
        file_synopsis[$_fpath]=$_syn
    done < <(awk '
        FNR == 1 { found = 0 }
        !found && FNR <= 30 && /^#[[:space:]]*Synopsis:[[:space:]]/ {
            line = $0
            sub(/^#[[:space:]]*Synopsis:[[:space:]]*/, "", line)
            sub(/[[:space:]]+$/, "", line)
            print FILENAME ":" line
            found = 1
        }
    ' "${awk_file_list[@]}" 2>/dev/null)
fi

# ── Helper: longest prefix match for BU_OUT_PRODUCER_FIELDS /
#            BU_OUT_STAGE_EFFECT registries (keyed on "bu <cmd>"). ──
__bu_get_cmd_registry_lookup()
{
    local -n _registry=$1
    local _bu_key="bu $2"
    local _best_key= _best_len=0
    local _key
    for _key in "${!_registry[@]}"
    do
        if [[ "$_bu_key" == "$_key" || "$_bu_key" == "$_key "* || "$_key" == "$_bu_key "* ]] && (( ${#_key} > _best_len ))
        then
            _best_key=$_key
            _best_len=${#_key}
        fi
    done
    if [[ -n "$_best_key" ]]
    then
        BU_RET=${_registry[$_best_key]}
    else
        BU_RET=
    fi
}

# ── Phase 3: Emit TSV records (all schema columns) ──
# Columns: name verb noun namespace type definition synopsis fields stage
#          input output requires module shadows shadowed_by
# Default --columns for table projection is name,type,definition,synopsis
{
    for command in "${filtered_commands[@]}"
    do
        __bu_cli_command_type "$command"
        command_type=$BU_RET
        command_verb=${BU_COMMAND_PROPERTIES[$command,verb]:-}
        command_noun=${BU_COMMAND_PROPERTIES[$command,noun]:-}
        command_namespace=${BU_COMMAND_PROPERTIES[$command,namespace]:-}
        local command_module=${BU_COMMAND_PROPERTIES[$command,module]:-}

        # Synopsis precedence: registry → file scan → alias synthesis → empty
        local synopsis=${BU_COMMAND_PROPERTIES[$command,synopsis]:-}
        if [[ -z "$synopsis" ]]
        then
            local _cmd_path=${BU_COMMANDS[$command]:-${BU_COMMANDS_QUALIFIED[$command]:-}}
            case "$command_type" in
            execute|source)
                synopsis=${file_synopsis[$_cmd_path]:-}
                ;;
            alias)
                # Alias synopsis stays empty unless registered via --synopsis;
                # the expansion is now the first-class definition column.
                ;;
            esac
            # function type: stays empty unless registered
        fi

        # Fields: registry first (jc parsers, bu_register_output_fields),
        # then the command's `# Fields:` header.
        __bu_get_cmd_registry_lookup BU_OUT_PRODUCER_FIELDS "$command"
        local fields=$BU_RET
        if [[ -z "$fields" ]]
        then
            local _f_file=${BU_COMMANDS[$command]:-}
            if [[ -f "$_f_file" ]]
            then
                __bu_command_header_get "$_f_file" "Fields" fields
            fi
        fi

        # Stage + derived input/output from the # Pipeline: header (or the
        # registry cache populated by bu_register_stage_effect).
        local stage=
        __bu_out_stage_effect_lookup "$command" stage
        local input= output=
        if [[ -n "$stage" ]]
        then
            __bu_out_effect_io "$stage" "$command" input output
        fi

        # Fixed input contract (# Requires: header).
        local requires=
        local _req_file=${BU_COMMANDS[$command]:-}
        if [[ -f "$_req_file" ]]
        then
            __bu_command_header_get "$_req_file" "Requires" requires
        fi

        # Definition: BU_COMMANDS value (falling back to the qualified store
        # for --all collision-parked losers) — script path (execute/source),
        # function name (function), or expansion spec (alias).
        local definition=${BU_COMMANDS[$command]:-${BU_COMMANDS_QUALIFIED[$command]:-}}

        # shadows: the qualified name this command beat (winner only).
        local shadows=${BU_COMMAND_PROPERTIES[$command,shadows]:-}
        # shadowed_by: reverse link, derived only on qualified entries whose
        # bare sibling's shadows property points back at them.
        local shadowed_by=
        if [[ "$command" == :*:* ]]
        then
            local _shadow_bare=${command#:}
            _shadow_bare=${_shadow_bare#*:}
            if [[ "${BU_COMMAND_PROPERTIES[$_shadow_bare,shadows]:-}" == "$command" ]]
            then
                shadowed_by=$_shadow_bare
            fi
        fi

        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$command" "$command_verb" "$command_noun" "$command_namespace" \
            "$command_type" "$definition" "$synopsis" "$fields" "$stage" "$input" \
            "$output" "$requires" "$command_module" "$shadows" "$shadowed_by"
    done
} | sort | bu_out_from_tsv --columns name,verb,noun,namespace,type,definition,synopsis,fields,stage,input,output,requires,module,shadows,shadowed_by \
    | "$BU_OUT_JQ" -c '.shadows = (if .shadows == "" then null else .shadows end) | .shadowed_by = (if .shadowed_by == "" then null else .shadowed_by end)' \
    | bu_out --format "$format" --columns "${columns:-name,type,definition,synopsis}"


bu_scope_pop_function
}

__bu_bu_get_command_main "$@"
