# bash-ide source=./bu_core_cli.sh
# bash-ide source=./bu_core_autocomplete.sh

# MARK: Bare-name command exposure (BU_EXPOSE_COMMANDS)
#
# When BU_EXPOSE_COMMANDS is true, every source-type and execute-type
# command in BU_COMMANDS gets a thin shell function wrapper of the same
# name, plus Tab completion.  Toggling the flag off and re-running init
# (or sourcing this module) cleanly tears down all exposed names.

# Track currently exposed names so teardown is precise.
declare -A -g __BU_EXPOSED_NAMES=()

# Teardown all previously exposed bare-name functions and completions.
# Idempotent — safe to call when nothing is exposed.
# bash-ide parse-func-sig
__bu_expose_teardown()
{
    local name
    for name in "${!__BU_EXPOSED_NAMES[@]}"
    do
        unset -f "$name" 2>/dev/null || true
        complete -r "$name" 2>/dev/null || true
    done
    __BU_EXPOSED_NAMES=()
}

# Completion function for an exposed bare name.  Resolves the bare name
# to its real script path via BU_COMMANDS before calling the master
# completion impl (which sources its first arg for lazy DSL harvesting
# and needs a real file path, not a function name).
__bu_expose_completion_func()
{
    local bare_name=$1
    local script_path=${BU_COMMANDS[$bare_name]:-}
    # The master impl sources $script_path; fall back to bare_name
    # (which won't be sourceable, but completion degrades gracefully).
    __bu_autocomplete_completion_func_master_impl \
        "${script_path:-$bare_name}" "$2" "$3" "$COMP_CWORD" "" "${COMP_WORDS[@]}"
}

# Set up bare-name function wrappers and completions for all eligible
# source-type and execute-type commands.  Skips function/alias types
# and any name that would shadow a real tool (builtin, keyword, PATH
# binary, existing function, or alias).
# bash-ide parse-func-sig
__bu_expose_setup()
{
    local command script_path type
    for command in "${!BU_COMMANDS[@]}"
    do
        script_path=${BU_COMMANDS[$command]}

        # ── Type guard: only source and execute ──────────────────────
        __bu_cli_command_type "$command"
        type=$BU_RET
        case "$type" in
        source|execute) ;;
        *) continue ;;
        esac

        # ── Collision guard ──────────────────────────────────────────
        # Do not shadow builtins, keywords, real PATH executables,
        # pre-existing functions, or aliases.
        case "$(type -t "$command" 2>/dev/null)" in
        builtin|keyword|file|function|alias) continue ;;
        esac

        # ── Identifier guard ─────────────────────────────────────────
        # The command name must be a valid shell function identifier.
        [[ "$command" =~ ^[a-zA-Z_][a-zA-Z0-9_.-]*$ ]] || continue

        # ── Define the wrapper function ──────────────────────────────
        case "$type" in
        source)
            # source-type must run in the caller's shell (cwd/env
            # mutations); use builtin source directly.
            eval "$command() { builtin source '$script_path' \"\$@\"; }"
            ;;
        execute)
            # execute-type runs in a subprocess; direct invocation works.
            eval "$command() { '$script_path' \"\$@\"; }"
            ;;
        esac

        # ── Register completion ──────────────────────────────────────
        complete -F __bu_expose_completion_func "$command"

        # ── Track for teardown ───────────────────────────────────────
        __BU_EXPOSED_NAMES[$command]=1
    done
}

# Idempotent expose/teardown entry point.  Tears down any previous
# exposure, then re-exposes iff BU_EXPOSE_COMMANDS is true.
# Called from bu_init after autocomplete is set up.
# bash-ide parse-func-sig
__bu_expose()
{
    __bu_expose_teardown
    if "${BU_EXPOSE_COMMANDS:-false}"
    then
        __bu_expose_setup
    fi
}
