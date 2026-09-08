# bash-ide source=./bu_core_base.sh
# bash-ide source=./bu_core_autocomplete.sh
# bash-ide source=./bu_core_cli.sh


# ```
# *Description*:
# Register a user-defined key binding for the shell
#
# *Params*:
# - `$1`: Key binding (e.g. `\ee`, `\eg`)
# - `$2`: Command or function name to bind to the key
# - `$3` (optional): Human-readable description shown in `bu` help
#
# *Returns*: None
#
# *Examples*:
# ```bash
# bu_preinit_register_user_defined_key_binding '\em' my_custom_command
# bu_preinit_register_user_defined_key_binding '\em' my_custom_command "My description"
# ```
#
# *Notes*:
# - This adds the binding to the `${BU_KEY_BINDINGS[@]}` associative array, which is later passed to `bind -x`
# - An optional third argument sets a human-readable description shown in `bu` help
# - When BU_CURRENT_MODULE is non-empty (i.e. registered from a module preinit
#   callback), the owning module is stamped in BU_KEY_BINDING_MODULES so the
#   help table can attribute the binding.
# ```
bu_preinit_register_user_defined_key_binding()
{
    local -r key=$1
    local -r binding=$2
    BU_KEY_BINDINGS[$key]=$binding
    if [[ -n "${BU_CURRENT_MODULE:-}" ]]
    then
        BU_KEY_BINDING_MODULES[$key]=$BU_CURRENT_MODULE
    fi
    if (($# >= 3))
    then
        BU_KEY_BINDING_DOCS[$key]=$3
    fi
}

# ```
# *Description*:
# Register a command-line transform (a `match -> replace` rewrite rule over
# READLINE_LINE).  See docs/line_transforms.md.
#
# *Params*:
# - `$1`: transform name
# - `--match <template>`: match template (required)
# - `--replace <template>`: replace template (required)
# - `--description <text>`: human-readable description
#
# *Returns*:
# - 0 on success, 1 on invalid rule or missing arguments
#
# *Notes*:
# - The rule is validated against the grammar; a matching auto-inverse is
#   derived and registered as `unwrap-<name>` (or `<name>-inverse`) when the
#   swapped rule is itself valid.
# - The owning module is stamped in BU_LINE_TRANSFORM_PROPERTIES so `bu
#   get-transform` can attribute the entry.
# ```
bu_preinit_register_line_transform()
{
    local -r name=$1
    shift
    local match= replace= description=
    while (($#))
    do
        case "$1" in
        --match)
            match=$2
            shift 2
            ;;
        --replace)
            replace=$2
            shift 2
            ;;
        --description)
            description=$2
            shift 2
            ;;
        *)
            bu_log_err "bu_preinit_register_line_transform: unrecognized option $1"
            shift
            ;;
        esac
    done
    if [[ -z "$name" || -z "$match" || -z "$replace" ]]
    then
        bu_log_err "bu_preinit_register_line_transform: name, --match and --replace are required"
        return 1
    fi

    __bu_transform_validate "$name" "$match" "$replace" || return 1

    local module=${BU_CURRENT_MODULE:-bu}
    BU_LINE_TRANSFORM_PROPERTIES[$name,match]=$match
    BU_LINE_TRANSFORM_PROPERTIES[$name,replace]=$replace
    BU_LINE_TRANSFORM_PROPERTIES[$name,description]=$description
    BU_LINE_TRANSFORM_PROPERTIES[$name,derived]=false
    BU_LINE_TRANSFORM_PROPERTIES[$name,module]=$module

    # Auto-derive the inverse as its own transform when the swapped rule is
    # also valid (per the spec: inverses are just transforms).
    local inv_name
    if [[ "$name" == wrap-* ]]
    then
        inv_name="unwrap-${name#wrap-}"
    else
        inv_name="${name}-inverse"
    fi
    if __bu_transform_validate "$inv_name" "$replace" "$match" quiet
    then
        BU_LINE_TRANSFORM_PROPERTIES[$inv_name,match]=$replace
        BU_LINE_TRANSFORM_PROPERTIES[$inv_name,replace]=$match
        BU_LINE_TRANSFORM_PROPERTIES[$inv_name,description]="Inverse of $name"
        BU_LINE_TRANSFORM_PROPERTIES[$inv_name,derived]=true
        BU_LINE_TRANSFORM_PROPERTIES[$inv_name,module]=$module
    fi
    return 0
}

# ```
# *Description*:
# Register a user-defined completion function for a command
#
# *Params*:
# - `$1`: Command name to register completion for
# - `$2`: Completion function name to associate with the command
#
# *Returns*: None
#
# *Examples*:
# ```bash
# bu_preinit_register_user_defined_completion_func mycmd my_completion_func
# ```
#
# *Notes*:
# - This adds the mapping to the `BU_AUTOCOMPLETE_COMPLETION_FUNCS` associative array, which is later passed to `complete -F`
# ```
bu_preinit_register_user_defined_completion_func()
{
    local completion_command=$1
    local completion_func=$2
    BU_AUTOCOMPLETE_COMPLETION_FUNCS[$completion_command]=$completion_func
}

# ```
# *Description*:
# Register a directory containing user-defined subcommands
#
# *Params*:
# - `$1`: Directory path containing subcommand scripts
# - `...` (optional): Conversion function to convert file names to command names.
#   The callback receives the file path (relative to the search dir) and
#   returns one of three codes:
#     0 — use BU_RET as the command name
#     1 — keep the default name (file name without .sh extension)
#     2 — REJECT: skip this file entirely, do not register it
#
# *Returns*:
# - Exit code 0 on success, 1 if directory does not exist
#
# *Examples*:
# ```bash
# bu_preinit_register_user_defined_subcommand_dir /path/to/commands bu_convert_file_to_command_namespace prefix
# ```
#
# *Notes*:
# - The directory is added to `BU_COMMAND_SEARCH_DIRS` for dynamic command discovery. New commands can be added by re-sourcing the init script.
# - If `<dir>/.bashtabignore` exists, it is read as glob patterns (one per
#   line, # comments and blank lines ignored). Files whose path-relative-to-dir
#   or basename match any pattern are skipped.
# - If no conversion function is provided, file names are used as-is (after removing .sh extension)
# ```
bu_preinit_register_user_defined_subcommand_dir()
{
    local dir=$1
    shift
    local convert_file_to_command=
    if (($#))
    then
        printf -v convert_file_to_command '%q ' "$@"
    fi

    bu_realpath "$dir"
    dir=$BU_RET

    if [[ ! -d "$dir" ]]
    then
        bu_log_warn "dir[$dir] does not exist"
        return 1
    fi

    BU_COMMAND_SEARCH_DIRS[$dir]=$convert_file_to_command
    if [[ -n "${BU_CURRENT_MODULE:-}" ]]
    then
        BU_COMMAND_SEARCH_DIR_MODULE[$dir]=$BU_CURRENT_MODULE
    fi
}

# ```
# *Description*:
# Stamp the owning module onto a registered command.  When the command's
# namespace is empty (no filename-converter namespace), default it to the
# module name and add the name to the namespace set, so `:<module>:`
# namespace-qualified dispatch works for converter-less module commands.
#
# *Params*:
# - `$1`: command name
# - `$2`: owning module name
# ```
__bu_stamp_command_module()
{
    local command=$1
    local module=$2
    BU_COMMAND_PROPERTIES[$command,module]=$module
    if [[ -z "${BU_COMMAND_PROPERTIES[$command,namespace]:-}" ]]
    then
        BU_COMMAND_PROPERTIES[$command,namespace]=$module
        BU_COMMAND_NAMESPACES[$module]=1
    fi
}

# ```
# *Description*:
# Resolve the precedence rank for a module name.  Lower rank wins the bare
# command name.  Rank 0 = no module (interactive/session registration, beats
# everything); unranked modules default to 500; the framework ("bu") is
# pinned at 900 via BU_MODULE_RANK's declaration.
#
# *Params*:
# - `$1`: module name (may be empty)
#
# *Returns*:
# - BU_RET: numeric rank
# ```
__bu_module_rank()
{
    local -r m=$1
    if [[ -z "$m" ]]
    then
        BU_RET=0
    else
        BU_RET=${BU_MODULE_RANK[$m]:-500}
    fi
    return 0
}

# ```
# *Description*:
# Single write funnel for the command registry.  Every definition write goes
# through here so that registering a definition always settles its dispatch
# type — the (BU_COMMANDS, BU_COMMAND_PROPERTIES[,type]) pair can never
# disagree the way it did when each write site maintained its own consistency
# rules (a stale cached type surviving a definition rewrite).
#
# Name collisions across DIFFERENT modules are legal and non-destructive: the
# lower-rank module keeps the bare name (ties keep the incumbent), the loser
# is parked in BU_COMMANDS_QUALIFIED under `:<module>:<name>` and stays
# dispatchable via the qualified spelling.  Same-module re-registration is an
# ordinary overwrite (a rescan), and string-identical definitions never warn.
#
# *Params*:
# - `$1`: command name
# - `$2`: definition (script path | function name | alias spec string)
# - `--type T`: write this exact dispatch type (caller already knows it —
#   alias registration passes `alias`; the function/file helpers pass an
#   explicit type argument when one was given).
# - `--settle-from-file PATH`: definition is a script file — write the type
#   from the file's `# Dispatch:` header, else UNSET any cached type so the
#   lazy derivation runs fresh on next dispatch.
# - `--module M`: stamp the owning module (defaults to `BU_CURRENT_MODULE`;
#   an explicitly-passed empty module suppresses stamping rather than falling
#   back to the default).
#
# *Returns*: None
# ```
__bu_command_register()
{
    local -r name=$1
    local -r definition=$2
    shift 2

    local type=
    local settle_file=
    local module=
    local has_module=false

    while (($#))
    do
        case "$1" in
        --type)
            type=$2
            shift 2
            ;;
        --settle-from-file)
            settle_file=$2
            shift 2
            ;;
        --module)
            module=$2
            has_module=true
            shift 2
            ;;
        *)
            bu_log_err "__bu_command_register: unrecognized option $1"
            shift
            ;;
        esac
    done

    # ── Resolve owning module (default BU_CURRENT_MODULE; explicit empty suppresses)
    if ! "$has_module"
    then
        module=${BU_CURRENT_MODULE:-}
    fi

    # ── Collision handling (different module, different definition) ──
    local incumbent_def=${BU_COMMANDS[$name]:-}
    if [[ -n "$incumbent_def" && "$incumbent_def" != "$definition" ]]
    then
        local incumbent_module=${BU_COMMAND_PROPERTIES[$name,module]:-}
        if [[ "$incumbent_module" != "$module" ]]
        then
            local new_rank inc_rank
            __bu_module_rank "$module"
            new_rank=$BU_RET
            __bu_module_rank "$incumbent_module"
            inc_rank=$BU_RET

            if (( new_rank >= inc_rank ))
            then
                # Ties keep the incumbent: park the NEWCOMER in the qualified
                # store, leave the bare entry untouched, and return.
                local qualified=":$module:$name"
                BU_COMMANDS_QUALIFIED[$qualified]=$definition
                if [[ -n "$type" ]]
                then
                    BU_COMMAND_PROPERTIES[$qualified,type]=$type
                elif [[ -n "$settle_file" ]]
                then
                    local park_decl
                    __bu_command_dispatch_decl "$settle_file"
                    park_decl=$BU_RET
                    if [[ -n "$park_decl" ]]
                    then
                        BU_COMMAND_PROPERTIES[$qualified,type]=$park_decl
                    fi
                fi
                if [[ -n "$module" ]]
                then
                    BU_COMMAND_PROPERTIES[$qualified,module]=$module
                    BU_COMMAND_PROPERTIES[$qualified,namespace]=$module
                fi
                BU_COMMAND_PROPERTIES[$name,shadows]=$qualified
                bu_log_warn "Command collision: [$name] is registered by module[$incumbent_module] (rank $inc_rank) and module[$module] (rank $new_rank); keeping [$incumbent_module] on the bare name and parking [$module] at $qualified"
                return 0
            fi

            # Newcomer outranks the incumbent: demote the INCUMBENT into the
            # qualified store, then fall through to the normal registration.
            local qualified=":$incumbent_module:$name"
            BU_COMMANDS_QUALIFIED[$qualified]=$incumbent_def
            local inc_type=${BU_COMMAND_PROPERTIES[$name,type]:-}
            local inc_ns=${BU_COMMAND_PROPERTIES[$name,namespace]:-}
            if [[ -n "$inc_type" ]]
            then
                BU_COMMAND_PROPERTIES[$qualified,type]=$inc_type
            fi
            if [[ -n "$incumbent_module" ]]
            then
                BU_COMMAND_PROPERTIES[$qualified,module]=$incumbent_module
            fi
            if [[ -n "$inc_ns" ]]
            then
                BU_COMMAND_PROPERTIES[$qualified,namespace]=$inc_ns
            fi
            BU_COMMAND_PROPERTIES[$name,shadows]=$qualified
            # Clear the loser's namespace label so `:<loser>:<cmd>` resolves to
            # the parked entry via the qualified store, not to the winner
            # through the bare entry's stale namespace label.
            unset "BU_COMMAND_PROPERTIES[$name,namespace]"
            bu_log_warn "Command collision: [$name] is registered by module[$incumbent_module] (rank $inc_rank) and module[$module] (rank $new_rank); [$module] takes the bare name and [$incumbent_module] is parked at $qualified"
        fi
    fi

    # ── Definition write (the ONLY BU_COMMANDS assignment in the codebase)
    BU_COMMANDS[$name]=$definition

    # ── Settle the dispatch type
    if [[ -n "$type" ]]
    then
        BU_COMMAND_PROPERTIES[$name,type]=$type
    elif [[ -n "$settle_file" ]]
    then
        local dispatch_decl
        __bu_command_dispatch_decl "$settle_file"
        dispatch_decl=$BU_RET
        if [[ -n "$dispatch_decl" ]]
        then
            BU_COMMAND_PROPERTIES[$name,type]=$dispatch_decl
            # A shell-mutating script with the exec bit is an attractive
            # nuisance: invoked as ./cmd.sh or via PATH it runs as a child
            # process and silently no-ops its mutations.
            if [[ "$dispatch_decl" == source && -x "$settle_file" ]]
            then
                bu_log_warn "Command[$name] declares '# Dispatch: source' but has the exec bit; invoking it as '$settle_file' will silently no-op its shell mutations. Use 'chmod -x' to remove the exec bit."
            fi
        else
            unset "BU_COMMAND_PROPERTIES[$name,type]"
        fi
    else
        unset "BU_COMMAND_PROPERTIES[$name,type]"
    fi

    # ── Stamp the owning module
    if [[ -n "$module" ]]
    then
        __bu_stamp_command_module "$name" "$module"
    fi
}


# ```
# *Description*:
# Register a single user-defined subcommand file
#
# *Params*:
# - `$1`: File path to the subcommand script
# - `$2` (optional): Command name to register (default: derived from file name)
# - `$3` (optional): Type of the command (e.g. `function`, `execute`, `source`)
#
# *Returns*: None
#
# *Examples*:
# ```bash
# bu_preinit_register_user_defined_subcommand_file /path/to/my-cmd.sh my-cmd execute
# bu_preinit_register_user_defined_subcommand_file /path/to/my-cmd.sh
# ```
#
# *Notes*:
# - If no command name is provided, it is derived from the file name (with .sh extension removed)
# - The command is added to the `BU_COMMANDS` associative array
# ```
bu_preinit_register_user_defined_subcommand_file()
{
    local -r file=$1
    local command=$2
    local type=$3
    local synopsis=

    # Parse --synopsis from remaining positional args
    shift 3 2>/dev/null || shift $#
    while (($#))
    do
        case "$1" in
        --synopsis)
            synopsis=$2
            shift 2
            ;;
        *)
            shift
            ;;
        esac
    done

    if [[ -z "$command" ]]
    then
        bu_basename "$file"
        local file_base=$BU_RET
        command=${file_base%.sh}
    fi

    if [[ -n "$type" ]]
    then
        __bu_command_register "$command" "$file" --type "$type"
    else
        __bu_command_register "$command" "$file" --settle-from-file "$file"
    fi

    if [[ -n "$synopsis" ]]
    then
        BU_COMMAND_PROPERTIES[$command,synopsis]=$synopsis
    fi
}

# ```
# *Description*:
# Register a user-defined subcommand function
#
# *Params*:
# - `$1`: Function name implementing the subcommand
# - `$2` (optional): Command name to register (default: same as function name)
# - `$3` (optional): Type of the command (e.g. `function`, `execute`, `source`)
#
# *Returns*: None
#
# *Examples*:
# ```bash
# bu_preinit_register_user_defined_subcommand_function my_cmd_func my-cmd function
# bu_preinit_register_user_defined_subcommand_function my_cmd_func
# ```
#
# *Notes*:
# - If no command name is provided, the function name is used as the command name
# - The command is added to the `BU_COMMANDS` associative array
# ```
bu_preinit_register_user_defined_subcommand_function()
{
    local -r fn=$1
    local command=$2
    local type=$3
    local synopsis=

    # Parse --synopsis from remaining positional args
    shift 3 2>/dev/null || shift $#
    while (($#))
    do
        case "$1" in
        --synopsis)
            synopsis=$2
            shift 2
            ;;
        *)
            shift
            ;;
        esac
    done

    if [[ -z "$command" ]]
    then
        command=$fn
    fi

    if [[ -n "$type" ]]
    then
        __bu_command_register "$command" "$fn" --type "$type"
    else
        __bu_command_register "$command" "$fn"
    fi

    if [[ -n "$synopsis" ]]
    then
        BU_COMMAND_PROPERTIES[$command,synopsis]=$synopsis
    fi
}

# ```
# *Description*:
# Convert a file name to a command name using prefix style with delimiter
#
# *Params*:
# - `$1`: Delimiter character (e.g. `-`)
# - `$2`: File path to convert
#
# *Returns*:
# - `$BU_RET`: The derived command name in format `verb-noun`
#
# *Examples*:
# ```bash
# bu_convert_file_to_command_prefix - /path/to/my-get-status.sh  # $BU_RET=get-status
# ```
#
# *Notes*:
# - This parses the file name (without .sh extension) and extracts verb and noun components
# - Updates the global `BU_COMMAND_VERBS` and `BU_COMMAND_NOUNS` sets
# - Stores verb/noun properties in `BU_COMMAND_PROPERTIES`
# ```
# ```
# *Description*:
# Split a command name (without namespace) into verb and remainder,
# honoring multi-word verbs registered in `BU_MULTI_WORD_VERBS`.
#
# *Params*:
# - `$1`: Command name without namespace (e.g. `convert-to-jsonl`)
#
# *Returns*:
# - `$BU_RET_VERB`: The verb (e.g. `convert-to` if registered, else `convert`)
# - `$BU_RET_REST`: The remainder after the verb (e.g. `jsonl`)
#
# *Notes*:
# - Multi-word verbs are matched longest-first as a `verb-` prefix
# - A name that is exactly a multi-word verb (no noun) is not special-cased;
#   it falls back to single-word splitting
# ```
__bu_preinit_split_verb()
{
    local -r no_namespace=$1
    local multi_word_verb best_match=
    # Longest match wins, so e.g. a hypothetical `convert-to-utc` beats `convert-to`
    for multi_word_verb in "${BU_MULTI_WORD_VERBS[@]}"
    do
        if [[ "$no_namespace" == "$multi_word_verb"-* ]] && (( ${#multi_word_verb} > ${#best_match} ))
        then
            best_match=$multi_word_verb
        fi
    done
    if [[ -n "$best_match" ]]
    then
        BU_RET_VERB=$best_match
        BU_RET_REST=${no_namespace#"$best_match"-}
        return 0
    fi
    BU_RET_VERB=${no_namespace%%-*}
    BU_RET_REST=${no_namespace#*-}
}

bu_convert_file_to_command_prefix()
{
    local -r delimiter=$1
    local -r file_path=$2
    bu_basename "$file_path"
    local -r file_base=$BU_RET
    local -r file_base_no_ext=${file_base%.sh}
    local -r namespace=${file_base_no_ext%%$delimiter*}
    local -r no_namespace=${file_base_no_ext#*$delimiter} # Don't quote prefix, we allow it to be a pattern
    __bu_preinit_split_verb "$no_namespace"
    local -r verb=$BU_RET_VERB
    local -r noun=$BU_RET_REST
    BU_COMMAND_VERBS[$verb]=1
    BU_COMMAND_NOUNS[$noun]=1
    BU_COMMAND_NAMESPACES[$namespace]=1
    local -r command=${verb}-${noun}
    BU_COMMAND_PROPERTIES[$command,verb]=$verb
    BU_COMMAND_PROPERTIES[$command,noun]=$noun
    BU_COMMAND_PROPERTIES[$command,namespace]=$namespace
    BU_RET=$command
}

# ```
# *Description*:
# Convert a file name to a command name using PowerShell style naming convention
#
# *Params*:
# - `$1`: File path to convert
#
# *Returns*:
# - `$BU_RET`: The derived command name in format `verb-noun`
#
# *Examples*:
# ```bash
# bu_convert_file_to_command_powershell /path/to/get-my-process-status.sh  # $BU_RET=get-process-status
# ```
#
# *Notes*:
# - This parses the file name (without .sh extension) in PowerShell style: `verb-namespace-noun`
# - Extracts the verb and noun components, discarding the namespace
# - Updates the global `BU_COMMAND_VERBS` and `BU_COMMAND_NOUNS` sets
# - Stores verb/noun properties in `BU_COMMAND_PROPERTIES`
# ```
bu_convert_file_to_command_powershell()
{
    local -r file_path=$1
    bu_basename "$file_path"
    local -r file_base_no_ext=${BU_RET%.sh}
    __bu_preinit_split_verb "$file_base_no_ext"
    local -r verb=$BU_RET_VERB
    local -r no_verb=$BU_RET_REST
    local -r namespace=${no_verb%%-*}
    local -r noun=${no_verb#*-}
    BU_COMMAND_VERBS[$verb]=1
    BU_COMMAND_NOUNS[$noun]=1
    BU_COMMAND_NAMESPACES[$namespace]=1
    local -r command=${verb}-${noun}
    BU_COMMAND_PROPERTIES[$command,verb]=$verb
    BU_COMMAND_PROPERTIES[$command,noun]=$noun
    BU_COMMAND_PROPERTIES[$command,namespace]=$namespace
    BU_RET=$command
}

# ```
# *Description*:
# Convert a file name to a command name using a specified naming style
#
# *Params*:
# - `$1`: Naming style (one of `none`, `prefix`, `powershell`, `prefix-keep`, `powershell-keep`)
# - `$2`: File path to convert
#
# *Returns*:
# - `$BU_RET`: The derived command name
#
# *Examples*:
# ```bash
# bu_convert_file_to_command_namespace prefix /path/to/my-get-status.sh  # $BU_RET=get-status
# bu_convert_file_to_command_namespace powershell /path/to/get-my-status.sh  # $BU_RET=get-status
# bu_convert_file_to_command_namespace none /path/to/mycmd.sh  # $BU_RET=mycmd
# ```
#
# *Notes*:
# - `none`, `prefix-keep`, and `powershell-keep` styles preserve the file name (without .sh extension)
# - `prefix` style delegates to `bu_convert_file_to_command_prefix` with `-` as delimiter
# - `powershell` style delegates to `bu_convert_file_to_command_powershell`
# ```
bu_convert_file_to_command_namespace()
{
    local -r style=$1
    local -r file_path=$2
    case "$style" in
    none)
        bu_basename "$file_path"
        BU_RET=${BU_RET%.sh}
        ;;
    prefix-keep)
        # -keep means don't throw away the namespace
        bu_convert_file_to_command_prefix - "$file_path"
        # We only need to do some processing of the other bookkeeping variables
        # Otherwise, we don't change the command name
        bu_basename "$file_path"
        BU_RET=${BU_RET%.sh}
        ;;
    powershell-keep)
        # -keep means don't throw away the namespace
        # We only need to do some processing of the other bookkeeping variables
        # Otherwise, we don't change the command name
        bu_convert_file_to_command_powershell "$file_path"
        bu_basename "$file_path"
        BU_RET=${BU_RET%.sh}
        ;;
    prefix)
        # Format namespace-verb-noun
        bu_convert_file_to_command_prefix - "$file_path"
        ;;
    powershell)
        # Format verb-namespace-noun
        bu_convert_file_to_command_powershell "$file_path"
        ;;
    *)
        bu_log_err "Invalid naming style[$style]"
        return 1
        ;;
    esac
}

# BashTab's builtin commands directory is registered from core (not a module
# preinit callback), so BU_CURRENT_MODULE is empty here.  Stamp its provenance
# as module "bu" (the framework itself) — matching how bu_entrypoint.sh stamps
# core config settings and help topics — so `bu get-command` reports module=bu
# for the builtin commands instead of leaving the module column empty.
_bu_cur_module_prev=${BU_CURRENT_MODULE:-}
BU_CURRENT_MODULE=bu
bu_preinit_register_user_defined_subcommand_dir "$BU_BUILTIN_COMMANDS_DIR" bu_convert_file_to_command_namespace prefix
BU_CURRENT_MODULE=$_bu_cur_module_prev

# Alias spec
# '{}' represents 1 input
# '{...}' represents remaining input
# '{?}' represents don't add the remaining if there are no more inputs
#
# There can be no '{}' after '...'
# There can be at most 1 '...'
#
# Example:
# my_command --arg1 '{}' '{?}' --arg2 '{}' '{...}'
#
# Aliases are using for creating positional commands and transforming them into named argument commands 
bu_preinit_register_new_alias()
{
    local -r alias_name=$1
    if [[ -z "$alias_name" ]]
    then
        bu_log_err "Alias name is empty"
        return 1
    fi
    shift

    # Parse --synopsis from the end of the args (before alias spec processing)
    local synopsis=
    local -a spec_args=()
    while (($#))
    do
        case "$1" in
        --synopsis)
            synopsis=$2
            shift 2
            ;;
        *)
            spec_args+=("$1")
            shift
            ;;
        esac
    done
    set -- "${spec_args[@]}"

    local i
    local has_remaining_input=false
    # Validate
    for ((i = 0; i < $#; i++))
    do
        case "${!i}" in
        '{...}')
            if "$has_remaining_input"
            then
                bu_log_err "Bad alias spec, there should not be another {...}"
                return 1
            fi
            has_remaining_input=true
            ;;
        '{}'|'{?}')
            if "$has_remaining_input"
            then
                bu_log_err "Bad alias spec, there should not be ${!i} after a {...}"
                return 1
            fi
        esac
    done
    local alias_spec=$*
    __bu_command_register "$alias_name" "$alias_spec" --type alias
    if [[ -n "$synopsis" ]]
    then
        BU_COMMAND_PROPERTIES[$alias_name,synopsis]=$synopsis
    fi
    return 0
}

# The builtin aliases are registered from core too — stamp them as module
# "bu" so `bu get-command` reports their provenance instead of leaving the
# module column empty.
_bu_cur_module_prev=${BU_CURRENT_MODULE:-}
BU_CURRENT_MODULE=bu
bu_preinit_register_new_alias gc get-command --namespace {} {?} --verb {} {?} --noun {} {...}

# Short aliases that expand to query-object --where / --select / --grep /
# --order-by.
#   bu get-process | bu where type -eq source
#   bu get-process | bu select name,verb
#   bu get-process | bu grep get
#   bu get-process | bu sort name desc
bu_preinit_register_new_alias where query-object --where {...}
bu_preinit_register_new_alias select query-object --select {...}
bu_preinit_register_new_alias grep query-object --grep {...}
bu_preinit_register_new_alias sort query-object --order-by {...}

# Stage effects for the aliases above — they have no script file to carry a
# `# Pipeline:` header, so register explicitly (query-object reads JSONL and
# emits JSONL).
bu_register_stage_effect "bu where" query
bu_register_stage_effect "bu select" query
bu_register_stage_effect "bu grep" query
bu_register_stage_effect "bu sort" query
BU_CURRENT_MODULE=$_bu_cur_module_prev
