# Context-variable origin tracking and consumption logging.
#
# Commands take defaults from ambient "context" variables (environment /
# configuration variables set by the embedding project).  Two questions were
# previously unanswerable: which variables a command actually consumes, and
# where each variable's value came from.  This module answers both.
#
# WRITE SIDE — origin tracking.
#   `bu_var_origin_enable` arms a DEBUG trap (+ `set -o functrace`) that
#   records, for every executed simple command matching `^(NAME)=` (NAME
#   matching the prefix regex, default CAPS names `[A-Z_][A-Z0-9_]*`),
#   `BU_VARIABLE_ORIGIN[NAME]="file:line"` of that assignment (last write
#   wins).  `bu_var_origin_disable` disarms and restores the pre-existing
#   DEBUG trap + functrace flag.  Nothing is armed by default anywhere in
#   core — steady-state cost is zero.  Embedders choose windows (e.g. around
#   sourcing their configuration chain) and wrap them in enable/disable.
#
# READ SIDE — consumption logging.
#   `bu_context_default VARNAME CONTEXT_VAR` is THE idiomatic replacement for
#   the flag-default boilerplate `[[ -n "$x" ]] || x=${CONTEXT_VAR:-}`.
#   `bu_context_use CONTEXT_VAR` is an unconditional read (value returned in
#   BU_RET[0]).  Each call emits one compact stderr line and appends one JSONL
#   record to $BU_OUT_DIR/context/<YYYY-MM-DD>.jsonl.
#
# See docs/context_variables.md for the full guide.

# ---------------------------------------------------------------------------
# Global state.  Guard-declared so re-activation is idempotent and, in the
# write direction, `declare -p` checks avoid tripping `set -u` on arrays.
# ---------------------------------------------------------------------------

# Origin map: variable NAME -> "file:line" of the last tracked assignment.
# Populated by the DEBUG trap installed by bu_var_origin_enable.
if ! declare -p BU_VARIABLE_ORIGIN &>/dev/null
then
    declare -A -g BU_VARIABLE_ORIGIN=()
fi

# `declare -p` check so a bare test subshell (no entrypoint) also works.
if ! declare -p BU_RET &>/dev/null
then
    declare -a -g BU_RET=()
fi

# Whether the origin-tracking DEBUG trap is currently armed.
declare -g BU_VAR_ORIGIN_ARMED=false
# `trap -p DEBUG` output captured at enable time (empty = no prior trap).
declare -g BU_VAR_ORIGIN_SAVED_TRAP=
# functrace state ("on"/"off") captured at enable time.
declare -g BU_VAR_ORIGIN_SAVED_FUNCTRACE=off
# Prefix regex used by the armed trap (read by the trap body at trap time).
declare -g BU_VAR_ORIGIN_PREFIX_REGEX='[A-Z_][A-Z0-9_]*'

# ---------------------------------------------------------------------------
# Write side — origin tracking
# ---------------------------------------------------------------------------

# Arm origin tracking: record "file:line" of every executed assignment to a
# variable whose name matches the prefix regex (default CAPS names only).
#
# Params:
# - --reset: Clear BU_VARIABLE_ORIGIN first.  Applies even when already armed.
# - --prefix-regex RE: Narrow which names are tracked.  RE is a POSIX ERE
#   fragment matching the variable name (default `[A-Z_][A-Z0-9_]*`).
#
# Notes:
# - The pre-existing DEBUG trap and the functrace flag are saved and restored
#   by bu_var_origin_disable, so this composes with other DEBUG users.
# - Enable-while-armed is a no-op (never nests).
# - Windows accumulate into BU_VARIABLE_ORIGIN unless --reset is given.
bu_var_origin_enable()
{
    local is_reset=false
    local prefix_regex='[A-Z_][A-Z0-9_]*'
    while (($#))
    do
        case "$1" in
        --reset)
            is_reset=true
            ;;
        --prefix-regex)
            prefix_regex=$2
            shift
            ;;
        *)
            printf '%s\n' "bu_var_origin_enable: unrecognized option[$1]" >&2
            return 1
            ;;
        esac
        shift
    done

    if "$is_reset"
    then
        BU_VARIABLE_ORIGIN=()
    fi

    if [[ $BU_VAR_ORIGIN_ARMED == true ]]
    then
        return 0
    fi

    # Save pre-existing state for restore on disable.  `trap -p DEBUG` cannot
    # see a caller's DEBUG trap from inside a function unless the function is
    # traced — this function is `declare -ft`'d at the bottom of this file.
    BU_VAR_ORIGIN_SAVED_TRAP=$(trap -p DEBUG)
    if shopt -qo functrace
    then
        BU_VAR_ORIGIN_SAVED_FUNCTRACE=on
    else
        BU_VAR_ORIGIN_SAVED_FUNCTRACE=off
    fi
    BU_VAR_ORIGIN_PREFIX_REGEX=$prefix_regex

    # Mark armed BEFORE installing the trap so the trap does not record our
    # own state assignment below.
    BU_VAR_ORIGIN_ARMED=true
    set -o functrace
    # The trap body MUST stay on a single line: a multiline trap string
    # offsets LINENO by its own line count.  `if/fi` (not `[[ ]] &&`) so the
    # trap always returns 0 into the errexit/extdebug machinery.
    trap 'if [[ $BASH_COMMAND =~ ^($BU_VAR_ORIGIN_PREFIX_REGEX)= ]]; then __bu_vo_src=${BASH_SOURCE[0]:-}; if [[ $__bu_vo_src != /* ]]; then __bu_vo_src=$PWD/$__bu_vo_src; fi; BU_VARIABLE_ORIGIN[${BASH_REMATCH[1]}]="$__bu_vo_src:$LINENO"; fi' DEBUG
    return 0
}

# Disarm origin tracking: restore the pre-existing DEBUG trap and functrace
# flag captured by bu_var_origin_enable.  Idempotent when not armed.
# bash-ide parse-func-sig
bu_var_origin_disable()
{
    if [[ $BU_VAR_ORIGIN_ARMED != true ]]
    then
        return 0
    fi

    if [[ -n $BU_VAR_ORIGIN_SAVED_TRAP ]]
    then
        eval "$BU_VAR_ORIGIN_SAVED_TRAP"
    else
        trap - DEBUG
    fi

    if [[ $BU_VAR_ORIGIN_SAVED_FUNCTRACE == on ]]
    then
        set -o functrace
    else
        set +o functrace
    fi

    BU_VAR_ORIGIN_ARMED=false
    return 0
}

# `trap -p DEBUG` inside a function cannot see a caller's DEBUG trap unless
# the function is traced.  Mark both so enable can save / disable can see
# through function scope.
declare -ft bu_var_origin_enable bu_var_origin_disable

# ---------------------------------------------------------------------------
# Read side — consumption logging
# ---------------------------------------------------------------------------

# Flatten a value for single-line display: newlines/tabs become spaces, CR is
# stripped.  Pure bash, no subprocess.
#
# Params:
# - $1: Value to flatten
# - $2: Name of the caller variable to receive the result (nameref)
# bash-ide parse-func-sig
__bu_context_flatten()
{
    local s=$1
    local -n _out=$2
    s=${s//$'\n'/ }
    s=${s//$'\t'/ }
    s=${s//$'\r'/}
    _out=$s
}

# JSON-escape a value for embedding in a JSON string: backslash and double
# quote are escaped; newlines/tabs flattened to spaces; CR stripped.
# Pure bash, no subprocess per record.
#
# Params:
# - $1: Value to escape
# - $2: Name of the caller variable to receive the result (nameref)
# bash-ide parse-func-sig
__bu_context_json_escape()
{
    local s=$1
    local -n _out=$2
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\n'/ }
    s=${s//$'\t'/ }
    s=${s//$'\r'/}
    _out=$s
}

# Emit one consumption event: a compact stderr line and one JSONL record
# appended to $BU_OUT_DIR/context/<YYYY-MM-DD>.jsonl.  Never fails the
# caller: an unwritable record path degrades silently to stderr-only, and
# autocomplete suppresses both outputs entirely.  `set -e` / `set -u` safe.
#
# Params:
# - $1: Context variable name (var field)
# - $2: Ambient value of the context variable (record `value` field)
# - $3: Local variable name, or "" for bu_context_use (local field)
# - $4: Value actually used by the command (stderr display value)
# - $5: source field — context | flag | read
# - $6: Consuming script basename, .sh stripped (command field)
# bash-ide parse-func-sig
__bu_context_log()
{
    local _var=$1
    local _ambient=$2
    local _local=$3
    local _used=$4
    local _source=$5
    local _command=$6

    if bu_env_is_in_autocomplete
    then
        return 0
    fi

    local _origin=${BU_VARIABLE_ORIGIN[$_var]:-}

    # (1) Compact stderr line at read time.  Shows the value actually used
    # (the flag value when the flag won, the ambient value otherwise).
    local _flat_used=
    __bu_context_flatten "$_used" _flat_used
    local _line="[ctx] "
    if [[ $_source == flag ]]
    then
        _line+="${_local}=${_flat_used} <- flag (${_var} overridden)"
    else
        if [[ -n $_local ]]
        then
            _line+="${_local}="
        fi
        _line+="${_flat_used} <- ${_var}"
        if [[ -n $_origin ]]
        then
            _line+=" (${_origin})"
        fi
    fi
    printf '%s\n' "$_line" >&2

    # (2) JSONL record.  ts/date come from printf %(...)T (no subprocess).
    local _date=
    local _ts=
    printf -v _date '%(%F)T' -1
    printf -v _ts '%(%s)T' -1

    local _e_value= _e_local= _e_var= _e_origin= _e_command=
    __bu_context_json_escape "$_ambient" _e_value
    __bu_context_json_escape "$_local" _e_local
    __bu_context_json_escape "$_var" _e_var
    __bu_context_json_escape "$_origin" _e_origin
    __bu_context_json_escape "$_command" _e_command

    local _record="{\"ts\":$_ts,\"command\":\"$_e_command\",\"var\":\"$_e_var\",\"value\":\"$_e_value\",\"local\":\"$_e_local\",\"source\":\"$_source\",\"origin\":\"$_e_origin\"}"

    # Unwritable record path degrades silently to stderr-only.
    {
        mkdir -p "${BU_OUT_DIR:-}/context" &&
        printf '%s\n' "$_record" >> "${BU_OUT_DIR:-}/context/$_date.jsonl"
    } 2>/dev/null || true

    return 0
}

# Idiomatic replacement for the flag-default boilerplate
# `[[ -n "$x" ]] || x=${CONTEXT_VAR:-}`.  If the named local is already
# non-empty (an explicit argument won), keep it and log source=flag (the
# variable was consulted but overridden — logging this case answers "would
# this command have used CONTEXT_VAR?").  Otherwise assign from the context
# variable (nameref; may remain empty when unset — still logged: "wanted it,
# wasn't set" is signal) and log source=context.
#
# Prefer this over bu_context_use: it makes the input argument-injectable.
#
# Params:
# - $1: Local variable NAME (caller-declared `local name=`), passed by name
# - $2: CONTEXT_VAR name (ambient variable providing the default)
bu_context_default()
{
    local -n _lref=$1
    local _ctx_var=$2
    local -n _cref=$_ctx_var
    local _source=context

    local _used=
    if [[ -n ${_lref:-} ]]
    then
        _source=flag
    else
        _lref=${_cref:-}
    fi
    _used=${_lref:-}

    local _ambient=${_cref:-}
    local _command=${BASH_SOURCE[1]:-}
    _command=${_command##*/}
    _command=${_command%.sh}

    __bu_context_log "$_ctx_var" "$_ambient" "$1" "$_used" "$_source" "$_command"
    return 0
}

# Unconditional read of a context variable.  Value is returned in BU_RET[0]
# and logged with source=read.
#
# Use sparingly: prefer refactoring the call site to bu_context_default (make
# the input argument-injectable); if that does not fit, consider whether the
# variable is a genuine contextual input worth logging (framework/plumbing
# paths are not).
#
# Params:
# - $1: CONTEXT_VAR name
#
# Returns:
# - BU_RET: The context variable's value (BU_RET[0]; empty when unset)
# bash-ide parse-func-sig
bu_context_use()
{
    local _ctx_var=$1
    local -n _cref=$_ctx_var
    local _value=${_cref:-}

    BU_RET=$_value

    local _command=${BASH_SOURCE[1]:-}
    _command=${_command##*/}
    _command=${_command%.sh}

    __bu_context_log "$_ctx_var" "$_value" "" "$_value" "read" "$_command"
    return 0
}
