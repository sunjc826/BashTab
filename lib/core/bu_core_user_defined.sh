# bash-ide source=../../bu_custom_source.sh
# bash-ide source=../../bu_user_defined_decl.sh

# Sources user defined configuration callback scripts.
#
# @noargs
# bash-ide parse-func-sig
bu_source_user_defined_configs()
{
    bu_source_multi_once "${BU_USER_DEFINED_STATIC_CONFIGS[@]}"
    bu_source_multi "${BU_USER_DEFINED_DYNAMIC_CONFIGS[@]}"
}

# Sources user defined pre-init callback scripts.
#
# @noargs
# bash-ide parse-func-sig
bu_source_user_defined_pre_init_callbacks()
{
    local -r saved_module=${BU_CURRENT_MODULE:-}
    local filepath
    if ! "$BU_SOURCE_IS_CUSTOM" && ((${#BU_USER_DEFINED_STATIC_PRE_INIT_ENTRYPOINT_CALLBACKS[@]}))
    then
        for filepath in "${BU_USER_DEFINED_STATIC_PRE_INIT_ENTRYPOINT_CALLBACKS[@]}"
        do
            BU_CURRENT_MODULE=${BU_MODULE_PREINIT_MAP[$filepath]:-}
            # shellcheck disable=SC1090
            source "$filepath"
        done
    else
        for filepath in "${BU_USER_DEFINED_STATIC_PRE_INIT_ENTRYPOINT_CALLBACKS[@]}"
        do
            BU_CURRENT_MODULE=${BU_MODULE_PREINIT_MAP[$filepath]:-}
            # shellcheck disable=SC1090
            source "$filepath" --__bu-once --__bu-no-inline
        done
    fi
    BU_CURRENT_MODULE=$saved_module
    bu_source_multi "${BU_USER_DEFINED_DYNAMIC_POST_ENTRYPOINT_CALLBACKS[@]}"
}

# Sources user defined post-init callback scripts.
#
# @noargs
# bash-ide parse-func-sig
bu_source_user_defined_post_entrypoint_callbacks()
{
    bu_source_multi_once "${BU_USER_DEFINED_STATIC_POST_ENTRYPOINT_CALLBACKS[@]}"
    bu_source_multi "${BU_USER_DEFINED_DYNAMIC_POST_ENTRYPOINT_CALLBACKS[@]}"
}

# *Params*
# - `$1`: Command to convert to a key
#
# *Returns*
# - `$BU_RET`: Key. By default it will be of the form `command-$1`, but users can override the behavior with user defined functions in `${BU_USER_DEFINED_COMPLETION_COMMAND_TO_KEY_CONVERSIONS[@]}`.
#              The first user defined function to perform the conversion successfully will take priority.
#
# Each function will be of the following signature
# *Function Params*
# - `$1`: Command to convert to a key
#
# *Function Returns*
# - Exit code:
#   - 0: Function successfully maps command to a key
#   - 1 or any other non-zero exit code: Mapping is unsuccessful
# - `$BU_RET`: If exit code is 0, then this should be the key
# bash-ide parse-func-sig
bu_user_defined_convert_command_to_key()
{
    local command=$1
    local fn
    for fn in "${BU_USER_DEFINED_COMPLETION_COMMAND_TO_KEY_CONVERSIONS[@]}"
    do
        "$fn" "$command"
        if (($? == 0))
        then
            return
        fi
    done
    BU_RET=command-$command # default conversion
}

# *Params*
# - `...`: Lazy autocompletion args
#
# *Returns*
# - `${COMPREPLY[@]}`: Original contents plus new autocompletions
# - `$BU_RET`: Number of lazy autocompletion args consumed
#
# Each function will be of the following signature
# *Function Params*
# - `...`: Lazy autocompletion args
#
# *Function Returns*
# - Exit code:
#   - 0: Function successfully parses the lazy autocompletion args
#   - 124: Function successfully parses the lazy autocompletion args,
#          needs to await further input from user and retry before moving on to the next word.
#   - 1: Function does not handle the lazy autocompletion args
# - `${COMPREPLY[@]}`: If exit code is 0, then this is the original contents plus new autocompletions
# - `$BU_RET`: If exit code is 0, then this should be the number of lazy autocompletion args consumed
# bash-ide parse-func-sig
bu_user_defined_autocomplete_lazy()
{
    local fn
    local exit_code=1
    local fn_exit_code
    BU_RET=0
    for fn in "${BU_USER_DEFINED_AUTOCOMPLETE_HELPERS[@]}"
    do
        "$fn" "$@" && fn_exit_code=0 || fn_exit_code=$?
        case "$fn_exit_code" in
        0|124)
            exit_code=$fn_exit_code
            break
            ;;
        1|*)
            continue
            ;;
        esac
    done
    return "$exit_code"
}

# Normalize BU_MODULE_LIST in place: drop empty and repeated entries (by
# module name, first wins). BU_MODULE_LIST is a static setting, so the
# entrypoint normalizes it before the static config phase finalizes it (and
# before re-checking it on re-activation).
#
# @noargs
#
# @returns None (always 0)
# bash-ide parse-func-sig
__bu_module_list_normalize()
{
    local entry name normalized=
    local -A seen=()
    local old_ifs=$IFS
    IFS=';'
    local -a entries=(${BU_MODULE_LIST:-})
    IFS=$old_ifs
    for entry in "${entries[@]}"
    do
        [[ -n "$entry" ]] || continue
        name=${entry%%:*}
        [[ -v "seen[$name]" ]] && continue
        seen[$name]=1
        normalized+="$entry;"
    done
    if [[ "${BU_MODULE_LIST-}" != "$normalized" ]]
    then
        BU_MODULE_LIST=$normalized
    fi
    return 0
}

# Order the BU_MODULE_LIST entries so that every module comes after the
# modules it requires (BU_MODULE_DEPS, recorded by bu_module_require): a
# depth-first topological sort, visiting modules and their requirements in
# BU_MODULE_LIST order so unrelated modules keep their relative order. A
# requirement that closes a cycle is ignored for the order, with a warning.
# Requirements on modules that are not in the list are ignored. Pure Bash (no
# subshells); the result is cached until either input changes, so the
# entrypoint's three callers sort once per shell.
#
# @noargs
# @set BU_RET the "name:version:preinit_path" entries, dependencies first
# bash-ide parse-func-sig
__bu_module_order()
{
    local -r key="${BU_MODULE_LIST:-}|${BU_MODULE_DEPS:-}"
    if [[ "${__BU_MODULE_ORDER_KEY-}" == "$key" ]]
    then
        BU_RET=("${__BU_MODULE_ORDER[@]}")
        return 0
    fi
    local entry name pair parent dep
    local -a names=()
    local -A entry_of=() deps=() state=()
    local old_ifs=$IFS
    IFS=';'
    local -a entries=(${BU_MODULE_LIST:-})
    local -a pairs=(${BU_MODULE_DEPS:-})
    IFS=$old_ifs
    for entry in "${entries[@]}"
    do
        [[ -n "$entry" ]] || continue
        name=${entry%%:*}
        [[ -v "entry_of[$name]" ]] && continue
        entry_of[$name]=$entry
        names+=("$name")
    done
    for pair in "${pairs[@]}"
    do
        [[ "$pair" == ?*'>'?* ]] || continue
        parent=${pair%%>*}
        dep=${pair#*>}
        [[ -v "entry_of[$parent]" && -v "entry_of[$dep]" ]] || continue
        deps[$parent]+="$dep "
    done
    BU_RET=()
    for name in "${names[@]}"
    do
        __bu_module_order_visit "$name"
    done
    __BU_MODULE_ORDER=("${BU_RET[@]}")
    __BU_MODULE_ORDER_KEY=$key
    return 0
}

# Cycles already reported (once per shell), and the cached module order
declare -p __BU_MODULE_CYCLE_WARNED &>/dev/null || declare -A -g __BU_MODULE_CYCLE_WARNED=()
declare -p __BU_MODULE_ORDER &>/dev/null || declare -a -g __BU_MODULE_ORDER=()
declare -g __BU_MODULE_ORDER_KEY=${__BU_MODULE_ORDER_KEY-}

# Visit one module for __bu_module_order (uses its locals: entry_of, deps,
# state; appends to BU_RET)
# bash-ide parse-func-sig
__bu_module_order_visit()
{
    local -r module=$1
    local dep
    [[ "${state[$module]:-}" == done ]] && return 0
    state[$module]=visiting
    for dep in ${deps[$module]:-}
    do
        case "${state[$dep]:-}" in
        done) ;;
        visiting)
            if [[ ! -v "__BU_MODULE_CYCLE_WARNED[$module>$dep]" ]]
            then
                __BU_MODULE_CYCLE_WARNED[$module>$dep]=1
                bu_basic_log_warn "Module dependency cycle: $module requires $dep, which requires $module (directly or not); ignoring that requirement when ordering modules"
            fi
            ;;
        *) __bu_module_order_visit "$dep" ;;
        esac
    done
    state[$module]=done
    BU_RET+=("${entry_of[$module]}")
    return 0
}

# Source each module's config registration file, found next to its preinit
# (from BU_MODULE_LIST): NAME_bu_config.static.sh for the static config phase,
# NAME_bu_config.sh for the main one, in dependency order (__bu_module_order).
# The entrypoint calls this while the phase is open, so a module's settings
# are resolved with BashTab's own.
# While a file runs, BU_CURRENT_MODULE is the module's name and
# BU_CURRENT_MODULE_DIR its directory (for defaults relative to it).
#
# @arg $1 {string} kind `static` or `main`
#
# @returns None (always 0)
# bash-ide parse-func-sig
__bu_source_module_configs()
{
    local -r kind=$1
    local suffix=.sh
    [[ "$kind" == static ]] && suffix=.static.sh
    local entry name path file
    local -r saved_module=${BU_CURRENT_MODULE:-}
    __bu_module_order
    local -a entries=("${BU_RET[@]}")
    for entry in "${entries[@]}"
    do
        name=${entry%%:*}
        path=${entry#*:}
        path=${path#*:}
        [[ "$path" == */* ]] || continue
        file=${path%/*}/${name}_bu_config$suffix
        [[ -f "$file" ]] || continue
        BU_CURRENT_MODULE=$name
        BU_CURRENT_MODULE_DIR=${path%/*}
        # shellcheck disable=SC1090
        source "$file"
    done
    BU_CURRENT_MODULE=$saved_module
    unset BU_CURRENT_MODULE_DIR
    return 0
}

# Parse BU_MODULE_LIST and register preinit callbacks + module registry entries.
#
# BU_MODULE_LIST is an exported scalar of the form:
#   "name:version:preinit_path;name:version:preinit_path;..."
#
# Modules append to it in their module script; the top-level sets it directly.
# Top-level projects set it directly in their activate script before sourcing
# bu_entrypoint.sh — no function call needed.
#
# *Side effects*:
# - Populates BU_MODULE_REGISTRY (for bu get-module) and BU_MODULE_RANK (list
#   order: the top-level module first)
# - Appends preinit paths to BU_USER_DEFINED_STATIC_PRE_INIT_ENTRYPOINT_CALLBACKS
#   in dependency order (__bu_module_order), so a module's preinit runs after
#   those of the modules it requires and the top-level module's runs last
# bash-ide parse-func-sig
__bu_parse_module_list()
{
    local entry name version path
    local old_ifs=$IFS
    IFS=';'
    local -a entries=()
    entries=(${BU_MODULE_LIST:-})
    IFS=$old_ifs

    local -A seen_names=()
    local -A seen_paths=()
    local deduped=
    BU_MODULE_PREINIT_MAP=()

    for entry in "${entries[@]}"
    do
        [[ -z "$entry" ]] && continue
        name=${entry%%:*}
        local rest=${entry#*:}
        version=${rest%%:*}
        path=${rest#*:}

        # Dedup by name (first registration wins)
        if [[ -n "${seen_names[$name]:-}" ]]; then
            continue
        fi
        seen_names[$name]=1

        # Precedence rank: 1-based position in the deduped list (top-level=1,
        # dependencies in list order). First assignment wins so re-activation
        # cannot renumber an already-ranked module.
        if [[ -z "${BU_MODULE_RANK[$name]:-}" ]]; then
            BU_MODULE_RANK[$name]=${#seen_names[@]}
        fi

        # Append to deduped list
        deduped+="${name}:${version}:${path};"

        # Register for bu get-module
        BU_MODULE_REGISTRY[$name]="$version:$path"
    done

    # Write back the deduped list
    BU_MODULE_LIST=$deduped
    export BU_MODULE_LIST

    # Register preinit callbacks in dependency order (dedup by path)
    __bu_module_order
    for entry in "${BU_RET[@]}"
    do
        name=${entry%%:*}
        path=${entry#*:}
        path=${path#*:}
        if [[ -n "$path" && -z "${seen_paths[$path]:-}" ]]; then
            seen_paths[$path]=1
            BU_USER_DEFINED_STATIC_PRE_INIT_ENTRYPOINT_CALLBACKS+=("$path")
            BU_MODULE_PREINIT_MAP[$path]=$name
        fi
    done
}
