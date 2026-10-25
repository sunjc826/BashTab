# bash-ide source=../../bu_custom_source.sh

# MARK: Config registry

# Declarative settings registry — the config equivalent of the autocompletion
# DSL specifiers. One `bu_config_register` call declares everything about a
# setting; `bu set-config` (validation, value mapping, --unset default restore,
# --list, completion) consumes the registry. Modules can register their own
# settings the same way.
#
# Acceptable setting-name prefixes. Embedders can pre-seed this array before
# sourcing the entrypoint or append to it afterward to allow their own
# namespaced settings (e.g. BU_CONFIG_NAME_PREFIXES+=(MYAPP_)).
# Declared guarded so a pre-seeded value survives.
if ! declare -p BU_CONFIG_NAME_PREFIXES &>/dev/null
then
    declare -a -g BU_CONFIG_NAME_PREFIXES=(BU_)
fi

# Storage mirrors BU_COMMAND_PROPERTIES: keys are "$name,field".
# The registry, phase state and provenance below are declared guarded, so
# re-sourcing this file (`source ./activate -f`) keeps them: static settings
# stay final. `bu import-environment --reset-source` resets the static phases
# explicitly (__bu_config_static_reset).
declare -p BU_CONFIG_PROPERTIES &>/dev/null || declare -A -g BU_CONFIG_PROPERTIES=()

# Named persistence layers. Each entry maps a layer name to a resolver
# function that prints the layer's settings file path for the current context.
# The "local" layer is built-in (the machine-local settings file).
declare -p BU_CONFIG_LAYER_RESOLVERS &>/dev/null || declare -A -g BU_CONFIG_LAYER_RESOLVERS=()

# Config phases. Every setting belongs to exactly one phase, the one open
# when it was registered. A phase resolves its settings in one step
# (bu_config_phase_end): exported values win, then the phase's own settings
# files, then registered defaults, written to a generated file and sourced.
# The entrypoint runs the built-in "static" and "main" phases; projects can
# add their own. A static phase (--static) is resolved once per shell: its
# values are exported and stay final, so running it again (re-activation) only
# restores any that changed.
#   BU_CONFIG_PHASE_STATE     phase -> open | final
#   __BU_CONFIG_PHASE_STATIC  phase -> true for static phases
#   __BU_CONFIG_PHASE_VARIANT phase -> active variant (e.g. a profile): picks
#                             bu_config_local.PHASE.VARIANT.sh and
#                             --default-for values
#   __BU_CONFIG_PHASE_PREFIX  phase -> required setting-name prefix
#   __BU_CONFIG_PHASE_FILES   phase -> extra settings files (--settings-file):
#                             newline-separated ORIGIN:PATH entries, with a
#                             bare `local` line where the built-in files go
#   __BU_CONFIG_OPEN_PHASE    the phase registrations currently go to
#   __BU_CONFIG_RECHECK       true while re-running a final static phase
#   __BU_CONFIG_PHASE_NAMES   settings of the phase being resolved
declare -p BU_CONFIG_PHASE_STATE &>/dev/null || declare -A -g BU_CONFIG_PHASE_STATE=()
declare -p __BU_CONFIG_PHASE_STATIC &>/dev/null || declare -A -g __BU_CONFIG_PHASE_STATIC=()
declare -p __BU_CONFIG_PHASE_VARIANT &>/dev/null || declare -A -g __BU_CONFIG_PHASE_VARIANT=()
declare -p __BU_CONFIG_PHASE_PREFIX &>/dev/null || declare -A -g __BU_CONFIG_PHASE_PREFIX=()
declare -p __BU_CONFIG_PHASE_FILES &>/dev/null || declare -A -g __BU_CONFIG_PHASE_FILES=()
declare -g __BU_CONFIG_OPEN_PHASE=
declare -g __BU_CONFIG_RECHECK=false
declare -a -g __BU_CONFIG_PHASE_NAMES=()

# Settings provenance. Exported values belong to the user: a phase saves them
# before sourcing its settings files and restores them afterwards, so the
# environment beats persisted settings while the files keep plain VAR=value
# assignments (re-sourcing a file by hand still applies it).
#   __BU_CONFIG_USER       name -> value the user exported before the phase ran
#                          (for a static phase, also an unexported value)
#   __BU_CONFIG_USER_KIND  name -> env (exported) or shell (unexported, static)
#   BU_CONFIG_ORIGIN       name -> local | site | callback | layer, or the
#                          label of a --settings-file: who set it
#   BU_CONFIG_SOURCE_FILE  name -> absolute path of the file that set it
#   __BU_CONFIG_APPLIED    name -> value when its phase finished (or after the
#                          last `bu set-config`), to spot later shell edits
#   __BU_CONFIG_SNAP       scratch snapshot for attributing file assignments
declare -p __BU_CONFIG_USER &>/dev/null || declare -A -g __BU_CONFIG_USER=()
declare -p __BU_CONFIG_USER_KIND &>/dev/null || declare -A -g __BU_CONFIG_USER_KIND=()
declare -p BU_CONFIG_ORIGIN &>/dev/null || declare -A -g BU_CONFIG_ORIGIN=()
declare -p BU_CONFIG_SOURCE_FILE &>/dev/null || declare -A -g BU_CONFIG_SOURCE_FILE=()
declare -p __BU_CONFIG_APPLIED &>/dev/null || declare -A -g __BU_CONFIG_APPLIED=()
declare -A -g __BU_CONFIG_SNAP=()

# Scratch results of __bu_config_parse_enum_file (an --enum-file's sections)
#   __BU_CONFIG_ENUM_HEADER          leading comment lines, verbatim
#   __BU_CONFIG_ENUM_GENERATED       values of the generated section (all of
#                                    them in a file without markers)
#   __BU_CONFIG_ENUM_HAND_KEPT       values of the hand-kept section
#   __BU_CONFIG_ENUM_HAND_KEPT_LINES the hand-kept section's lines, verbatim
declare -a -g __BU_CONFIG_ENUM_HEADER=()
declare -a -g __BU_CONFIG_ENUM_GENERATED=()
declare -a -g __BU_CONFIG_ENUM_HAND_KEPT=()
declare -a -g __BU_CONFIG_ENUM_HAND_KEPT_LINES=()
# Scratch rows of __bu_config_validate_rows / __bu_config_refresh_enum_rows
declare -a -g __BU_CONFIG_VALIDATE_ROWS=()
declare -a -g __BU_CONFIG_REFRESH_ROWS=()

# Validate a setting name against the configured name prefixes.
# Returns 0 if the name starts with one of the prefixes listed in
# BU_CONFIG_NAME_PREFIXES and contains only uppercase letters, digits,
# and underscores after the prefix.
#
# @arg $1 {string} name Setting name to validate
#
# @returns
# - 0 if the name is valid, 1 otherwise
# bash-ide parse-func-sig
bu_config_name_is_valid()
{
    local -r name=$1
    local prefix
    for prefix in "${BU_CONFIG_NAME_PREFIXES[@]}"
    do
        if [[ "$name" =~ ^${prefix}[A-Z0-9_]*$ ]]
        then
            return 0
        fi
    done
    return 1
}

# Register a named persistence layer with a resolver function.
# The resolver is called by bu_config_layer_file and should print
# the layer's settings file path to stdout for the current context.
#
# @arg $1 {string} name Layer name (must be usable as a shell identifier)
# @arg $2 {string} resolver Resolver function name (called with any extra args passed to
#   bu_config_layer_file)
# bash-ide parse-func-sig
bu_config_register_layer()
{
    local name=$1
    local resolver=$2
    BU_CONFIG_LAYER_RESOLVERS[$name]=$resolver
    return 0
}

# Resolve a named layer to its settings file path.
# The "local" layer (and empty name) resolve to the machine-local file.
#
# @arg $1 {string} name Layer name (`local` or a registered layer)
# @arg $@ {string} args... Extra arguments forwarded to the layer's resolver function
# @set BU_RET the resolved file path
#
# @returns
# - Exit code: 0 on success, 1 if the layer name is unknown
# bash-ide parse-func-sig
bu_config_layer_file()
{
    local name=$1
    shift
    if [[ -z "$name" || "$name" == local ]]
    then
        BU_RET=${BU_CONFIG_LOCAL_FILE:-"$BU_DIR"/config/bu_config_local.sh}
        return 0
    fi
    local resolver=${BU_CONFIG_LAYER_RESOLVERS[$name]:-}
    if [[ -z "$resolver" ]]
    then
        local -a names=(local)
        local k
        for k in "${!BU_CONFIG_LAYER_RESOLVERS[@]}"
        do
            [[ -n "${BU_CONFIG_LAYER_RESOLVERS[$k]}" ]] && names+=("$k")
        done
        printf -v _joined '%s, ' "${names[@]}"
        bu_log_err "Unknown config layer '$name'. Registered layers: ${_joined%, }"
        return 1
    fi
    BU_RET=$("$resolver" "$@")
    return 0
}

# Register a runtime setting with metadata.
#
# @arg $1 string Setting name (must start with one of the configured prefixes)
# @arg $@ {string} args... DSL specifiers, processed left to right:
#   - `--default VALUE`: value restored by `bu set-config --unset`
#   - `--bool`: value must be `true` or `false`
#   - `--enum a b:2 c enum--`: allowed values; optional `name:mapped` form
#     accepts `name` but stores `mapped` (e.g. warn:2)
#   - `--enum-file PATH`: the allowed values come from PATH, one per line
#     (blank lines and `#` comments ignored, `name:mapped` as for --enum).
#     Kept as BU_CONFIG_PROPERTIES[NAME,enum_file] (absolute; a relative PATH
#     is resolved against $PWD now); the values land in [NAME,enum] as for
#     --enum. An unreadable PATH is a registration error, except a missing
#     file with an --enum-source (registered without values until
#     `bu update-config-enum NAME --execute` creates it). Layout, for files
#     refreshed from a source: header comments, `# --- generated (NOTE) ---`,
#     the source's values, `# --- hand-kept ---`, values the source does not
#     know. A file without markers counts as all generated.
#   - `--enum-source CMD`: (with --enum-file) a function name or command
#     line, eval'd in the current shell, that prints the fresh allowed values
#     one per line; bu_config_refresh_enum_file (`bu update-config-enum`)
#     rewrites the file's generated section from it. Kept as
#     BU_CONFIG_PROPERTIES[NAME,enum_source]
#   - `--hint "text"`: description shown by `bu set-config --list`
#   - `--env-only`: (static phases) only the environment can set it, never a
#     settings file or `bu set-config`
#   - `--default-for VARIANT VALUE`: (repeatable) the default while the
#     phase's variant is VARIANT, instead of --default
#
# @example
# ```bash
# bu_config_register BU_LOG_LVL --default 2 \
#     --enum debug:0 info:1 warn:2 err:3 silence:99 enum-- \
#     --hint "Log level when running commands"
# bu_config_register MYAPP_VENUE --enum-file "$BU_CURRENT_MODULE_DIR"/venues.txt \
#     --enum-source myapp_list_venues --hint "Trading venue"
# ```
#
# Nothing validates settings-file values at activation: run
# bu_config_require_valid (or `bu validate-config`) where a bad value matters.
bu_config_register()
{
    local name=$1
    shift
    if ! bu_config_name_is_valid "$name"
    then
        local _prefix_list="${BU_CONFIG_NAME_PREFIXES[*]}"
        bu_basic_log_err "bu_config_register: invalid setting name[$name], must match ^(${_prefix_list// /|})[A-Z0-9_]*$"
        return 1
    fi
    local default= enum= hint= layer= complete_values_fn= enum_file= enum_source=
    local has_enum=false
    local is_bool=false
    local is_env_only=false
    local -A default_for=()
    local presets=
    while (($#))
    do
        case "$1" in
        --default)
            default=$2
            shift 2
            ;;
        --bool)
            is_bool=true
            shift
            ;;
        --enum)
            shift
            local -a enum_values=()
            while (($#)) && [[ "$1" != enum-- ]]
            do
                enum_values+=("$1")
                shift
            done
            if (($# == 0))
            then
                bu_basic_log_err "bu_config_register: --enum missing terminator enum--"
                return 1
            fi
            shift
            enum="${enum_values[*]}"
            has_enum=true
            ;;
        --enum-file|--enum-source)
            if (($# < 2)) || [[ -z "$2" ]]
            then
                bu_basic_log_err "bu_config_register: $name: $1 needs a value"
                return 1
            fi
            if [[ "$1" == --enum-file ]]
            then
                enum_file=$2
            else
                enum_source=$2
            fi
            shift 2
            ;;
        --presets)
            shift
            local -a preset_values=()
            while (($#)) && [[ "$1" != presets-- ]]
            do
                preset_values+=("$1")
                shift
            done
            if (($# == 0))
            then
                bu_basic_log_err "bu_config_register: --presets missing terminator presets--"
                return 1
            fi
            shift
            presets="${preset_values[*]}"
            ;;
        --complete-values)
            complete_values_fn=$2
            shift 2
            ;;
        --layer)
            layer=$2
            shift 2
            ;;
        --hint)
            hint=$2
            shift 2
            ;;
        --env-only)
            is_env_only=true
            shift
            ;;
        --default-for)
            default_for[$2]=$3
            shift 3
            ;;
        *)
            bu_basic_log_err "bu_config_register: unrecognized specifier[$1]"
            return 1
            ;;
        esac
    done
    if [[ -n "$enum_file" ]]
    then
        if "$has_enum"
        then
            bu_basic_log_err "bu_config_register: $name: --enum and --enum-file are mutually exclusive"
            return 1
        fi
        [[ "$enum_file" == /* ]] || enum_file=$PWD/${enum_file#./}
        if [[ -e "$enum_file" || -z "$enum_source" ]]
        then
            if [[ ! -f "$enum_file" || ! -r "$enum_file" ]]
            then
                bu_basic_log_err "bu_config_register: $name: --enum-file[$enum_file] is not a readable file"
                return 1
            fi
            __bu_config_parse_enum_file "$enum_file"
            __bu_config_enum_join "${__BU_CONFIG_ENUM_GENERATED[@]}" "${__BU_CONFIG_ENUM_HAND_KEPT[@]}"
            enum=$BU_RET
        else
            bu_basic_log_warn "bu_config_register: $name: --enum-file[$enum_file] does not exist yet; any value is accepted until \`bu update-config-enum $name --execute\` creates it"
        fi
    elif [[ -n "$enum_source" ]]
    then
        bu_basic_log_err "bu_config_register: $name: --enum-source needs an --enum-file to keep the values in"
        return 1
    fi
    # Owning phase: the open one; outside any phase, legacy late registration
    # into main (no files, defaults or provenance beyond what the caller does)
    local phase=${__BU_CONFIG_OPEN_PHASE:-main}
    local owner=${BU_CONFIG_PROPERTIES[$name,phase]:-}
    if [[ -z "$__BU_CONFIG_OPEN_PHASE" && -n "${BU_CURRENT_MODULE:-}" && "${BU_CONFIG_PHASE_STATE[main]:-}" == final ]]
    then
        bu_basic_log_warn "bu_config_register: $name registered outside a config phase (module ${BU_CURRENT_MODULE}); register it in ${BU_CURRENT_MODULE}_bu_config.sh so the environment and settings files apply to it"
    fi
    local prefix=${__BU_CONFIG_PHASE_PREFIX[$phase]:-}
    if [[ -n "$prefix" && "$name" != "$prefix"* ]]
    then
        bu_basic_log_err "bu_config_register: settings of config phase '$phase' must start with $prefix (got $name)"
        return 1
    fi
    if [[ -n "$owner" && "$owner" != "$phase" ]]
    then
        bu_basic_log_err "bu_config_register: $name already belongs to config phase '$owner', cannot register it in '$phase'"
        return 1
    fi
    if "$__BU_CONFIG_RECHECK" && [[ "$phase" == "$__BU_CONFIG_OPEN_PHASE" ]]
    then
        # Re-running a final static phase: its settings are already known
        if [[ -z "$owner" ]]
        then
            bu_basic_log_err "bu_config_register: $name registered after static config phase '$phase' was finalized for this shell; it takes effect in a new shell"
        fi
        return 0
    fi
    if "$is_env_only" && [[ "${__BU_CONFIG_PHASE_STATIC[$phase]:-}" != true ]]
    then
        bu_basic_log_err "bu_config_register: --env-only requires a static config phase ($name is in '$phase')"
        return 1
    fi
    BU_CONFIG_PROPERTIES[$name,registered]=true
    BU_CONFIG_PROPERTIES[$name,phase]=$phase
    # The default for the phase's active variant, if one was given
    local variant=${__BU_CONFIG_PHASE_VARIANT[$phase]:-} key
    for key in "${!default_for[@]}"
    do
        BU_CONFIG_PROPERTIES[$name,default_for,$key]=${default_for[$key]}
    done
    if [[ -n "$variant" && -v "default_for[$variant]" ]]
    then
        default=${default_for[$variant]}
    fi
    [[ -n "$default" ]] && BU_CONFIG_PROPERTIES[$name,default]=$default
    [[ -n "$enum" ]] && BU_CONFIG_PROPERTIES[$name,enum]=$enum
    [[ -n "$enum_file" ]] && BU_CONFIG_PROPERTIES[$name,enum_file]=$enum_file
    [[ -n "$enum_source" ]] && BU_CONFIG_PROPERTIES[$name,enum_source]=$enum_source
    [[ -n "$hint" ]] && BU_CONFIG_PROPERTIES[$name,hint]=$hint
    [[ -n "$presets" ]] && BU_CONFIG_PROPERTIES[$name,presets]=$presets
    "$is_bool" && BU_CONFIG_PROPERTIES[$name,bool]=true
    "$is_env_only" && BU_CONFIG_PROPERTIES[$name,env_only]=true
    [[ -n "$layer" ]] && BU_CONFIG_PROPERTIES[$name,layer]=$layer
    [[ -n "$complete_values_fn" ]] && BU_CONFIG_PROPERTIES[$name,complete_values_fn]=$complete_values_fn
    # Stamp the owning module (mirrors __bu_stamp_command_module and the
    # help-topic stamp in bu_core_help_topic.sh) so `bu get-config` can tell
    # a core BU_* setting from one a module registered. STICKY: only
    # overwrite when BU_CURRENT_MODULE is non-empty, so re-registering a
    # setting outside the entrypoint (where BU_CURRENT_MODULE is empty) never
    # blanks its provenance.
    if [[ -n "${BU_CURRENT_MODULE:-}" ]]
    then
        BU_CONFIG_PROPERTIES[$name,module]=$BU_CURRENT_MODULE
    fi
    # Where the setting is declared (first line of the register call), for
    # the location of a defaulted setting in `bu get-config`.
    local src=${BASH_SOURCE[1]:-}
    if [[ -n "$src" ]]
    then
        [[ "$src" == /* ]] || src=$PWD/${src#./}
        BU_CONFIG_PROPERTIES[$name,defined_at]=$src:${BASH_LINENO[0]}
    fi
    return 0
}

# List the names of the settings registered in a config phase.
#
# @arg $1 {string} phase Phase name
# @set BU_RET the setting names, sorted
# bash-ide parse-func-sig
__bu_config_phase_settings()
{
    local -r phase=$1
    local key
    BU_RET=()
    for key in "${!BU_CONFIG_PROPERTIES[@]}"
    do
        [[ "$key" == *,phase && "${BU_CONFIG_PROPERTIES[$key]}" == "$phase" ]] || continue
        BU_RET+=("${key%,phase}")
    done
    # Insertion sort (a handful of names; no subshell)
    local i j item
    for ((i = 1; i < ${#BU_RET[@]}; i++))
    do
        item=${BU_RET[i]}
        j=$((i - 1))
        while ((j >= 0)) && [[ "${BU_RET[j]}" > "$item" ]]
        do
            BU_RET[j + 1]=${BU_RET[j]}
            j=$((j - 1))
        done
        BU_RET[j + 1]=$item
    done
    return 0
}

# Open a config phase: settings registered until bu_config_phase_end belong
# to it. Running a phase again (re-activation) first drops its previous
# registrations, so settings that are no longer registered disappear, and
# resets their values unless exported.
#
# @arg $1 {string} phase Phase name (lowercase letters, digits, `_` and `-`)
# @option --static (optional): resolve once per shell; values are exported and
#   final. Beginning a static phase that is already final re-checks it
#   instead: registrations are ignored and bu_config_phase_end restores any
#   changed value.
# @option --variant VARIANT (optional): the active variant (e.g. a profile): its
#   settings file bu_config_local.PHASE.VARIANT.sh is sourced after the
#   phase's shared one, and `--default-for VARIANT` defaults apply. Settings
#   registered only for some variants come and go as the phase runs again.
# @option --prefix PREFIX (optional): every setting of the phase must start with
#   PREFIX, so phases (e.g. profiles) cannot collide by accident
# @option --settings-file [ORIGIN:]PATH (optional, repeatable): one more settings
#   file of the phase, attributed as ORIGIN (default `local`; not one of the
#   reserved `env`, `shell`, `default`, `callback`, `site`). Split at the
#   first colon; a relative PATH is resolved against $PWD now. Files are
#   sourced in the order declared, later ones winning; a missing one is
#   skipped. The bare `--settings-file local` marks where the phase's
#   built-in files (bu_config_local.PHASE[.VARIANT].sh) go; without it they
#   come first. E.g. a profile's layers, lowest precedence first:
#   `--settings-file user:$HOME/.myapp.sh --settings-file local
#   --settings-file profile:profiles/$P.sh`
#
# @returns None (always 0; errors are logged)
# bash-ide parse-func-sig
bu_config_phase_begin()
{
    local -r phase=$1
    shift
    local is_static=false variant= prefix= spec origin path files= has_local=false
    while (($#))
    do
        case "$1" in
        --static) is_static=true ;;
        --variant) variant=${2:-}; shift ;;
        --prefix) prefix=${2:-}; shift ;;
        --settings-file)
            spec=${2:-}
            (($# > 1)) && shift
            origin=local
            path=$spec
            if [[ "$spec" == *:* ]]
            then
                origin=${spec%%:*}
                path=${spec#*:}
            fi
            if [[ "$spec" == local ]]
            then
                if "$has_local"
                then
                    bu_basic_log_err "bu_config_phase_begin: --settings-file local given twice; ignoring the second"
                else
                    has_local=true
                    files+=local$'\n'
                fi
            elif [[ -z "$path" ]]
            then
                bu_basic_log_err "bu_config_phase_begin: --settings-file[$spec]: empty path; ignoring it"
            elif [[ ! "$origin" =~ ^[a-z][a-z0-9_-]*$ ]]
            then
                bu_basic_log_err "bu_config_phase_begin: --settings-file[$spec]: invalid origin[$origin]; ignoring it"
            elif [[ "$origin" =~ ^(env|shell|default|callback|site)$ ]]
            then
                bu_basic_log_err "bu_config_phase_begin: --settings-file[$spec]: origin[$origin] is reserved; ignoring it"
            elif [[ "$path" == *$'\n'* ]]
            then
                bu_basic_log_err "bu_config_phase_begin: --settings-file[$spec]: path contains a newline; ignoring it"
            else
                [[ "$path" == /* ]] || path=$PWD/${path#./}
                files+=$origin:$path$'\n'
            fi
            ;;
        *) bu_basic_log_err "bu_config_phase_begin: unrecognized option[$1]" ;;
        esac
        shift
    done
    if [[ -n "$variant" && ! "$variant" =~ ^[a-z0-9][a-z0-9_-]*$ ]]
    then
        bu_basic_log_err "bu_config_phase_begin: invalid variant name[$variant]"
        variant=
    fi
    if [[ ! "$phase" =~ ^[a-z0-9][a-z0-9_-]*$ ]]
    then
        bu_basic_log_err "bu_config_phase_begin: invalid phase name[$phase]"
        return 0
    fi
    if [[ -n "$__BU_CONFIG_OPEN_PHASE" && "$__BU_CONFIG_OPEN_PHASE" != "$phase" ]]
    then
        bu_basic_log_err "bu_config_phase_begin: config phase '$__BU_CONFIG_OPEN_PHASE' is still open; closing it without resolving"
    fi
    __BU_CONFIG_RECHECK=false
    if "$is_static"
    then
        __BU_CONFIG_PHASE_STATIC[$phase]=true
        if [[ "${BU_CONFIG_PHASE_STATE[$phase]:-}" == final ]]
        then
            __BU_CONFIG_RECHECK=true
            __BU_CONFIG_OPEN_PHASE=$phase
            return 0
        fi
    fi

    __bu_config_phase_drop "$phase"
    __BU_CONFIG_PHASE_VARIANT[$phase]=$variant
    __BU_CONFIG_PHASE_PREFIX[$phase]=$prefix
    if [[ -n "$files" ]]
    then
        __BU_CONFIG_PHASE_FILES[$phase]=$files
    else
        unset '__BU_CONFIG_PHASE_FILES[$phase]'
    fi
    BU_CONFIG_PHASE_STATE[$phase]=open
    __BU_CONFIG_OPEN_PHASE=$phase
    return 0
}

# Drop a config phase's registrations, unsetting their values unless
# exported (the user's).
#
# @arg $1 {string} phase Phase name
#
# @returns None (always 0)
# bash-ide parse-func-sig
__bu_config_phase_drop()
{
    local -r phase=$1
    local name key attrs
    local -A dropped=()
    __bu_config_phase_settings "$phase"
    for name in "${BU_RET[@]}"
    do
        dropped[$name]=1
        attrs=${!name@a}
        if [[ -v "$name" && "$attrs" != *x* && "$attrs" != *r* ]]
        then
            unset "$name"
        fi
        unset '__BU_CONFIG_USER[$name]' '__BU_CONFIG_USER_KIND[$name]' \
            'BU_CONFIG_ORIGIN[$name]' 'BU_CONFIG_SOURCE_FILE[$name]' '__BU_CONFIG_APPLIED[$name]'
    done
    if ((${#dropped[@]}))
    then
        for key in "${!BU_CONFIG_PROPERTIES[@]}"
        do
            [[ -v "dropped[${key%%,*}]" ]] && unset 'BU_CONFIG_PROPERTIES[$key]'
        done
    fi
    return 0
}

# Unload a (non-static) config phase, e.g. to deactivate a profile: drop its
# registrations and unset its values, except exported ones.
#
# @arg $1 {string} phase Phase name
#
# @returns None (always 0; errors are logged)
# bash-ide parse-func-sig
bu_config_phase_unload()
{
    local -r phase=$1
    if [[ "${__BU_CONFIG_PHASE_STATIC[$phase]:-}" == true ]]
    then
        bu_basic_log_err "bu_config_phase_unload: '$phase' is a static config phase, final for this shell"
        return 0
    fi
    __bu_config_phase_drop "$phase"
    unset 'BU_CONFIG_PHASE_STATE[$phase]' '__BU_CONFIG_PHASE_VARIANT[$phase]' '__BU_CONFIG_PHASE_PREFIX[$phase]' \
        '__BU_CONFIG_PHASE_FILES[$phase]'
    [[ "$__BU_CONFIG_OPEN_PHASE" == "$phase" ]] && __BU_CONFIG_OPEN_PHASE=
    return 0
}

# List a config phase's built-in settings files, in order (later files win).
# For each level, the checkout's file comes first, then the embedder's
# BU_CONFIG_LOCAL_FILE counterpart. The main phase uses bu_config_local.sh
# itself plus site/*.sh; another phase PHASE uses bu_config_local.PHASE.sh,
# then, with an active variant, bu_config_local.PHASE.VARIANT.sh.
#
# @arg $1 {string} phase Phase name
# @arg $2 {string} [include_missing=false] `true` to include files that do not exist (site files
#   are always only the existing ones)
# @set BU_RET "ORIGIN:PATH" entries
# bash-ide parse-func-sig
__bu_config_phase_builtin_files()
{
    local -r phase=$1
    local -r include_missing=${2:-false}
    local -r variant=${__BU_CONFIG_PHASE_VARIANT[$phase]:-}
    local -a suffixes=(.sh)
    if [[ "$phase" != main ]]
    then
        suffixes=(".$phase.sh")
        [[ -n "$variant" ]] && suffixes+=(".$phase.$variant.sh")
    fi
    local suffix checkout embedder
    local -a files=()
    for suffix in "${suffixes[@]}"
    do
        checkout=$BU_DIR/config/bu_config_local$suffix
        if "$include_missing" || [[ -f "$checkout" ]]
        then
            files+=("local:$checkout")
        fi
        if [[ -n "${BU_CONFIG_LOCAL_FILE:-}" ]]
        then
            embedder=${BU_CONFIG_LOCAL_FILE%.sh}$suffix
            [[ "$embedder" == /* ]] || embedder=$PWD/${embedder#./}
            if [[ "$embedder" != "$checkout" ]] && { "$include_missing" || [[ -f "$embedder" ]]; }
            then
                files+=("local:$embedder")
            fi
        fi
    done
    if [[ "$phase" == main && -d "$BU_DIR/site" ]]
    then
        local site_file
        for site_file in "$BU_DIR"/site/*.sh
        do
            [[ -f "$site_file" ]] && files+=("site:$site_file")
        done
    fi
    BU_RET=("${files[@]}")
    return 0
}

# List the settings files a config phase reads, in the order
# bu_config_phase_end sources them (later files win): its extra files
# (`bu_config_phase_begin --settings-file`) with the built-in files expanded
# where `--settings-file local` was given, or first without it. Files that
# do not exist are included (bu_config_phase_end skips them), so a doctor
# command can show where the phase would read its settings from.
#
# @arg $1 {string} phase Phase name
# @set BU_RET "ORIGIN:PATH" entries
# bash-ide parse-func-sig
bu_config_phase_files()
{
    local -r phase=$1
    local -r declared=${__BU_CONFIG_PHASE_FILES[$phase]:-}
    local -a entries=() files=()
    local entry
    [[ -n "$declared" ]] && mapfile -t entries <<<"${declared%$'\n'}"
    [[ $'\n'"$declared" == *$'\nlocal\n'* ]] || entries=(local "${entries[@]}")
    for entry in "${entries[@]}"
    do
        if [[ "$entry" == local ]]
        then
            __bu_config_phase_builtin_files "$phase" true
            files+=("${BU_RET[@]}")
        else
            files+=("$entry")
        fi
    done
    BU_RET=("${files[@]}")
    return 0
}

# The settings files a config phase sources (bu_config_phase_files), only
# those that exist.
#
# @arg $1 string Phase name
# @set BU_RET "ORIGIN:PATH" entries for the files that exist
__bu_config_phase_files()
{
    local entry
    local -a files=()
    bu_config_phase_files "$1"
    for entry in "${BU_RET[@]}"
    do
        [[ -f "${entry#*:}" ]] && files+=("$entry")
    done
    BU_RET=("${files[@]}")
    return 0
}

# Origin label of a file a config phase reads (bu_config_phase_files), for
# `bu set-config`: "local" for its built-in files, ORIGIN for a file declared
# with `bu_config_phase_begin --settings-file ORIGIN:PATH`.
#
# @arg $1 {string} phase Phase name
# @arg $2 {string} file Absolute path
# @set BU_RET the file's ORIGIN, or empty if the phase does not read it
#   (the last entry wins if it is listed more than once)
# bash-ide parse-func-sig
__bu_config_phase_file_origin()
{
    local -r phase=$1
    local -r file=$2
    local entry origin=
    bu_config_phase_files "$phase"
    for entry in "${BU_RET[@]}"
    do
        [[ "${entry#*:}" == "$file" ]] && origin=${entry%%:*}
    done
    BU_RET=$origin
    return 0
}

# First half of resolving a config phase: save the phase's exported values,
# reset its unexported ones (a static phase keeps them as the user's too), and
# snapshot every registered setting so the
# settings files sourced next can be attributed (__bu_config_phase_track).
# bu_config_phase_end calls the three steps; the entrypoint calls them itself
# to source the main phase's files at top level.
#
# @arg $1 {string} phase Phase name (must be the open phase)
#
# @returns None (always 0)
# bash-ide parse-func-sig
__bu_config_phase_prepare()
{
    local -r phase=$1
    local name attrs
    __bu_config_phase_settings "$phase"
    __BU_CONFIG_PHASE_NAMES=("${BU_RET[@]}")
    local -r is_static=${__BU_CONFIG_PHASE_STATIC[$phase]:-false}
    for name in "${__BU_CONFIG_PHASE_NAMES[@]}"
    do
        unset '__BU_CONFIG_USER[$name]' '__BU_CONFIG_USER_KIND[$name]' \
            'BU_CONFIG_ORIGIN[$name]' 'BU_CONFIG_SOURCE_FILE[$name]'
        [[ -v "$name" ]] || continue
        attrs=${!name@a}
        if [[ "$attrs" == *x* ]]
        then
            __BU_CONFIG_USER[$name]=${!name}
            __BU_CONFIG_USER_KIND[$name]=env
        elif "$is_static"
        then
            # Static values are exported once final, so a value set before
            # the phase reaches child processes too: it counts as the user's
            __BU_CONFIG_USER[$name]=${!name}
            __BU_CONFIG_USER_KIND[$name]=shell
        elif [[ "$attrs" != *r* ]]
        then
            unset "$name"
        fi
    done
    __bu_config_snapshot
    return 0
}

# Snapshot every registered setting (scratch for __bu_config_phase_track)
# bash-ide parse-func-sig
__bu_config_snapshot()
{
    local key name
    __BU_CONFIG_SNAP=()
    for key in "${!BU_CONFIG_PROPERTIES[@]}"
    do
        [[ "$key" == *,registered ]] || continue
        name=${key%,registered}
        [[ -v "$name" ]] && __BU_CONFIG_SNAP[$name]=${!name}
    done
    return 0
}

# After sourcing one settings file for the phase being resolved: attribute
# the phase's settings it assigned to it, and revert (with a warning) any
# assignment to a setting owned by another phase that has already finished.
#
# @arg $1 {string} file Absolute path of the file just sourced (empty for callbacks)
# @arg $2 {string} origin Origin to record (`local`, `site` or `callback`)
#
# @returns None (always 0)
# bash-ide parse-func-sig
__bu_config_phase_track()
{
    local -r file=$1
    local -r origin=$2
    local -r phase=$__BU_CONFIG_OPEN_PHASE
    local key name owner
    for key in "${!BU_CONFIG_PROPERTIES[@]}"
    do
        [[ "$key" == *,registered ]] || continue
        name=${key%,registered}
        if [[ -v "$name" ]]
        then
            [[ -v "__BU_CONFIG_SNAP[$name]" && "${__BU_CONFIG_SNAP[$name]}" == "${!name}" ]] && continue
        else
            [[ -v "__BU_CONFIG_SNAP[$name]" ]] || continue
        fi
        owner=${BU_CONFIG_PROPERTIES[$name,phase]:-}
        if [[ "$owner" == "$phase" && "${BU_CONFIG_PROPERTIES[$name,env_only]:-}" == true ]]
        then
            bu_basic_log_warn "${file:-$origin}: ignoring assignment to $name, which only the environment can set"
            if [[ -v "__BU_CONFIG_SNAP[$name]" ]]
            then
                printf -v "$name" '%s' "${__BU_CONFIG_SNAP[$name]}" || true
            else
                unset "$name"
            fi
        elif [[ "$owner" == "$phase" || "${BU_CONFIG_PHASE_STATE[$owner]:-}" != final ]]
        then
            # Ours, or a later phase's (that phase resets it when it runs)
            [[ "$owner" == "$phase" && -v "$name" ]] || continue
            BU_CONFIG_ORIGIN[$name]=$origin
            if [[ -n "$file" ]]
            then
                BU_CONFIG_SOURCE_FILE[$name]=$file
            else
                unset 'BU_CONFIG_SOURCE_FILE[$name]'
            fi
            __BU_CONFIG_SNAP[$name]=${!name}
        else
            bu_basic_log_warn "${file:-$origin}: ignoring assignment to $name, a setting of config phase '$owner' (set it in that phase's settings file)"
            if [[ -v "__BU_CONFIG_SNAP[$name]" ]]
            then
                printf -v "$name" '%s' "${__BU_CONFIG_SNAP[$name]}" || true
            else
                unset "$name"
            fi
        fi
    done
    return 0
}

# Second half of resolving a config phase: restore the saved exported
# values, then apply registered defaults by generating the phase's vars file
# (one `NAME=${NAME:-default}` line per setting, documented for editors) and
# sourcing it, and record the resulting values.
#
# @arg $1 {string} phase Phase name (must be the open phase)
#
# @returns None (always 0)
# bash-ide parse-func-sig
__bu_config_phase_complete()
{
    local -r phase=$1
    local name
    for name in "${__BU_CONFIG_PHASE_NAMES[@]}"
    do
        [[ -v "__BU_CONFIG_USER[$name]" ]] || continue
        if [[ "${!name-}" != "${__BU_CONFIG_USER[$name]}" ]]
        then
            printf -v "$name" '%s' "${__BU_CONFIG_USER[$name]}" || true
        fi
        BU_CONFIG_ORIGIN[$name]=${__BU_CONFIG_USER_KIND[$name]}
        unset 'BU_CONFIG_SOURCE_FILE[$name]'
    done

    # Settings registered while the files ran (callbacks) count too
    __bu_config_phase_settings "$phase"
    __BU_CONFIG_PHASE_NAMES=("${BU_RET[@]}")
    __bu_config_write_vars_file "$phase"
    if [[ -n "$BU_RET" ]]
    then
        # shellcheck disable=SC1090
        builtin source "$BU_RET"
    fi
    for name in "${__BU_CONFIG_PHASE_NAMES[@]}"
    do
        __BU_CONFIG_APPLIED[$name]=${!name-}
        if [[ "${__BU_CONFIG_PHASE_STATIC[$phase]:-}" == true ]]
        then
            export "$name"
        fi
    done

    BU_CONFIG_PHASE_STATE[$phase]=final
    __BU_CONFIG_OPEN_PHASE=
    return 0
}

# Path of a config phase's generated vars file:
# $BU_OUT_DIR/cache/config-vars/<top-level module>/<BashTab dir>/<phase>[.<variant>].sh
# (the BashTab dir with every character outside [A-Za-z0-9._-] replaced by
# `_`, so checkouts sharing a module name never share a file).
#
# @arg $1 {string} phase Phase name
# @set BU_RET the file path
# bash-ide parse-func-sig
__bu_config_vars_file()
{
    local -r phase=$1
    local -r variant=${__BU_CONFIG_PHASE_VARIANT[$phase]:-}
    BU_RET=${BU_OUT_DIR:-/tmp/bu/${USER:-unknown}}/cache/config-vars/${BU_TOP_LEVEL_MODULE:-default}/${BU_DIR//[^A-Za-z0-9._-]/_}/$phase${variant:+.$variant}.sh
    return 0
}

# Generate the vars file of a config phase from the registry, rewriting it
# only when its content changes (so it stays stable for editors and the
# usual activation needs no extra processes).
#
# @arg $1 string Phase name
# @set BU_RET the file path (__bu_config_vars_file), or empty if it could not
#   be written
__bu_config_write_vars_file()
{
    local -r phase=$1
    __bu_config_vars_file "$phase"
    local -r file=$BU_RET
    local -r dir=${file%/*}
    local content name default quoted allowed entry
    printf -v content '%s\n' \
        "# Generated by BashTab from the registered settings of config phase '$phase${__BU_CONFIG_PHASE_VARIANT[$phase]:+ (variant ${__BU_CONFIG_PHASE_VARIANT[$phase]})}'." \
        "# Do not edit: rewritten whenever the registered settings change."
    for name in "${__BU_CONFIG_PHASE_NAMES[@]}"
    do
        content+=$'\n'
        [[ -n "${BU_CONFIG_PROPERTIES[$name,hint]:-}" ]] && content+="# ${BU_CONFIG_PROPERTIES[$name,hint]}"$'\n'
        allowed=
        if [[ "${BU_CONFIG_PROPERTIES[$name,bool]:-}" == true ]]
        then
            allowed='true false'
        else
            for entry in ${BU_CONFIG_PROPERTIES[$name,enum]:-}
            do
                allowed+="${allowed:+ }${entry%%:*}"
            done
        fi
        default=${BU_CONFIG_PROPERTIES[$name,default]:-}
        content+="#${allowed:+ allowed: $allowed |} default: ${default:-(empty)} | declared: ${BU_CONFIG_PROPERTIES[$name,defined_at]:-?}"$'\n'
        quoted=
        [[ -n "$default" ]] && printf -v quoted '%q' "$default"
        content+="$name=\${$name:-$quoted}"$'\n'
    done

    BU_RET=
    local existing=
    if [[ -f "$file" ]]
    then
        IFS= read -r -d '' existing < "$file" || true
    fi
    if [[ "$existing" != "$content" ]]
    then
        if [[ ! -d "$dir" ]] && ! mkdir -p "$dir" 2>/dev/null
        then
            bu_basic_log_err "Cannot create $dir; config phase '$phase' defaults not applied"
            return 0
        fi
        if ! { printf '%s' "$content" > "$file.$$" && mv -f "$file.$$" "$file"; } 2>/dev/null
        then
            bu_basic_log_err "Cannot write $file; config phase '$phase' defaults not applied"
            rm -f "$file.$$" 2>/dev/null
            return 0
        fi
    fi
    BU_RET=$file
    return 0
}

# Close and resolve a config phase: save exported values, source the phase's
# settings files (bu_config_phase_files: its --settings-file files and its
# built-in ones, in order, skipping missing files) with each assignment
# attributed to its file's origin, restore the exported values, then apply
# defaults. Call after the phase's settings are registered.
#
# @arg $1 {string} phase Phase name (must be the open phase)
#
# @returns None (always 0; errors are logged)
# bash-ide parse-func-sig
bu_config_phase_end()
{
    local -r phase=$1
    if [[ "$__BU_CONFIG_OPEN_PHASE" != "$phase" ]]
    then
        bu_basic_log_err "bu_config_phase_end: config phase '$phase' is not open"
        return 0
    fi
    if "$__BU_CONFIG_RECHECK"
    then
        __bu_config_static_recheck "$phase"
        return 0
    fi
    __bu_config_phase_prepare "$phase"
    local entry
    __bu_config_phase_files "$phase"
    local -a files=("${BU_RET[@]}")
    for entry in "${files[@]}"
    do
        # shellcheck disable=SC1090
        source "${entry#*:}"
        __bu_config_phase_track "${entry#*:}" "${entry%%:*}"
    done
    __bu_config_phase_complete "$phase"
    return 0
}

# Re-check a final static phase (re-activation): its values are final for
# the shell, so any that changed since are restored, with a warning.
#
# @arg $1 {string} phase Phase name
#
# @returns None (always 0)
# bash-ide parse-func-sig
__bu_config_static_recheck()
{
    local -r phase=$1
    local name
    __bu_config_phase_settings "$phase"
    for name in "${BU_RET[@]}"
    do
        [[ -v "__BU_CONFIG_APPLIED[$name]" ]] || continue
        if [[ "${!name-}" != "${__BU_CONFIG_APPLIED[$name]}" ]]
        then
            bu_basic_log_warn "$name is a static setting, final for this shell: keeping '${__BU_CONFIG_APPLIED[$name]}', ignoring '${!name-}' (open a new shell to change it)"
            printf -v "$name" '%s' "${__BU_CONFIG_APPLIED[$name]}" || true
        fi
        export "$name"
    done
    __BU_CONFIG_RECHECK=false
    __BU_CONFIG_OPEN_PHASE=
    return 0
}

# Make the static phases resolvable again, for re-initializing a shell
# (`bu import-environment --reset-source`): unset the static values BashTab
# set, keeping the ones the user supplied, and forget that the phases ran.
#
# @noargs
#
# @returns None (always 0)
# bash-ide parse-func-sig
__bu_config_static_reset()
{
    local phase name
    for phase in "${!__BU_CONFIG_PHASE_STATIC[@]}"
    do
        __bu_config_phase_settings "$phase"
        for name in "${BU_RET[@]}"
        do
            case "${BU_CONFIG_ORIGIN[$name]:-}" in
            env|shell) ;;
            *) unset "$name" ;;
            esac
        done
        unset 'BU_CONFIG_PHASE_STATE[$phase]'
    done
    return 0
}

# Record a value `bu set-config` just applied in this shell, so provenance
# follows it instead of reporting a change in the shell.
#
# @arg $1 {string} name Setting name
# @arg $2 {string} origin Origin: `local`, `layer`, or `default` (after --unset)
# @arg $3 {string} [file] Settings file written (ignored for `default`)
#
# @returns None (always 0)
# bash-ide parse-func-sig
__bu_config_mark_applied()
{
    local -r name=$1
    local -r origin=$2
    local -r file=${3:-}
    unset '__BU_CONFIG_USER[$name]' '__BU_CONFIG_USER_KIND[$name]'
    if [[ "$origin" == default ]]
    then
        unset 'BU_CONFIG_ORIGIN[$name]' 'BU_CONFIG_SOURCE_FILE[$name]'
    else
        BU_CONFIG_ORIGIN[$name]=$origin
        BU_CONFIG_SOURCE_FILE[$name]=$file
    fi
    __BU_CONFIG_APPLIED[$name]=${!name-}
    return 0
}

# Row action of `bu edit-config`, run inside `bu view-table` (a separate
# process) on the cursor record in BU_TV_RECORD: change the setting with
# `bu set-config`, and queue the change in $BU_CONFIG_EDIT_QUEUE so
# edit-config applies it to the calling shell once the viewer exits (a
# static setting is stored for new shells only, so it is not queued). The
# last line printed becomes the viewer's status message.
#
# @arg $1 {string} mode `cycle` (next true/false or allowed value), `unset` (registered
#   default), `prompt` (type a value), `open` (open its location, as
#   `bu get-config` reports it, in $VISUAL / $EDITOR: the settings file line
#   that set it, or where a defaulted setting is registered)
#
# @returns
# - The `bu set-config` status (non-zero shows as a failure)
# bash-ide parse-func-sig
__bu_config_edit_action()
{
    local -r mode=$1
    local name= location= current next entry
    local -i i n
    IFS=$'\t' read -r name location < <("$BU_OUT_JQ" -r '[.name, (.location // "")] | @tsv' <<<"${BU_TV_RECORD:-}" 2>/dev/null)
    if [[ "${BU_CONFIG_PROPERTIES[$name,registered]:-}" != true ]]
    then
        echo "Not a registered setting: ${name:-?}"
        return 1
    fi
    current=${!name-}

    case "$mode" in
    cycle)
        if [[ "${BU_CONFIG_PROPERTIES[$name,bool]:-}" == true ]]
        then
            next=true
            [[ "$current" == true ]] && next=false
        elif [[ -n "${BU_CONFIG_PROPERTIES[$name,enum]:-}" ]]
        then
            local -a entries=(${BU_CONFIG_PROPERTIES[$name,enum]})
            n=${#entries[@]}
            next=${entries[0]%%:*}
            for (( i = 0; i < n; i++ ))
            do
                entry=${entries[i]}
                if [[ "${entry#*:}" == "$current" || "${entry%%:*}" == "$current" ]]
                then
                    entry=${entries[(i + 1) % n]}
                    next=${entry%%:*}
                    break
                fi
            done
        else
            echo "$name takes any value: press e to edit it"
            return 0
        fi
        bu set-config "$name" "$next" || return
        __bu_config_edit_queue "$name"
        ;;
    unset)
        bu set-config --unset "$name" || return
        __bu_config_edit_queue "$name" --unset
        ;;
    prompt)
        if ! bu_tv_prompt "$name=" "$current"
        then
            echo "Cancelled"
            return 0
        fi
        bu set-config "$name" "$BU_RET" || return
        __bu_config_edit_queue "$name"
        ;;
    open)
        if [[ -z "$location" ]]
        then
            echo "$name has no settings file to open (origin ${BU_CONFIG_ORIGIN[$name]:-shell})"
            return 0
        fi
        local file=$location line=
        if [[ "$location" =~ ^(.*):([0-9]+)$ ]]
        then
            file=${BASH_REMATCH[1]}
            line=${BASH_REMATCH[2]}
        fi
        bu_tv_interactive "${VISUAL:-${EDITOR:-vi}}" ${line:+"+$line"} "$file" || return
        echo "Edited $file (hand edits apply on the next activation)"
        ;;
    *)
        echo "Unknown edit action: $mode"
        return 1
        ;;
    esac
}

# Queue a change `bu set-config` just applied in this process, for
# __bu_config_apply_live in the shell running `bu edit-config`
__bu_config_edit_queue()
{
    local -r name=$1
    local -r phase=${BU_CONFIG_PROPERTIES[$name,phase]:-main}
    [[ -n "${BU_CONFIG_EDIT_QUEUE:-}" ]] || return 0
    [[ "${__BU_CONFIG_PHASE_STATIC[$phase]:-}" == true ]] && return 0
    if [[ "${2:-}" == --unset ]]
    then
        printf '__bu_config_apply_live --unset %q\n' "$name" >> "$BU_CONFIG_EDIT_QUEUE"
    else
        printf '__bu_config_apply_live %q %q %q\n' "$name" "${!name-}" "${BU_CONFIG_SOURCE_FILE[$name]:-}" >> "$BU_CONFIG_EDIT_QUEUE"
    fi
    return 0
}

# *Description*:
# Apply a change queued by __bu_config_edit_action to this shell: the value
# (already stored in its settings file) and its provenance.
#
# *Params*:
# - `NAME VALUE [FILE]`, or `--unset NAME` (the registered default)
#
# *Returns*: None (always 0)
__bu_config_apply_live()
{
    if [[ "$1" == --unset ]]
    then
        local -r unset_name=$2
        declare -g "$unset_name=${BU_CONFIG_PROPERTIES[$unset_name,default]:-}"
        __bu_config_mark_applied "$unset_name" default
        return 0
    fi
    local -r name=$1 value=$2 file=${3:-}
    declare -g "$name=$value"
    __bu_config_mark_applied "$name" local "$file"
    return 0
}

# Validate a value against a registered setting and map it to its stored form.
# Unregistered settings (or registered ones without --bool/--enum) pass through.
#
# @arg $1 {string} name Setting name
# @arg $2 {string} value Candidate value
# @set BU_RET the value to store (mapped form for name:mapped enum entries)
#
# @returns
# - Exit code: 0 if valid, 1 if rejected
# bash-ide parse-func-sig
bu_config_validate_value()
{
    local name=$1 value=$2
    if [[ "${BU_CONFIG_PROPERTIES[$name,bool]:-}" == true ]]
    then
        case "$value" in
        true|false) BU_RET=$value; return 0 ;;
        *) BU_RET="expected true|false"; return 1 ;;
        esac
    fi
    local enum=${BU_CONFIG_PROPERTIES[$name,enum]:-}
    if [[ -n "$enum" ]]
    then
        local entry entry_name
        for entry in $enum
        do
            entry_name=${entry%%:*}
            if [[ "$value" == "$entry_name" ]]
            then
                # name:mapped stores the mapped form; bare name stores itself
                BU_RET=${entry#*:}
                return 0
            fi
        done
        BU_RET="expected one of: $enum"
        return 1
    fi
    BU_RET=$value
    return 0
}

# MARK: File-backed enums

# Join enum values into the space-separated form of
# BU_CONFIG_PROPERTIES[NAME,enum], dropping repeats (first one wins).
#
# @arg $@ {string} args... values (`name` or `name:mapped`)
# @set BU_RET the joined values
# bash-ide parse-func-sig
__bu_config_enum_join()
{
    local value joined=
    local -A seen=()
    for value in "$@"
    do
        [[ -n "$value" && ! -v "seen[$value]" ]] || continue
        seen[$value]=1
        joined+="${joined:+ }$value"
    done
    BU_RET=$joined
    return 0
}

# The value on one line of an enum file or of an --enum-source's output: the
# first word, or nothing for a blank line or a `#` comment.
#
# @arg $1 {string} line the line
# @set BU_RET the value, or empty
# bash-ide parse-func-sig
__bu_config_enum_line_value()
{
    local line=$1
    line=${line#"${line%%[![:space:]]*}"}
    if [[ "$line" == '#'* ]]
    then
        BU_RET=
    else
        BU_RET=${line%%[[:space:]]*}
    fi
    return 0
}

# Read an --enum-file into its sections (the __BU_CONFIG_ENUM_* scratch
# arrays): the header (leading comment and blank lines), the values after
# `# --- generated (NOTE) ---`, and the values and lines after
# `# --- hand-kept ---`. Values before any marker, and every value of a file
# without markers, count as generated.
#
# @arg $1 {string} file file path (a missing file reads as empty)
#
# @returns None (always 0)
# bash-ide parse-func-sig
__bu_config_parse_enum_file()
{
    local -r file=$1
    local -r gen_re='^#[[:space:]]*---[[:space:]]*generated([[:space:]].*)?---[[:space:]]*$'
    local -r hand_re='^#[[:space:]]*---[[:space:]]*hand-kept[[:space:]]*---[[:space:]]*$'
    local -a lines=()
    local line section=header
    __BU_CONFIG_ENUM_HEADER=()
    __BU_CONFIG_ENUM_GENERATED=()
    __BU_CONFIG_ENUM_HAND_KEPT=()
    __BU_CONFIG_ENUM_HAND_KEPT_LINES=()
    [[ -r "$file" ]] && mapfile -t lines < "$file"
    for line in "${lines[@]}"
    do
        if [[ "$line" =~ $gen_re ]]
        then
            section=generated
            continue
        fi
        if [[ "$line" =~ $hand_re ]]
        then
            section=hand-kept
            continue
        fi
        __bu_config_enum_line_value "$line"
        case "$section" in
        header)
            if [[ -z "$BU_RET" ]]
            then
                __BU_CONFIG_ENUM_HEADER+=("$line")
            else
                section=generated
                __BU_CONFIG_ENUM_GENERATED+=("$BU_RET")
            fi
            ;;
        generated)
            [[ -n "$BU_RET" ]] && __BU_CONFIG_ENUM_GENERATED+=("$BU_RET")
            ;;
        hand-kept)
            __BU_CONFIG_ENUM_HAND_KEPT_LINES+=("$line")
            [[ -n "$BU_RET" ]] && __BU_CONFIG_ENUM_HAND_KEPT+=("$BU_RET")
            ;;
        esac
    done
    # Blank lines between the header and the first section are layout
    while ((${#__BU_CONFIG_ENUM_HEADER[@]})) && [[ -z "${__BU_CONFIG_ENUM_HEADER[-1]//[[:space:]]/}" ]]
    do
        unset '__BU_CONFIG_ENUM_HEADER[-1]'
    done
    while ((${#__BU_CONFIG_ENUM_HAND_KEPT_LINES[@]})) && [[ -z "${__BU_CONFIG_ENUM_HAND_KEPT_LINES[-1]//[[:space:]]/}" ]]
    do
        unset '__BU_CONFIG_ENUM_HAND_KEPT_LINES[-1]'
    done
    return 0
}

# Refresh a setting's --enum-file from its --enum-source: run the source,
# compare its values with the file's generated section, and print what
# changes. With --execute, rewrite the file (header kept, generated section
# replaced under a dated marker, hand-kept section kept) and update the live
# BU_CONFIG_PROPERTIES[NAME,enum]. An unchanged file is not rewritten.
#
# @arg $1 string setting name (registered with --enum-file and --enum-source)
# @option --execute (optional): write the file
# @stdout TSV rows `name file kind value action`: one `added` / `removed`
#   row per value, then one `summary` row ("N generated, M hand-kept, +a -r");
#   action `would-write`, `written` or `unchanged`
#
# @returns
# - Exit code: 0 on success, 1 when the setting has no source, the source
#   fails or prints nothing, or the file cannot be written
# bash-ide parse-func-sig
bu_config_refresh_enum_file()
{
    __BU_CONFIG_REFRESH_ROWS=()
    local status=0
    __bu_config_refresh_enum_rows "$@" || status=1
    ((${#__BU_CONFIG_REFRESH_ROWS[@]})) && printf '%s\n' "${__BU_CONFIG_REFRESH_ROWS[@]}"
    return "$status"
}

# bu_config_refresh_enum_file without printing: appends its rows to
# __BU_CONFIG_REFRESH_ROWS (so a caller can refresh several settings in this
# shell, keeping the live enum updates, and print the rows afterwards)
__bu_config_refresh_enum_rows()
{
    local name= is_execute=false
    while (($#))
    do
        case "$1" in
        --execute) is_execute=true ;;
        *)
            if [[ -n "$name" ]]
            then
                bu_log_err "bu_config_refresh_enum_file: unexpected argument[$1]"
                return 1
            fi
            name=$1
            ;;
        esac
        shift
    done
    local -r file=${BU_CONFIG_PROPERTIES[$name,enum_file]:-}
    local -r src=${BU_CONFIG_PROPERTIES[$name,enum_source]:-}
    if [[ "${BU_CONFIG_PROPERTIES[$name,registered]:-}" != true ]]
    then
        bu_log_err "${name:-(no setting)} is not a registered setting"
        return 1
    fi
    if [[ -z "$file" || -z "$src" ]]
    then
        bu_log_err "$name has no --enum-source to refresh its --enum-file from"
        return 1
    fi

    local output= line value
    if ! output=$(eval "$src")
    then
        bu_log_err "$name: --enum-source[$src] failed; $file left as it is"
        return 1
    fi
    local -a fresh=()
    local -A in_fresh=()
    while IFS= read -r line
    do
        __bu_config_enum_line_value "$line"
        value=$BU_RET
        [[ -n "$value" && ! -v "in_fresh[$value]" ]] || continue
        in_fresh[$value]=1
        fresh+=("$value")
    done <<<"$output"
    if ((${#fresh[@]} == 0))
    then
        bu_log_err "$name: --enum-source[$src] printed no values; $file left as it is"
        return 1
    fi

    __bu_config_parse_enum_file "$file"
    local -a added=() removed=()
    local -A in_old=()
    for value in "${__BU_CONFIG_ENUM_GENERATED[@]}"
    do
        in_old[$value]=1
        [[ -v "in_fresh[$value]" ]] || removed+=("$value")
    done
    for value in "${fresh[@]}"
    do
        [[ -v "in_old[$value]" ]] || added+=("$value")
    done

    local action=unchanged
    if ((${#added[@]} + ${#removed[@]})) || [[ ! -f "$file" ]]
    then
        action=would-write
        if "$is_execute"
        then
            local content= section= today
            printf -v today '%(%Y-%m-%d)T' -1
            if ((${#__BU_CONFIG_ENUM_HEADER[@]}))
            then
                printf -v content '%s\n' "${__BU_CONFIG_ENUM_HEADER[@]}"
            else
                printf -v content '%s\n' \
                    "# Allowed values of $name, one per line (bu_config_register --enum-file)." \
                    "# The generated section is rewritten by \`bu update-config-enum $name --execute\`;" \
                    "# add values the source does not know under the hand-kept marker."
            fi
            printf -v section '%s\n' "${fresh[@]}"
            content+=$'\n'"# --- generated ($src, $today) ---"$'\n'$section
            content+=$'\n'"# --- hand-kept ---"$'\n'
            if ((${#__BU_CONFIG_ENUM_HAND_KEPT_LINES[@]}))
            then
                printf -v section '%s\n' "${__BU_CONFIG_ENUM_HAND_KEPT_LINES[@]}"
                content+=$section
            fi
            if ! { printf '%s' "$content" > "$file.$$" && mv -f "$file.$$" "$file"; } 2>/dev/null
            then
                rm -f "$file.$$" 2>/dev/null
                bu_log_err "$name: cannot write $file"
                return 1
            fi
            __bu_config_enum_join "${fresh[@]}" "${__BU_CONFIG_ENUM_HAND_KEPT[@]}"
            BU_CONFIG_PROPERTIES[$name,enum]=$BU_RET
            action=written
        fi
    fi

    for value in "${added[@]}"
    do
        __BU_CONFIG_REFRESH_ROWS+=("$name"$'\t'"$file"$'\t'added$'\t'"$value"$'\t'"$action")
    done
    for value in "${removed[@]}"
    do
        __BU_CONFIG_REFRESH_ROWS+=("$name"$'\t'"$file"$'\t'removed$'\t'"$value"$'\t'"$action")
    done
    __BU_CONFIG_REFRESH_ROWS+=("$name"$'\t'"$file"$'\t'summary$'\t'"${#fresh[@]} generated, ${#__BU_CONFIG_ENUM_HAND_KEPT[@]} hand-kept, +${#added[@]} -${#removed[@]}"$'\t'"$action")
    return 0
}

# MARK: Validating settings

# Where a setting's current value came from, as `bu get-config` reports it:
# `shell` when it changed since its phase ran (or the last `bu set-config`),
# else the recorded origin (env, local, site, callback, layer, or a
# --settings-file label), else `default`.
#
# @arg $1 {string} name setting name
# @set BU_RET the origin
# bash-ide parse-func-sig
__bu_config_origin()
{
    local -r name=$1
    if [[ -v "__BU_CONFIG_APPLIED[$name]" && "${!name-}" != "${__BU_CONFIG_APPLIED[$name]}" ]]
    then
        BU_RET=shell
    else
        BU_RET=${BU_CONFIG_ORIGIN[$name]:-default}
    fi
    return 0
}

# *Description*:
# Check settings' current values against their registered rules, into
# __BU_CONFIG_VALIDATE_ROWS (TSV `name value origin status detail`), for
# bu_config_validate_settings and bu_config_require_valid.
#
# *Params*: as bu_config_validate_settings
#
# *Returns*:
# - Exit code: 0 when all pass, 1 when any is invalid
__bu_config_validate_rows()
{
    local -a names=() allowed=() entry_names=()
    local key name value origin status detail entry enum
    while (($#))
    do
        case "$1" in
        --allow)
            allowed+=("${2-}")
            (($# > 1)) && shift
            ;;
        *) names+=("$1") ;;
        esac
        shift
    done
    if ((${#names[@]} == 0))
    then
        for key in "${!BU_CONFIG_PROPERTIES[@]}"
        do
            [[ "$key" == *,registered ]] || continue
            name=${key%,registered}
            [[ -n "${BU_CONFIG_PROPERTIES[$name,enum]:-}" || "${BU_CONFIG_PROPERTIES[$name,bool]:-}" == true ]] && names+=("$name")
        done
        __bu_config_sort_names names
    fi

    local is_valid=true
    __BU_CONFIG_VALIDATE_ROWS=()
    for name in "${names[@]}"
    do
        value=
        origin=
        status=ok
        detail=
        if [[ "${BU_CONFIG_PROPERTIES[$name,registered]:-}" != true ]]
        then
            status=invalid
            detail="not a registered setting"
        else
            value=${!name-}
            __bu_config_origin "$name"
            origin=$BU_RET
            enum=${BU_CONFIG_PROPERTIES[$name,enum]:-}
            if [[ -z "$value" ]]
            then
                detail="not applicable (empty)"
            elif __bu_config_value_in "$value" "${allowed[@]}"
            then
                detail="not applicable (allowed by --allow)"
            elif [[ "${BU_CONFIG_PROPERTIES[$name,bool]:-}" == true ]]
            then
                if [[ "$value" != true && "$value" != false ]]
                then
                    status=invalid
                    detail="expected true|false"
                fi
            elif [[ -n "$enum" ]]
            then
                status=invalid
                entry_names=()
                for entry in $enum
                do
                    entry_names+=("${entry%%:*}")
                    if [[ "$value" == "${entry%%:*}" ]]
                    then
                        status=ok
                        break
                    elif [[ "$entry" == *:* && "$value" == "${entry#*:}" ]]
                    then
                        status=ok
                        detail="stored form of ${entry%%:*}"
                        break
                    fi
                done
                [[ "$status" == invalid ]] && detail="expected one of: ${entry_names[*]}"
            else
                detail="no enum or bool rule"
            fi
        fi
        [[ "$status" == invalid ]] && is_valid=false
        # One TSV row per setting, whatever the value holds
        value=${value//[$'\t\n']/ }
        __BU_CONFIG_VALIDATE_ROWS+=("$name"$'\t'"$value"$'\t'"$origin"$'\t'"$status"$'\t'"$detail")
    done
    "$is_valid"
}

# Is $1 one of the remaining arguments?
# bash-ide parse-func-sig
__bu_config_value_in()
{
    local -r needle=$1
    shift
    local item
    for item in "$@"
    do
        [[ "$item" == "$needle" ]] && return 0
    done
    return 1
}

# Sort the array named $1 in place (insertion sort; a few dozen names)
# bash-ide parse-func-sig
__bu_config_sort_names()
{
    local -n _sort_arr=$1
    local i j item
    for ((i = 1; i < ${#_sort_arr[@]}; i++))
    do
        item=${_sort_arr[i]}
        j=$((i - 1))
        while ((j >= 0)) && [[ "${_sort_arr[j]}" > "$item" ]]
        do
            _sort_arr[j + 1]=${_sort_arr[j]}
            j=$((j - 1))
        done
        _sort_arr[j + 1]=$item
    done
    return 0
}

# Check settings' current values against their registered --enum / --bool
# rules. Settings files are not validated at activation; call this (or the
# gate bu_config_require_valid) where a bad value matters, e.g. a module's
# preflight or plan verb.
#
# @arg $@ {string} args... setting names (default: every registered setting with an enum or
#   bool rule). An unregistered name is invalid. The stored form of a
#   `name:mapped` entry (BU_LOG_LVL holding 4) passes as well as the name.
# @option --allow VALUE (optional, repeatable): a sentinel that passes as "not
#   applicable" (e.g. `auto`, `none`); empty values always do
# @stdout TSV rows `name value origin status detail`; origin as
#   `bu get-config` reports it, status `ok` or `invalid`
#
# @returns
# - Exit code: 0 when all pass, 1 when any is invalid
# bash-ide parse-func-sig
bu_config_validate_settings()
{
    local status=0
    __bu_config_validate_rows "$@" || status=1
    ((${#__BU_CONFIG_VALIDATE_ROWS[@]})) && printf '%s\n' "${__BU_CONFIG_VALIDATE_ROWS[@]}"
    return "$status"
}

# *Description*:
# Gate on bu_config_validate_settings: log every invalid setting with
# bu_log_err and return 1; silent when all pass.
#
# *Params*: as bu_config_validate_settings
#
# *Returns*:
# - Exit code: 0 when all pass, 1 when any is invalid
# bash-ide parse-func-sig
bu_config_require_valid()
{
    __bu_config_validate_rows "$@" && return 0
    local row name value origin status detail
    for row in "${__BU_CONFIG_VALIDATE_ROWS[@]}"
    do
        # Split by hand: read would merge the empty fields of a tab-separated row
        name=${row%%$'\t'*}; row=${row#*$'\t'}
        value=${row%%$'\t'*}; row=${row#*$'\t'}
        origin=${row%%$'\t'*}; row=${row#*$'\t'}
        status=${row%%$'\t'*}
        detail=${row#*$'\t'}
        [[ "$status" == invalid ]] || continue
        if [[ -n "$origin" ]]
        then
            bu_log_err -i 1 "Invalid setting $name='$value' (origin $origin): $detail"
        else
            bu_log_err -i 1 "Invalid setting $name: $detail"
        fi
    done
    return 1
}

# Completion helpers (consumed by `bu set-config` via the --ret DSL specifier).
# bash-ide parse-func-sig
__bu_config_completion_names()
{
    local key
    BU_RET=()
    for key in "${!BU_CONFIG_PROPERTIES[@]}"
    do
        if [[ "$key" == *,registered ]]
        then
            BU_RET+=("${key%,registered}")
        fi
    done
}

# bash-ide parse-func-sig
__bu_config_completion_values()
{
    local name=$1
    BU_RET=()

    # Dynamic completion function takes priority over bool/enum.
    local fn=${BU_CONFIG_PROPERTIES[$name,complete_values_fn]:-}
    if [[ -n "$fn" ]]
    then
        if declare -F "$fn" &>/dev/null
        then
            # FN receives the setting name as $1, returns candidates in BU_RET.
            # Must be side-effect-free and fast (runs on every TAB).
            "$fn" "$name" || true
        fi
        return 0
    fi

    local entry
    if [[ "${BU_CONFIG_PROPERTIES[$name,bool]:-}" == true ]]
    then
        BU_RET=(true false)
        return 0
    fi
    for entry in ${BU_CONFIG_PROPERTIES[$name,enum]:-}
    do
        BU_RET+=("${entry%%:*}")
    done
    for entry in ${BU_CONFIG_PROPERTIES[$name,presets]:-}
    do
        BU_RET+=("$entry")
    done
}

# Completion helper: settings registered with --enum-source (for
# bu update-config-enum).
# bash-ide parse-func-sig
__bu_config_completion_enum_source_names()
{
    local key
    BU_RET=()
    for key in "${!BU_CONFIG_PROPERTIES[@]}"
    do
        [[ "$key" == *,enum_source ]] && BU_RET+=("${key%,enum_source}")
    done
    return 0
}

# Completion helper: list registered layer names (for bu set-config --layer).
# bash-ide parse-func-sig
__bu_config_completion_layers()
{
    BU_RET=(local)
    local k
    for k in "${!BU_CONFIG_LAYER_RESOLVERS[@]}"
    do
        [[ -n "${BU_CONFIG_LAYER_RESOLVERS[$k]}" ]] && BU_RET+=("$k")
    done
}
