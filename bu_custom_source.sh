# This file does not depend on any other file in BashTab, because we need to 
# define a custom source func ahead of other functions
# e.g. to ensure the correctness of --__bu-once

# The bu repo base directory
export BU_DIR=$PWD
# The directory where non user defined executables are placed
BU_LIB_BIN_DIR=$BU_DIR/lib/bin
# The directory where non user defined sourceable shell scripts are placed
BU_LIB_BINSRC_DIR=$BU_DIR/lib/binsrc
# The directory of the core library
BU_LIB_CORE_DIR=$BU_DIR/lib/core

BU_LIB_TEMPLATE_DIR=$BU_DIR/lib/templates

BU_BUILTIN_COMMANDS_DIR=$BU_DIR/commands


# Traditionally, bash has 3 states for a scalar variable
# 1. Undefined: `[[ ! -v VAR ]]` will be true
# 2. Empty: `[[ -v VAR && -z "$VAR" ]]` will be true
# 3. Non-empty: `[[ -n "$VAR" ]]` will be true
#
# However, state 1 isn't that useful if we want to "forward declare" a variable an initialize it to empty
# effectively, we only have states 2 and 3. Thus when we need 3 states (or if empty is considered to be a valid input),
# then we will use the following instead:
# 1. NULL: `bu_is_null "$VAR"` will be true
# 2. Empty: Same as above
# 3. Non-empty: Same as above
BU_NULL=BU_NULL

# Log a message with a given log level prefix
#
# @arg $1 {string} log_prefix log level prefix (e.g., DEBUG, INFO, WARN, ERR)
# @arg $@ {string} args... message to log
#
# @example
# ```bash
# __bu_basic_log INFO "This is an info message"
# ```
# bash-ide parse-func-sig
__bu_basic_log()
{
    local log_prefix=$1
    shift
    printf -v log_prefix '%-7s' "$log_prefix"
    printf '%s %s\n' "$log_prefix" "$*" >&2
}

# Log a debug message
#
# @arg $@ {string} args... message to log
# bash-ide parse-func-sig
bu_basic_log_debug()
{
    # Bootstrap debug logs (e.g. "sourcing(--__bu-once) ...") fire before the
    # repo configs are loaded, so they gate on a dedicated boolean rather than
    # BU_LOG_LVL. Enable via `bu set-config BU_BOOTSTRAP_VERBOSE true`.
    [[ "${BU_BOOTSTRAP_VERBOSE:-false}" == true ]] || return 0
    __bu_basic_log DEBUG "$*"
}

# Log an info message
#
# @arg $@ {string} args... message to log
# bash-ide parse-func-sig
bu_basic_log_info()
{
    __bu_basic_log INFO "$*"
}

# Log a warning message
#
# @arg $@ {string} args... message to log
# bash-ide parse-func-sig
bu_basic_log_warn()
{
    __bu_basic_log WARN "$*"
}

# Log an error message
#
# @arg $@ {string} args... message to log
# bash-ide parse-func-sig
bu_basic_log_err()
{
    __bu_basic_log ERR "$*"
}

# Check if a variable is BU_NULL
#
# @arg $1 string variable to check
#
# @returns
# - Returns 0 (true) if the variable is BU_NULL, else returns 1 (false)
#
# @example
# ```bash
# bu_is_null "$VAR"
# ```
bu_is_null()
{
    [[ "$1" = BU_NULL ]]
}

# Check if a variable is BU_NULL or empty
#
# @arg $1 string variable to check
#
# @returns
# - Returns 0 (true) if the variable is BU_NULL or empty, else returns 1 (false)
#
# @example
# ```bash
# bu_is_null_or_empty "$VAR"
# ```
bu_is_null_or_empty()
{
    [[ -z "$1" || "$1" = BU_NULL ]]
}

# Check if a variable is not BU_NULL
#
# @arg $1 string variable to check
#
# @returns
# - Returns 0 (true) if the variable is not BU_NULL, else returns 1 (false)
#
# @example
# ```bash
# bu_is_not_null "$VAR"
# ```
bu_is_not_null()
{
    [[ "$1" != BU_NULL ]]
}

# Check if a variable is not BU_NULL and not empty
#
# @arg $1 string variable to check
#
# @returns
# - Returns 0 (true) if the variable is not BU_NULL and not empty, else returns 1 (false)
#
# @example
# ```bash
# bu_is_not_null_or_empty "$VAR"
# ```
bu_is_not_null_or_empty()
{
    [[ -n "$1" && "$1" != BU_NULL ]]
}

# Get directory name of a filepath. Similar to `dirname` except that no process is spawned.
#
# @arg $1 string a filepath
# @set BU_RET directory name of the filepath
#
# @example
# ```bash
# bu_dirname /a/b/c.txt # $BU_RET=/a/b
# ```
bu_dirname()
{
    case "$1" in
    */*) BU_RET=${1%/*};;
    *) BU_RET=.;;
    esac
}

# bash-ide parse-func-sig
bu_pushd_current()
{
    local bash_source=$1
    bu_dirname "$bash_source"
    pushd "$BU_RET" &>/dev/null
}

# Get base name of a filepath. Similar to `basename` except that no process is spawned.
#
# @arg $1 string a filepath
# @set BU_RET base name of the filepath
#
# @example
# ```bash
# bu_basename /a/b/c.txt # $BU_RET=c.txt
# ```
bu_basename()
{
    case "$1" in
    */*) BU_RET=${1##*/};;
    *) BU_RET=$1;;
    esac
}

# Split a string into an array by a given separator
#
# @arg $1 {string} ifs Separator
# @arg $2 {string} to_split String to split
# @arg $3 {string} [ret=BU_RET] Name of the array to store the result in
# @set BU_RET or the array named in `$3`: Array of split entries
#
# @example
# ```bash
# bu_str_split , "a,b,c" # ${BU_RET[@]}=(a b c)
# bu_str_split , "a,b,c" MY_ARR # ${MY_ARR[@]}=(a b c)
# ```
# bash-ide parse-func-sig
bu_str_split()
{
    local ifs=$1
    local to_split=$2
    local ret=${3:-BU_RET}
    if [[ -z "$to_split" ]]
    then
        eval "$ret"=
    else
        local IFS=$ifs
        # shellcheck disable=SC2229
        read -ra "$ret" <<< "$to_split"
    fi
}

# `declare -p` check instead of "${#BU_SOURCE_ONCE_CACHE[@]}", which errors
# under `set -u` when the array has never been declared (and would leave the
# array undeclared, turning later CACHE[$name]=true assignments into indexed
# array assignments with an arithmetic-invalid string subscript).
if ! declare -p BU_SOURCE_ONCE_CACHE &>/dev/null
then
    declare -A -g BU_SOURCE_ONCE_CACHE=(
        [BU_NULL]=true
        [bu_custom_source.sh]=true
    )
fi

# Whether the current source function is the custom one defined by bu_def_source
BU_SOURCE_IS_CUSTOM=false

BU_SOURCE_IS_FORCE=${BU_SOURCE_IS_FORCE:-false}
BU_SOURCE_IS_AUTOPUSHD=${BU_SOURCE_IS_AUTOPUSHD:-false}
BU_SOURCE_IS_INLINE=${BU_SOURCE_IS_INLINE:-false}
BU_SOURCE_INLINE_OUTPUT=${BU_SOURCE_INLINE_OUTPUT:-}

# Define a custom source function that supports additional options
#
# *Bug*:
# Top level `declare` (without `-g`) in a script is broken because we are inside a function
#
# @arg $1 string filepath to source
# @arg $@ {string} args... additional arguments to pass to the sourced file
# @option --__bu-once (Optional): Source the file only if it hasn't been sourced before
# @option --__bu-no-pushd (Optional): Don't automatically pushd into the directory of the sourced file
#
# @example
# ```bash
# bu_def_source
# source my_script.sh --__bu-once --__bu-no-pushd
# ```
bu_def_source()
{
    # Set BU_SOURCE_IS_CUSTOM to indicate that we have defined a custom source function
    # Avoids the need to check whether "$(type -t source)" is "builtin" or "function"
    BU_SOURCE_IS_CUSTOM=true
    # bash-ide parse-func-sig
    source()
    {
        local source_filepath=$1
        shift

        case "$source_filepath" in
        BU_NULL) return 0;;
        esac

        local is_force=
        local is_once=false
        local is_autopushed=
        local is_inline=
        local is_no_inline=false
        local inline_output=
        local shift_by
        while (($#))
        do
            shift_by=1
            case "$1" in
            --__bu-force)
                is_force=true
                ;;
            --__bu-once)
                # Source the file only if it hasn't been sourced before
                # Note that this option is more for optimization forces.
                # Try not to make this a requisite for correctness. 
                # (For e.g. we can force source by setting BU_SOURCE_IS_FORCE to true)
                is_once=true
                ;;
            --__bu-autopushd)
                is_autopushed=true
                ;;
            --__bu-no-autopushd)
                # Don't automatically pushd into the directory
                is_autopushed=false
                ;;
            --__bu-inline)
                is_inline=true
                inline_output=$(realpath -- "$2")
                shift_by=2
                ;;
            --__bu-no-inline)
                is_no_inline=true
                ;;
            --__bu-*)
                bu_basic_log_err "Unrecognized source option $1"
                return 1
                ;;
            *)
                break
                ;;
            esac
            shift "$shift_by"
        done
        local saved_is_force=$BU_SOURCE_IS_FORCE
        BU_SOURCE_IS_FORCE=${is_force:-$BU_SOURCE_IS_FORCE}
        local saved_is_autopushd=$BU_SOURCE_IS_AUTOPUSHD
        BU_SOURCE_IS_AUTOPUSHD=${is_autopushed:-$BU_SOURCE_IS_AUTOPUSHD}
        local saved_is_inline=$BU_SOURCE_IS_INLINE
        BU_SOURCE_IS_INLINE=${is_inline:-$BU_SOURCE_IS_INLINE}
        local saved_inline_output=$BU_SOURCE_INLINE_OUTPUT
        BU_SOURCE_INLINE_OUTPUT=${inline_output:-$BU_SOURCE_INLINE_OUTPUT}

        local basename
        local dirname
        case "$source_filepath" in
        */*)
            basename=${source_filepath##*/}
            dirname=${source_filepath%/*}
            ;;
        *)
            basename=$source_filepath
            dirname=.
            ;;
        esac

        if [[ "$is_inline" = true ]]
        then
            BU_SOURCE_ONCE_CACHE=()
            : >"$BU_SOURCE_INLINE_OUTPUT"
        fi

        # shellcheck disable=SC2317
        if "$is_once"
        then
            # We assume all bu source once files to be uniquely named
            if "${BU_SOURCE_ONCE_CACHE[$basename]:-false}"
            then
                if "${BU_SOURCE_IS_FORCE:-false}"
                then
                    bu_basic_log_debug "$basename has already been sourced, forcing."
                else
                    bu_basic_log_debug "$basename has already been sourced, skipping."
                    return 0
                fi
            fi
            bu_basic_log_debug "sourcing(--__bu-once) $source_filepath"
        fi

        # shellcheck disable=SC2317
        BU_SOURCE_ONCE_CACHE[$basename]=true

        if "$BU_SOURCE_IS_AUTOPUSHD"
        then
            pushd "$dirname" >/dev/null
            source_filepath=$basename
        fi

        if [[ "$BU_SOURCE_IS_INLINE" = true ]]
        then
            if ! "$is_no_inline"
            then
            if [[ -n "$__bu_source_inline_cur_line" ]]
            then
                # echo "${BASH_SOURCE[1]}" "$__bu_source_inline_cur_line,$((BASH_LINENO[0] - 1))"
                sed -n "$__bu_source_inline_cur_line,$(( BASH_LINENO[0] - 1 )) p" "${BASH_SOURCE[1]}" >>"$BU_SOURCE_INLINE_OUTPUT"
                __bu_source_inline_cur_line=$(( BASH_LINENO[0] + 1 ))
            fi
            if declare -f "$source_filepath" >/dev/null
            then
                bu_basic_log_debug "$source_filepath is func"
                sed -n "${BASH_LINENO[0]} p" "${BASH_SOURCE[1]}" >>"$BU_SOURCE_INLINE_OUTPUT"
            else
                local __bu_source_inline_cur_line=1
                builtin source "$source_filepath" "$@"
                # echo "$source_filepath" "$__bu_source_inline_cur_line,$"
                sed -n "$__bu_source_inline_cur_line,$ p" "$source_filepath" >>"$BU_SOURCE_INLINE_OUTPUT"
            fi

            fi
        else
            # Our source implementations allow functions too
            # Functions are in fact more similar to sourcing scripts than invoking a script in a new shell
            # Slight optimization: If source_filepath ends in .sh, then we assume it is a script instead of a function
            case "$source_filepath" in
            *.sh)
                # shellcheck disable=SC2317
                builtin source "$source_filepath" "$@"
                ;;
            *)
                if declare -f "$source_filepath" >/dev/null
                then
                    "$source_filepath" "$@"
                else
                    # shellcheck disable=SC2317
                    builtin source "$source_filepath" "$@"
                fi
                ;;
            esac
        fi

        if "$BU_SOURCE_IS_AUTOPUSHD"
        then
            popd >/dev/null
        fi

        BU_SOURCE_IS_FORCE=$saved_is_force
        BU_SOURCE_IS_AUTOPUSHD=$saved_is_autopushd
        BU_SOURCE_IS_INLINE=$saved_is_inline
        BU_SOURCE_INLINE_OUTPUT=$saved_inline_output
    }
}

# Undefine the custom source function and restore the builtin source
# bash-ide parse-func-sig
bu_undef_source()
{
    unset -f source
    BU_SOURCE_IS_CUSTOM=false
}

# If the custom source function is defined, use it to source the given file(s).
# Otherwise, temporarily define the custom source function, use it to source the given file(s),
# and then undefine the custom source function.
# bash-ide parse-func-sig
bu_source()
{
    if "$BU_SOURCE_IS_CUSTOM"
    then
        # shellcheck disable=SC1090
        source "$@"
    else
        bu_def_source
        # shellcheck disable=SC1090
        source "$@"
        bu_undef_source
    fi
}

# If the custom source function is defined, undefine it, use the builtin source to source the given file(s),
# and then redefine the custom source function.
# Otherwise, use the builtin source to source the given file(s).
#
# *Bug*:
# Top level `declare` (without `-g`) in a script is broken because we are inside a function
# bash-ide parse-func-sig
bu_ext_source()
{
    if "$BU_SOURCE_IS_CUSTOM"
    then
        bu_undef_source
        # shellcheck disable=SC1090
        source "$@"
        bu_def_source
    else
        # shellcheck disable=SC1090
        source "$@"
    fi
}

# Source multiple files using the custom source function, ensuring each file is sourced only once.
# bash-ide parse-func-sig
bu_source_multi_once()
{
    if ! "$BU_SOURCE_IS_CUSTOM" && (($#))
    then
        bu_basic_log_warn "Using builtin source for bu_source_multi_once, --__bu-once feature will not be effective."
        bu_source_multi "$@"
    else
        local filepath
        for filepath
        do
            # shellcheck disable=SC1090
            source "$filepath" --__bu-once --__bu-no-inline
        done
    fi
}

# Source multiple files.
# bash-ide parse-func-sig
bu_source_multi()
{
    local filepath
    for filepath
    do
        # shellcheck disable=SC1090
        source "$filepath"
    done
}

bu_def_source
