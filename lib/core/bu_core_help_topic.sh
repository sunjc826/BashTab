# MARK: Help-topic registry
# PowerShell-flavored subsystem documentation ("about_*" pages).
#
# A help topic is a bash script (not markdown) that is sourced in a subshell
# with the framework loaded; its stdout IS the help text.  Heredocs give
# markdown-ish prose PLUS variable substitution and live system checks, so a
# topic can reflect THIS machine (real paths, live session state) rather than
# a stale snapshot.  The subshell is mandatory: a topic script must not be
# able to mutate the invoking shell.
#
# Topic membership is DERIVED, never duplicated.  Command tables inside a
# topic come from the command scripts' existing `# Synopsis:` headers; the
# `--help` → topic back-reference comes from the script's parent directory or
# a `# Help-Topic:` header.  No hand-maintained lists anywhere.

# These arrays are re-initialized every time the entrypoint sources this file
# (bu_core_help_topic.sh is intentionally sourced WITHOUT --__bu-once, next to
# the location registry, so re-activation starts from a clean slate before
# module preinits re-register their topics).
declare -A -g BU_HELP_TOPIC_REGISTRY=()     # name -> topic script path
declare -A -g BU_HELP_TOPIC_PROPERTIES=()   # [name,source] = registrant provenance

# First BASH_SOURCE frame OUTSIDE the help-topic registry core file.
# Used to record provenance ([name,source]) so a delegating wrapper records
# the actual registrant (module preinit, local file).
#
# @set BU_RET source file path
# bash-ide parse-func-sig
__bu_help_topic_provenance()
{
    local i file base
    for (( i = 0; i < ${#BASH_SOURCE[@]}; i++ ))
    do
        file=${BASH_SOURCE[$i]}
        base=${file##*/}
        [[ "$base" == bu_core_help_topic.sh ]] && continue
        BU_RET=("$file")
        return 0
    done
    BU_RET=("${BASH_SOURCE[0]}")
    return 0
}

# Extract a topic script's own `# Synopsis:` header (first ~30 lines).
# Values are extracted verbatim (no variable/command substitution).
#
# @arg $1 {string} file topic script path
# @set BU_RET synopsis text, or empty
__bu_help_topic_synopsis()
{
    BU_RET=
    local file=$1
    local _s=
    __bu_command_header_get "$file" "Synopsis" _s
    BU_RET=$_s
    return 0
}

# Extract a command script's explicit `# Help-Topic:` header (first ~30
# lines).  Empty when the script declares no topic back-reference.
#
# @arg $1 {string} file command script path
# @set BU_RET declared topic name, or empty
__bu_help_topic_header()
{
    BU_RET=
    local file=$1
    local _t=
    __bu_command_header_get "$file" "Help-Topic" _t
    BU_RET=$_t
    return 0
}

# Register a named help topic backed by a script file.
#
# @arg $1 {string} name topic name
# @option --file PATH: readable topic script (its stdout is the help text)
#
# @returns
# - 0 on success, 1 on invalid registration
# bash-ide parse-func-sig
bu_help_topic_register()
{
    local name=$1
    shift
    local file=
    while (($#))
    do
        case "$1" in
        --file) file=$2; shift 2 ;;
        *) bu_log_err "bu_help_topic_register: unknown option[$1]"; return 1 ;;
        esac
    done

    if [[ -z "$name" ]]
    then
        bu_log_err "bu_help_topic_register: empty name"
        return 1
    fi

    if [[ -z "$file" || ! -f "$file" || ! -r "$file" ]]
    then
        bu_log_err "bu_help_topic_register[$name]: requires a readable file"
        return 1
    fi

    __bu_help_topic_provenance
    BU_HELP_TOPIC_REGISTRY[$name]=$file
    BU_HELP_TOPIC_PROPERTIES[$name,source]=$BU_RET
    # Stamp the owning module (BU_CURRENT_MODULE is set while a module's
    # preinit callback is sourced; empty for core/user-local registrations).
    # Mirrors __bu_stamp_command_module so `bu get-help` can show provenance
    # the same way `bu get-command` does.
    BU_HELP_TOPIC_PROPERTIES[$name,module]=${BU_CURRENT_MODULE:-}
    return 0
}

# Register every `DIR/<topic>.help.sh` as topic `<topic>` — the idiomatic
# one-liner for a module preinit.  A missing/empty dir is success (a module
# may not ship topics yet).
#
# @arg $1 {string} dir directory containing topic scripts
#
# @returns
# - 0 on success (including missing/empty dir)
# bash-ide parse-func-sig
bu_help_topic_register_dir()
{
    local dir=$1
    if [[ ! -d "$dir" ]]
    then
        return 0
    fi

    local file topic
    for file in "$dir"/*.help.sh
    do
        [[ -f "$file" ]] || continue
        topic=${file##*/}
        topic=${topic%.help.sh}
        bu_help_topic_register "$topic" --file "$file" || return 1
    done
    return 0
}

# Resolve a topic name to its backing script path.
#
# @arg $1 {string} name topic name
# @set BU_RET topic script path
#
# @returns
# - 0 on success, 1 if unknown
# bash-ide parse-func-sig
bu_help_topic_resolve()
{
    local name=$1
    local file=${BU_HELP_TOPIC_REGISTRY[$name]:-}
    if [[ -z "$file" ]]
    then
        bu_log_err "Unknown help topic[$name]"
        return 1
    fi
    BU_RET=("$file")
    return 0
}

# List registered topic names, sorted (the completion feed).
#
# @set BU_RET array of topic names
# bash-ide parse-func-sig
bu_help_topic_names()
{
    BU_RET=()
    local name
    for name in "${!BU_HELP_TOPIC_REGISTRY[@]}"
    do
        BU_RET+=("$name")
    done
    if ((${#BU_RET[@]} > 0))
    then
        local -a sorted=()
        mapfile -t sorted < <(printf '%s\n' "${BU_RET[@]}" | sort -u)
        BU_RET=("${sorted[@]}")
    fi
    return 0
}

# Emit a command table for a list of command script files.  One row per file:
# `  <cli-name> <command-name> <synopsis>`, sorted by row.  Command names are
# derived from the filename (minus extension, underscores → dashes, and a
# leading `bu-` namespace prefix stripped); synopses come from each file's
# `# Synopsis:` header (first ~30 lines).
#
# @arg $@ {string} args... command script paths
# bash-ide parse-func-sig
__bu_help_topic_commands_print()
{
    local -a files=("$@")
    ((${#files[@]} > 0)) || return 0

    local file base cmd synopsis
    local -a rows=()
    for file in "${files[@]}"
    do
        base=${file##*/}
        cmd=${base%.*}
        cmd=${cmd//_/-}
        # BashTab command scripts are named <namespace>-<command>.sh (e.g.
        # bu-get-command.sh → get-command). Strip the leading `bu-` namespace
        # prefix so a row reads "<cli> <command>" rather than "bu bu-command".
        [[ "$cmd" == bu-* ]] && cmd=${cmd#bu-}
        __bu_help_topic_synopsis "$file"
        synopsis=$BU_RET
        rows+=("  $BU_CLI_COMMAND_NAME $cmd $synopsis")
    done
    printf '%s\n' "${rows[@]}" | sort
    return 0
}

# Print a command table for a suite directory.  For each `*.sh`/`*.py`
# (skipping `__*`, `functions.*`, `overrides*`), emit one row.  Topic scripts
# call this in a `$(...)` so the table can never drift from the commands.
#
# @arg $1 {string} dir suite directory
# bash-ide parse-func-sig
bu_help_topic_commands()
{
    local dir=$1
    [[ -d "$dir" ]] || return 0

    local file base
    local -a files=()
    for file in "$dir"/*.sh "$dir"/*.py
    do
        [[ -f "$file" ]] || continue
        base=${file##*/}
        case "$base" in
        __*|functions.*|overrides*) continue ;;
        esac
        files+=("$file")
    done

    __bu_help_topic_commands_print "${files[@]}"
    return 0
}

# Like bu_help_topic_commands, but includes only files whose header carries
# `# Help-Topic: TOPIC`.  For flat command dirs hosting many subsystems,
# membership is declared per-file with the SAME header that drives the
# `--help` back-reference (single source).
#
# @arg $1 {string} topic topic name to filter by
# @arg $@ {string} args... suite directories to scan
# bash-ide parse-func-sig
bu_help_topic_commands_tagged()
{
    local topic=$1
    shift
    [[ -n "$topic" ]] || return 0

    local dir file base
    local -a files=()
    for dir in "$@"
    do
        [[ -d "$dir" ]] || continue
        for file in "$dir"/*.sh "$dir"/*.py
        do
            [[ -f "$file" ]] || continue
            base=${file##*/}
            case "$base" in
            __*|functions.*|overrides*) continue ;;
            esac
            __bu_help_topic_header "$file"
            [[ "$BU_RET" == "$topic" ]] || continue
            files+=("$file")
        done
    done

    __bu_help_topic_commands_print "${files[@]}"
    return 0
}

# Resolve the help topic for a command script.  An explicit `# Help-Topic:`
# header wins; otherwise the script's parent directory name is used.  Fails
# unless that name is actually registered.
#
# @arg $1 {string} script command script path
# @set BU_RET topic name
#
# @returns
# - 0 on success, 1 if no registered topic applies
# bash-ide parse-func-sig
bu_help_topic_for_script()
{
    local script=$1

    __bu_help_topic_header "$script"
    local topic=$BU_RET

    if [[ -z "$topic" ]]
    then
        local dir
        bu_dirname "$script"
        dir=$BU_RET
        topic=${dir##*/}
    fi

    if [[ -z "${BU_HELP_TOPIC_REGISTRY[$topic]:-}" ]]
    then
        return 1
    fi

    BU_RET=("$topic")
    return 0
}

# Render a topic script.  Sources FILE in a subshell (so the topic cannot
# mutate the caller) with BU_TPUT_BOLD/BU_TPUT_RESET set to the given values.
# Callers blank them when stdout is not a terminal so piped topic text stays
# clean and grep-able (no escapes).
#
# @arg $1 {string} file topic script path
# @arg $2 {string} bold value for BU_TPUT_BOLD
# @arg $3 {string} reset value for BU_TPUT_RESET
# bash-ide parse-func-sig
__bu_help_topic_render()
{
    local file=$1
    local bold=$2
    local reset=$3
    (
        BU_TPUT_BOLD=$bold
        BU_TPUT_RESET=$reset
        builtin source "$file"
    )
}
