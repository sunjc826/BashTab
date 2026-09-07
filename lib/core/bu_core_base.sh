# bash-ide source=../../bu_custom_source.sh
# bash-ide source=./bu_core_var.sh
# Note: static.sh should be sourced outside of this file!
# bash-ide source=../../config/bu_config_static.sh
# Note: dynamic.sh should be sourced outside of this file!
# bash-ide source=../../config/bu_config_dynamic.sh

# MARK: Filesystem utilities

# ```
# *Description*:
# Create directories if they do not exist
#
# *Params*:
# - `...`: List of directories to create
#
# *Examples*:
# ```bash
# bu_mkdir /tmp/dir1 /tmp/dir2
# ```
# ```
bu_mkdir()
{
    local missing=()
    local dir
    for dir
    do
        if [[ ! -e "$dir" ]]
        then
            missing+=("$dir")
        fi
    done
    if ((${#missing[@]}))
    then
        mkdir -p "${missing[@]}"
    fi
}

# ```
# *Description*:
# Convert a path to an absolute path without resolving symlinks
#
# *Params*:
# - `$1`: Path to convert (relative or absolute)
# - `$2` (optional): Base directory for resolving relative paths (default: `$PWD`)
#
# *Returns*:
# - `$BU_RET`: The absolute path
#
# *Examples*:
# ```bash
# bu_realpath /tmp/file  # $BU_RET=/tmp/file
# bu_realpath ../dir  # $BU_RET=$PWD/../dir
# bu_realpath dir /home/user  # $BU_RET=/home/user/dir
# ```
#
# *Notes*:
# - Does not resolve symlinks (use the builtin `realpath` command for that)
# - Simply converts relative paths to absolute paths
# - Removes leading `./` from relative paths before appending to base directory
# - Returns absolute paths unchanged
# - Does not simplify ..
# - No forking is needed as compared to realpath
# ```
bu_realpath()
{
    local -r dir=$1
    local -r cwd=${2:-$PWD}

    case "$dir" in
    /*)
        BU_RET=$dir
        ;;
    *)
        BU_RET=$cwd/${dir#./}
        ;;
    esac
}

BU_BASE_PROC_DIR=$BU_OUT_DIR/proc
BU_PROC_DIR=$BU_BASE_PROC_DIR/$$
BU_CACHE_DIR=$BU_OUT_DIR/cache
BU_NAMED_CACHE_DIR=$BU_CACHE_DIR/named
BU_HASHED_CACHE_DIR=$BU_CACHE_DIR/hashed
BU_LOG_DIR=$BU_OUT_DIR/log
BU_LAST_RUN_CMDS=$BU_LOG_DIR/last_run_cmds.sh
BU_HISTORY=$BU_OUT_DIR/bu_history.sh
BU_TMP_DIR=$BU_OUT_DIR/tmp
BU_PROC_TMP_DIR=$BU_PROC_DIR/tmp
BU_SHIMS_DIR=$BU_DIR/shims

bu_mkdir \
    "$BU_NAMED_CACHE_DIR" \
    "$BU_HASHED_CACHE_DIR" \
    "$BU_LOG_DIR" \
    "$BU_TMP_DIR" \
    "$BU_PROC_TMP_DIR" \
    "$BU_SHIMS_DIR"

# Variables prefixed with BU_PROC_ are process specific
# BU_PROC_FIFO is allows reading from stdout of a command without using a subshell
# Iirc, bash 5.3 will support subshell-less process substitution, but until then, this is a workaround
BU_PROC_FIFO=$BU_PROC_DIR/scratch.fifo
BU_PROC_FILE=$BU_PROC_DIR/scratch.txt
# Use an fd to further reduce overhead
# TODO: Think about fds leaking if we re-source the file, e.g. when overridding source-once
BU_PROC_FIFO_FD=
# Probably have some kind of cleanup policy
if [[ ! -e "$BU_PROC_DIR" ]]
then
    mkdir "$BU_PROC_DIR"
fi
if [[ ! -e "$BU_PROC_FIFO" ]]
then
    mkfifo "$BU_PROC_FIFO"
fi
exec {BU_PROC_FIFO_FD}<>"$BU_PROC_FIFO"

BU_ENV_IS_MACOS=
# Detect if we are in WSL
BU_ENV_IS_WSL=
case "$(uname -s)" in
Darwin)
    BU_ENV_IS_MACOS=true
    BU_ENV_IS_WSL=false
    ;;
Linux)
    BU_ENV_IS_MACOS=false
    read -r < /proc/version
    if [[ "$REPLY" = *Microsoft* ]]
    then
        BU_ENV_IS_WSL=true
    else
        BU_ENV_IS_WSL=false
    fi
    ;;
*)
    echo "Unrecognized uname: $(uname -s)" >&2
esac


# MARK: Conversion utilities

# ```
# *Description*:
# Execute a command and capture its output into the global variable `BU_RET`,
# then print `BU_RET` to stdout in the specified format.
#
# *Params*:
# - `--str` or `--spaces`: Specify the output format. `--str` prints `BU_RET` as a single string,
#   while `--spaces` prints each element of `BU_RET` on a new line. Default is `--spaces`.
# - `...`: Command to execute
#
# *Returns*:
# - Exit code of the executed command
# - `stdout`: Formatted output of `BU_RET` from the executed command
#
# *Examples*:
# ```bash
# some_command() { BU_RET=hello; }
# bu_ret_to_stdout --str some_command  # stdout=hello
#
# some_command2() { BU_RET=(hello world); }
# # Note that --str will only print the first element of the array
# bu_ret_to_stdout --str some_command2  # stdout='hello'
# bu_ret_to_stdout --spaces some_command2 # stdout='hello world '
# bu_ret_to_stdout --lines some_command2  # stdout='hello\nworld\n'
# ```
bu_ret_to_stdout()
{
    local mode=str
    case "$1" in
    --str|--spaces|--lines)
        mode=${1#--}
        shift
        ;;
    -*)
        echo "Unrecognized option $1" >&2
        return 1
        ;;
    esac

    "$@"
    local exit_code=$?    
    case "$mode" in
    str)
        printf '%s' "$BU_RET"
        ;;
    spaces)
        printf '%s ' "${BU_RET[@]}"
        ;;
    lines)
        printf '%s\n' "${BU_RET[@]}" 
        ;;
    esac
    return "$exit_code"
}

bu_stdout_to_ret()
{
    local mode=str
    local is_proc=
    local outparam_name=BU_RET
    local shift_by
    while (($#))
    do
        shift_by=1
        case "$1" in
        --str|--spaces|--lines)
            mode=${1#--}
            ;;
        --proc)
            is_proc=true
            ;;
        --no-proc)
            is_proc=false
            ;;
        -o|--outparam)
            outparam_name=$2
            shift_by=2
            ;;
        -*)
            echo "Unrecognized option $1" >&2
            return 1
            ;;
        *)
            break
            ;;
        esac
        shift "$shift_by"
    done

    if [[ -z "$is_proc" ]]
    then
        if "$BU_ENV_IS_WSL"
        then
            # WSL doesn't have the best filesystem performance,
            # so there's not much to gain from the proc file optimization
            is_proc=false
        else
            is_proc=true
        fi
    fi
    local -n __bu_stdout_to_ret_outvar=$outparam_name
    local exit_code=
    case "$mode" in
    str)
        if "$is_proc"
        then
            __bu_stdout_to_ret_outvar=
            "$@" >&"$BU_PROC_FIFO_FD"
            exit_code=$?
            # We must have a newline, we assume that a non-zero exit code does not guarantee a newline
            (( exit_code == 0 )) && read -r "${outparam_name?}" <&"$BU_PROC_FIFO_FD"
        else
            __bu_stdout_to_ret_outvar=$("$@")
            exit_code=$?
        fi
        ;;
    spaces)
        # Note that the behavior is slightly different between is_proc true and false
        # For multiline output, is_proc=true will only process the first line
        if "$is_proc"
        then
            __bu_stdout_to_ret_outvar=()
            "$@" >&"$BU_PROC_FIFO_FD"
            exit_code=$?
            read -r -a "${outparam_name?}" <&"$BU_PROC_FIFO_FD"
        else
            __bu_stdout_to_ret_outvar=($("$@"))
            exit_code=$?
        fi
        ;;
    lines)
        if "$is_proc"
        then
            __bu_stdout_to_ret_outvar=()
            "$@" >"$BU_PROC_FILE"
            exit_code=$?
            mapfile -t "$outparam_name" <"$BU_PROC_FILE"
        else
            local fd
            exec {fd}< <("$@")
            local pid=$!
            mapfile -t "$outparam_name" <&"$fd"
            wait "$pid"
            exit_code=$?
        fi
        ;;
    esac
    return "$exit_code"
}

# ```
# *Description*:
# Read the entire content of a file into a string variable
#
# *Params*:
# - `$1`: File to read
# - `$2` (optional): Name of the variable to store the result in (default: `BU_RET`)
#
# *Returns*:
# - `$BU_RET` or the variable named in `$2`: Content of the file as a string
#
# *Examples*:
# ```bash
# bu_cat_str /path/to/file # $BU_RET contains the file content as a string
# bu_cat_str /path/to/file MY_VAR # $MY_VAR contains the file content as a string
# ```
# ```
bu_cat_str()
{
    local file=$1
    local ret=${2:-BU_RET}
    eval "$ret"=
    mapfile -d '' "$ret" <"$file"
}

# ```
# *Description*:
# Read the entire content of a file into an array variable, splitting by lines
#
# *Params*:
# - `$1`: File to read
# - `$2` (optional): Name of the array variable to store the result in (default: `BU_RET`)
#
# *Returns*:
# - `${BU_RET[@]}` or the array variable named in `$2`: Content of the file as an array of lines
#
# *Examples*:
# ```bash
# bu_cat_arr /path/to/file # ${BU_RET[@]} contains the file content as an array of lines
# bu_cat_arr /path/to/file MY_ARR # ${MY_ARR[@]} contains the file content as an array of lines
# ```
# ```
bu_cat_arr()
{
    local file=$1
    local ret=${2:-BU_RET}
    mapfile -t "$ret" <"$file"
}

# ```
# *Description*:
# Append the content of a file to an existing array variable, splitting by lines
#
# *Params*:
# - `$1`: File to read
# - `$2` (optional): Name of the array variable to append to (default: `BU_RET`)
#
# *Returns*:
# - `${BU_RET[@]}` or the array variable named in `$2`: Content of the file appended to the array
#
# *Examples*:
# ```bash
# bu_cat_arr_append /path/to/file # ${BU_RET[@]} has the file content appended
# bu_cat_arr_append /path/to/file MY_ARR # ${MY_ARR[@]} has the file content appended
# ```
# ```
bu_cat_arr_append()
{
    local file=$1
    local ret=${2:-BU_RET}
    mapfile -t <"$file"
    eval "$ret"+=\( \"\${MAPFILE[@]}\" \)
}

# MARK: Shell symbol helpers

# ```
# *Description*:
# Check if a symbol is a function
#
# *Params*:
# - `$1`: Symbol name
#
# *Returns*:
# - Exit code 0 if the symbol is a function, non-zero otherwise
# ```
bu_symbol_is_function()
{
    bu_stdout_to_ret type -t "$1"
    [[ "$BU_RET" = function ]]
}

# ```
# *Description*:
# Check if a symbol is a file
#
# *Params*:
# - `$1`: Symbol name
#
# *Returns*:
# - Exit code 0 if the symbol is a file, non-zero otherwise
# ```
bu_symbol_is_file()
{
    bu_stdout_to_ret type -t "$1"
    [[ "$BU_RET" = file ]]
}

# MARK: Caching functions
bu_cached_keyed_execute()
{
    local mode=lines
    local is_invalidate_cache=false
    local shift_by
    while (($#))
    do
        shift_by=1
        case "$1" in
        --str|--line|--lines)
            mode=${1#--}
            ;;
        --invalidate-cache)
            is_invalidate_cache=true
            ;;
        --invalidate-cache-bool)
            is_invalidate_cache=$2
            shift_by=2
            ;;
        -*)
            echo "Unrecognized option $1" >&2
            return 1
            ;;
        *)
            break
            ;;
        esac
        shift "$shift_by"
    done

    local cache_key=$1
    shift
    if [[ -z "$cache_key" ]]
    then
        "$@"
        return
    fi

    local cache_path=$BU_NAMED_CACHE_DIR/$cache_key
    if "$is_invalidate_cache"
    then
        rm "$cache_path" || true
    elif [[ -e "$cache_path" ]]
    then
        case "$mode" in
        lines)
            mapfile -t BU_RET < "$cache_path"
            ;;
        str)
            mapfile -d '' -t BU_RET < "$cache_path"
            ;;
        line)
            read -r BU_RET < "$cache_path"
            ;;
        esac
    else
        local exit_code
        "$@"
        exit_code=$?
        if ((exit_code))
        then
            echo "Failed: command[$*]" >&2
            return "$exit_code"
        fi
        case "$mode" in
        str)
            printf "%s" "${BU_RET}" > "$cache_path"
            BU_RET=${BU_RET[*]}
            ;;
        lines)
            printf "%s\n" "${BU_RET[@]}" > "$cache_path"
            ;;
        line)
            printf "%s " "${BU_RET[@]}" > "$cache_path"
            ;;
        esac
    fi
}

# MARK: Colors

# ```
# *Description*:
# Setup tput color codes into variables
#
# *Params*:
# - `$1`: Name of the output variable to store the tput code
# - `...`: Arguments to pass to tput
#
# *Returns*:
# - `${!1}`: Variable containing the tput code
# ```
__bu_setup_tput()
{
    local -n __bu_setup_tput_outvar=$1
    shift
    local joined_cmd=$*
    # Note that the --str --proc mode will lock up at the `read` if there is no newline.
    # tput functions don't make a newline, so we avoid the --proc mode in all cases, WSL or not. 
    # tput output is TERM-dependent (e.g. sgr0 is \E[m\017 under screen TERMs
    # but \E(B\E[m under xterm), so the cache key must include the TERM value;
    # otherwise whichever TERM runs first poisons every later session. The
    # `|| BU_RET=` guard stays load-bearing: TERM-less / capability-less
    # environments (ssh without a tty, cron, TERM=dumb) degrade to empty.
    bu_cached_keyed_execute --str tput_"${TERM:-dumb}"_"${joined_cmd// /_}" bu_stdout_to_ret --no-proc --str tput "$@" 2>/dev/null || BU_RET=
    __bu_setup_tput_outvar=$BU_RET
}

BU_TPUT_UNDERLINE=
BU_TPUT_NO_UNDERLINE=
BU_TPUT_BOLD=
BU_TPUT_RESET=
BU_TPUT_BLACK=
BU_TPUT_RED=
BU_TPUT_GREEN=
BU_TPUT_YELLOW=
BU_TPUT_DARK_BLUE=
BU_TPUT_VIOLET=
BU_TPUT_BLUE=
BU_TPUT_WHITE=
BU_TPUT_GREY=

BU_TPUT_VSCODE_DARK_BLUE=
BU_TPUT_VSCODE_BLACK=
BU_TPUT_VSCODE_PINK=
BU_TPUT_VSCODE_BLUE=
BU_TPUT_VSCODE_RED=
BU_TPUT_VSCODE_YELLOW=
BU_TPUT_VSCODE_WHITE=
BU_TPUT_VSCODE_ORANGE=
BU_TPUT_VSCODE_GREEN=
BU_TPUT_VSCODE_DARK_GREEN=

__bu_setup_tput BU_TPUT_UNDERLINE    smul
__bu_setup_tput BU_TPUT_NO_UNDERLINE rmul
__bu_setup_tput BU_TPUT_BOLD         bold
BU_TPUT_COLORS=$(tput colors 2>/dev/null) || BU_TPUT_COLORS=0
((BU_TPUT_COLORS > 0)) || BU_TPUT_COLORS=0
if ((BU_TPUT_COLORS > 0)) 
then
__bu_setup_tput BU_TPUT_RESET        sgr0
__bu_setup_tput BU_TPUT_BLACK        setaf 0
__bu_setup_tput BU_TPUT_RED          setaf 1
__bu_setup_tput BU_TPUT_GREEN        setaf 2
__bu_setup_tput BU_TPUT_YELLOW       setaf 3
__bu_setup_tput BU_TPUT_DARK_BLUE    setaf 4
__bu_setup_tput BU_TPUT_VIOLET       setaf 5
__bu_setup_tput BU_TPUT_BLUE         setaf 6
__bu_setup_tput BU_TPUT_WHITE        setaf 7
fi
if ((BU_TPUT_COLORS >= 16))
then
__bu_setup_tput BU_TPUT_GREY         setaf 8
fi
if ((BU_TPUT_COLORS >= 256))
then
# This is the VSCode Dark+ theme, hex color scheme converted to xterm256 colors
# Conversion done with https://gist.github.com/chrisdiana/c71f224626b5b9516bdb
__bu_setup_tput BU_TPUT_VSCODE_DARK_BLUE  setaf 74
__bu_setup_tput BU_TPUT_VSCODE_BLACK      setaf 16
__bu_setup_tput BU_TPUT_VSCODE_PINK       setaf 175
__bu_setup_tput BU_TPUT_VSCODE_BLUE       setaf 153
__bu_setup_tput BU_TPUT_VSCODE_RED        setaf 167
__bu_setup_tput BU_TPUT_VSCODE_YELLOW     setaf 187
__bu_setup_tput BU_TPUT_VSCODE_WHITE      setaf 188
__bu_setup_tput BU_TPUT_VSCODE_ORANGE     setaf 174
__bu_setup_tput BU_TPUT_VSCODE_GREEN      setaf 151
__bu_setup_tput BU_TPUT_VSCODE_DARK_GREEN setaf 65
else
BU_TPUT_VSCODE_DARK_BLUE=$BU_TPUT_BLUE
BU_TPUT_VSCODE_BLACK=$BU_TPUT_GREY
BU_TPUT_VSCODE_PINK=$BU_TPUT_RED
BU_TPUT_VSCODE_BLUE=$BU_TPUT_BLUE
BU_TPUT_VSCODE_RED=$BU_TPUT_RED
BU_TPUT_VSCODE_YELLOW=$BU_TPUT_YELLOW
BU_TPUT_VSCODE_WHITE=$BU_TPUT_WHITE
BU_TPUT_VSCODE_ORANGE=$BU_TPUT_YELLOW
BU_TPUT_VSCODE_GREEN=$BU_TPUT_GREEN
BU_TPUT_VSCODE_DARK_GREEN=$BU_TPUT_GREEN
fi


# MARK: Logging

# ```
# *Description*:
# Internal logging function
#
# *Params*:
# - `$1`: Color code
# - `$2`: Log level
# - `$3`: Log prefix
# - `-i|--idx <index>` (optional): Stacktrace index offset for the logging context
# - `...`: Log message
#
# *Notes*:
# - This should not be called externally, because it (in particular log_idx) assumes it is called by a bu_log_[LOG_LVL] function.
# ```
__bu_log()
{
    local color=$1
    local log_lvl=$2
    local log_prefix=$3
    shift 3
    
    local log_lvl_setting
    if bu_env_is_in_autocomplete
    then
        log_lvl_setting=$BU_AUTOCOMPLETE_LOG_LVL
    else
        log_lvl_setting=$BU_LOG_LVL
    fi

    if (( log_lvl < log_lvl_setting ))
    then
        return 0
    fi

    local log_idx=0
    case "$1" in
    -i|--idx)
        log_idx=$2
        shift 2
        ;;
    esac
    local BU_RET
    bu_basename "${BASH_SOURCE[log_idx+2]}"
    local basename=$BU_RET
    # 7 because SUCCESS is the longest log prefix
    printf -v log_prefix '%-7s' "$log_prefix"

    # echo ${FUNCNAME[@]}
    # echo ${BASH_LINENO[@]}
    if bu_env_is_in_autocomplete
    then
        printf "${color}${log_prefix} ${basename}:${BASH_LINENO[log_idx+1]}[${FUNCNAME[log_idx+2]}] %s${BU_TPUT_RESET}\n" "$*" >/dev/tty
    else
        printf "${color}${log_prefix} ${basename}:${BASH_LINENO[log_idx+1]}[${FUNCNAME[log_idx+2]}] %s${BU_TPUT_RESET}\n" "$*" >&2
    fi
}

# ```
# *Description*:
# Assert an error condition
#
# *Params*:
# - `-i|--idx <index>` (optional): Stacktrace index offset for the logging context
# - `...`: Error message
#
# *Returns*:
# - Exit code 1
#
# *Notes*:
# - This assumes that set -e is set, so that the assertion failure will terminate the script
# ```
bu_assert_err()
{
    __bu_log "$BU_TPUT_VSCODE_RED" "$BU_LOG_LVL_ERR" ERR "$@"
    return 1
}

# ```
# *Description*:
# Log an error message
#
# *Params*:
# - `-i|--idx <index>` (optional): Stacktrace index offset for the logging context
# - `...`: Log message
# ```
bu_log_err()
{
    __bu_log "$BU_TPUT_VSCODE_RED" "$BU_LOG_LVL_ERR" ERR "$@"
}

# ```
# *Description*:
# Log a warning message
#
# *Params*:
# - `-i|--idx <index>` (optional): Stacktrace index offset for the logging context
# - `...`: Log message
# ```
bu_log_warn() 
{
    __bu_log "$BU_TPUT_VSCODE_ORANGE" "$BU_LOG_LVL_WARN" WARN "$@"
}

# ```
# *Description*:
# Log an informational message
#
# *Params*:
# - `-i|--idx <index>` (optional): Stacktrace index offset for the logging context
# - `...`: Log message
# ```
bu_log_info() 
{ 
    __bu_log "$BU_TPUT_VSCODE_YELLOW" "$BU_LOG_LVL_INFO" INFO "$@"
}

# ```
# *Description*:
# Log a trace message (lowest level, hidden unless BU_LOG_LVL=trace)
#
# *Params*:
# - `-i|--idx <index>` (optional): Stacktrace index offset for the logging context
# - `...`: Log message
# ```
bu_log_trace()
{
    __bu_log "$BU_TPUT_GREY" "$BU_LOG_LVL_TRACE" TRACE "[${EPOCHREALTIME}] $*"
}

# ```
# *Description*:
# Log a debug message
#
# *Params*:
# - `-i|--idx <index>` (optional): Stacktrace index offset for the logging context
# - `...`: Log message
# ```
bu_log_debug()
{ 
    __bu_log "$BU_TPUT_VSCODE_DARK_GREEN" "$BU_LOG_LVL_DEBUG" DEBUG "$@"
}

# ```
# *Description*:
# Log a success message
#
# *Params*:
# - `-i|--idx <index>` (optional): Stacktrace index offset for the logging context
# - `...`: Log message
# ```
bu_log_success()
{
    __bu_log "$BU_TPUT_GREEN" "$BU_LOG_LVL_INFO" SUCCESS "$*"
}

# ```
# *Description*:
# Log a message directly to the terminal (TTY)
#
# *Params*:
# - `...`: Log message
# ```
bu_log_tty()
{
    printf '%s\n' "$*" > /dev/tty
}

# ```
# *Description*:
# Internal command logging function
#
# *Params*:
# - `$1`: Color code
# - `$2`: Log level
# - `$3`: Log prefix
# - `-i|--idx <index>` (optional): Stacktrace index offset for the logging context
# - `...`: Command to execute
#
# *Notes*:
# - This should not be called externally, because it (in particular log_idx) assumes it is called by a bu_log_cmd_[LOG_LVL] function.
# ```
__bu_log_cmd()
{
    local BU_RET
    local color=$1
    local log_lvl=$2
    local log_prefix=$3
    shift 3

    local log_idx=0
    case "$1" in
    -i|--idx)
        log_idx=$2
        shift 2
        ;;
    esac
    {
        case "$1" in
        echo|printf)
            ;;
        *)
            bu_basename "${BASH_SOURCE[log_idx+2]}"
            local basename=$BU_RET
            # 7 because SUCCESS is the longest log prefix
            printf -v log_prefix '%-7s' "$log_prefix"
            echo -n "${BU_TPUT_BLUE}${log_prefix}:  ${TPUT_BOLD}${basename}:${BASH_LINENO[log_idx+1]}[${FUNCNAME[log_idx+2]}] "
            printf '%q ' "$@"
            echo "${BU_TPUT_RESET}"
            ;;
        esac
        echo -n "${BU_TPUT_BLUE}"
        if ! "$@"
        then
            echo -n "(cmd failed)${BU_TPUT_RESET}"
            return 1
        fi
        echo -n "${BU_TPUT_RESET}"
        case "$1" in
        printf)
            case "$2" in
            '%q ')
                echo
                ;;
            esac
            ;;
        esac
    } >&2
}

# ```
# *Description*:
# Log an error command message
#
# *Params*:
# - `-i|--idx <index>` (optional): Stacktrace index offset for the logging context
# - `...`: Command to execute
# ```
bu_log_cmd_err()
{
    __bu_log_cmd "$BU_TPUT_RED" "$BU_LOG_LVL_ERR" ERR "$@"
}

# ```
# *Description*:
# Log a warning command message
#
# *Params*:
# - `-i|--idx <index>` (optional): Stacktrace index offset for the logging context
# - `...`: Command to execute
# ```
bu_log_cmd_warn()
{
    __bu_log_cmd "$BU_TPUT_YELLOW" "$BU_LOG_LVL_WARN" WARN "$@"
}

# ```
# *Description*:
# Log an informational command message
#
# *Params*:
# - `-i|--idx <index>` (optional): Stacktrace index offset for the logging context
# - `...`: Command to execute
# ```
bu_log_cmd_info()
{
    __bu_log_cmd "$BU_TPUT_BLUE" "$BU_LOG_LVL_INFO" INFO "$@"
}

# ```
# *Description*:
# Log a debug command message
#
# *Params*:
# - `-i|--idx <index>` (optional): Stacktrace index offset for the logging context
# - `...`: Command to execute
# ```
bu_log_cmd_debug()
{
    __bu_log_cmd "$BU_TPUT_VIOLET" "$BU_LOG_LVL_DEBUG" DEBUG "$@"
}

# ```
# *Description*:
# Log an unrecognized option error message
#
# *Params*:
# - `-i|--idx <index>` (optional): Index offset for the logging context
# - `$1`: Unrecognized option
#
# *Examples*:
# ```bash
# bu_log_unrecognized_option --idx 1 --unknown-option
# ```
# ```
bu_log_unrecognized_option()
{
    local log_idx=0
    case "$1" in
    -i|--idx)
        log_idx=$2
        shift 2
        ;;
    esac
    : "$((log_idx++))"
    bu_log_err -i "$log_idx" "Unrecognized option $1"
}

# MARK: List manipulation

# ```
# *Params*:
# - `$1`: Separator
# - `...`: List of entries to join
# 
# *Returns*:
# - `$BU_RET`: Value of the joined string
#
# *Examples*:
# ```bash
# bu_list_join , a b c
# echo "$BU_RET" # a,b,c
# ```
# ```
bu_list_join()
{
    local delim=${1-}
    local first_entry=${2-}
    BU_RET=
    if shift 2
    then
        printf -v BU_RET %s "$first_entry" "${@/#/$delim}"
    fi
}

# ```
# *Description*:
# Reverse a list of entries
#
# *Params*:
# - `...`: List of entries
#
# *Returns*:
# - `${BU_RET[@]}`: Array of entries in reverse order
#
# *Examples*:
# ```bash
# bu_list_reverse a b c # ${BU_RET[@]}=(c b a)
# ```
# ```
bu_list_reverse()
{
    BU_RET=()
    for (( i=$#; i>0; i-- ))
    do
        BU_RET+=("${!i}")
    done
}

# ```
# *Description*:
# Remove empty entries from a list
#
# *Params*:
# - `...`: List of entries
#
# *Returns*:
# - `$BU_RET`: Array of entries with empty entries removed
#
# *Examples*:
# ```bash
# bu_list_filter_out_empty a "" b c "" # ${BU_RET[@]}=(a b c)
# ```
bu_list_filter_out_empty()
{
    BU_RET=()
    local arg
    for arg
    do
        if [[ -n "$arg" ]]
        then
            BU_RET+=("$arg")
        fi
    done
}

# ```
# *Description*:
# Sort a list of entries
#
# *Params*:
# - `...`: List of entries
#
# *Returns*:
# - `${BU_RET[@]}`: Array of sorted entries
#
# *Examples*:
# ```bash
# bu_list_sort c a b # ${BU_RET[@]}=(a b c)
# ```
# ```
bu_list_sort()
{
    local ifs_defined=false
    local saved_ifs=$IFS
    if [[ -v IFS ]]
    then
        ifs_defined=true
        saved_ifs=$IFS
    fi
    IFS=$'\n' BU_RET=($(printf '%s\n' "$@" | sort))
    # TODO: Do we need this?
    if "$ifs_defined"
    then
        IFS=$saved_ifs
    fi
}

bu_list_version_sort()
{
    local ifs_defined=false
    local saved_ifs=$IFS
    if [[ -v IFS ]]
    then
        ifs_defined=true
        saved_ifs=$IFS
    fi
    IFS=$'\n' BU_RET=($(printf '%s\n' "$@" | sort --version-sort))
    # TODO: Do we need this?
    if "$ifs_defined"
    then
        IFS=$saved_ifs
    fi
}

# ```
# *Description*:
# Check if a string exists in a list of strings
#
# *Params*:
# - `$1`: String to search for (needle)
# - `...`: List of strings (haystack)
#
# *Returns*:
# - Exit code:
#   - `0`: if the string exists in the list
#   - `1`: if the string does not exist in the list
#
# *Examples*:
# ```bash
# HAYSTACK=(a b c)
# bu_list_exists_str b "${HAYSTACK[@]}" # returns 0
# bu_list_exists_str d "${HAYSTACK[@]}" # returns 1
# ```
bu_list_exists_str()
{
    local needle=$1
    shift
    local arg
    for arg
    do
        if [[ "$arg" == "$needle" ]]
        then
            return 0
        fi
    done
    return 1 # Not found
}

# MARK: String manipulation

# ```
# *Params*:
# - `$*`: String to convert to lower case
#
# *Returns*:
# - `stdout`: Lower-cased string
#
# *Examples*:
# ```bash
# bu_tolower "AbC" # stdout=abc
# ```
# 
# *Notes*:
# - For better performance, consider using parameter expansion: `${var,,}`
# ```
bu_tolower()
{
    tr '[:upper:]' '[:lower:]' <<<"$*"
}

# ```
# *Params*:
# - `$*`: String to convert to upper case
#
# *Returns*:
# - `stdout`: Upper-cased string
#
# *Examples*:
# ```bash
# bu_toupper "AbC" # stdout=ABC
# ```
#
# *Notes*:
# - For better performance, consider using parameter expansion: `${var^^}`
# ```
bu_toupper()
{
    tr '[:lower:]' '[:upper:]' <<<"$*"
}

# ```
# *Params*:
# - `stdin`: string to trim whitespaces
#
# *Returns*:
# - `stdout`: trimmed string
#
# *Examples*:
# ```bash
# echo '  abc ' | bu_gen_trim # stdout=abc
# ```
# ```
bu_gen_trim()
{
    awk '{$1=$1};1'
}

# ```
# trim is kind of a misnomer here.
# *Params*:
# One of
# - `stdin`: string to trim
# - `$1`: string to trim
#
# *Returns*:
# - `stdout`: string with empty lines, including those with whitespaces only removed
#
# *Examples*:
# ```bash
# echo '
# abc
# ' | bu_gen_trim_empty_lines # stdout='abc'
# ```
#
# ```bash
# bu_gen_trim_empty_lines '
# abc
# ' # stdout='abc'
# ```
# ```
bu_gen_trim_empty_lines()
{
    if [[ -n "$1" ]]
    then
        sed '/^ *$/d' <<<"$1"
    else
        sed '/^ *$/d'
    fi
}

# ```
# *Description*:
# Remove empty lines from a string
#
# *Params*:
# - `stdin`: string to remove empty lines from
#
# *Returns*:
# - `stdout`: string with empty lines removed
#
# *Examples*:
# ```bash
# echo '
# abc
#
# ' | bu_gen_remove_empty_lines # stdout='abc'
# ```
# ```
bu_gen_remove_empty_lines()
{
    sed -r -e '/^$/d'
}

# MARK: RAII Scopes

# ```
# *Description*:
# Push a new scope onto the scope stack
#
# *Params*: None
# *Returns*: None
#
# *Examples*:
# ```bash
# if some_condition; then
#     bu_scope_push
#     touch /tmp/some_temp_file
#     bu_scope_add_cleanup rm -f /tmp/some_temp_file
#     
#     some_command /tmp/some_temp_file
#     some_other_command /tmp/some_temp_file
#
#     bu_scope_pop
# fi
# ```
# ```
bu_scope_push()
{
    BU_SCOPE_STACK+=("${#BU_SCOPE_STACK[@]}")
}

# ```
# *Description*:
# Push a new function-level scope onto the scope stack
#
# *Params*: None
# *Returns*: None
#
# *Examples*:
# ```bash
# function my_function() {
#     bu_scope_push_function
#     if some_condition; then
#         # Early return with cleanup
#         bu_scope_pop_function
#         return 1
#     fi
#     some_command
#     bu_scope_pop_function
# }
# ```
# ```
bu_scope_push_function()
{
    BU_SCOPE_STACK+=("_${#BU_SCOPE_STACK[@]}")
}

# ```
# *Description*:
# Get the current scope handle
#
# *Params*: None
#
# *Returns*:
# - `$BU_RET`: Current scope handle
#
# *Examples*:
# ```bash
# bu_scope_push
# bu_scope_handle # $BU_RET contains the current scope handle, e.g. 0
# bu_scope_pop
# ```
# ```
bu_scope_handle()
{
    if ((!"${#BU_SCOPE_STACK[@]}"))
    then
        bu_log_err "Dynamic stack is empty"
        return 1
    fi

    BU_RET=${BU_SCOPE_STACK[-1]}
}

# ```
# *Description*:
# Register a cleanup command to be executed when the scope which the handle refers to is popped
# 
# *Params*:
# - `$1`: Scope handle
# - `...`: Command to register as cleanup
#
# *Returns*: None
#
# *Examples*:
# ```bash
# bu_scope_push
# bu_scope_handle # $BU_RET contains the current scope handle
# handle=$BU_RET
# touch /tmp/some_temp_file
# bu_scope_handle_add_cleanup "$handle" rm -f /tmp/some_temp_file
# bu_scope_pop
# ```
# ```
bu_scope_handle_add_cleanup()
{
    local handle=$1
    shift
    local -n deferred=BU_SCOPE_CLEANUPS_"$handle"
    # Use a local scratch variable, not BU_RET.  Callers commonly
    # produce a value in BU_RET and then register a cleanup that frees
    # the resource identified by that value — clobbering BU_RET here
    # would corrupt the returned handle.
    local _cmd
    printf -v _cmd "%q " "$@"
    deferred+=("$_cmd")
}

# ```
# *Description*:
# Register a cleanup command to be executed when the current scope is popped
#
# *Params*:
# - `...`: Command to register as cleanup
#
# *Returns*: None
#
# *Examples*:
# ```bash
# bu_scope_push
# touch /tmp/some_temp_file
# bu_scope_add_cleanup rm -f /tmp/some_temp_file
# bu_scope_pop
# ```
# ```
bu_scope_add_cleanup()
{
    if ((!"${#BU_SCOPE_STACK[@]}"))
    then
        bu_log_err -i 1 "Dynamic stack is empty"
        return 1
    fi

    bu_scope_handle_add_cleanup "${BU_SCOPE_STACK[-1]}" "$@"
}

# ```
# *Description*:
# Pop the current scope from the scope stack and execute all registered cleanup commands
#
# *Params*: None
#
# *Returns*: None
#
# *Examples*:
# ```bash
# bu_scope_push
# touch /tmp/some_temp_file
# bu_scope_add_cleanup rm -f /tmp/some_temp_file
# bu_scope_pop
# ```
# ```
bu_scope_pop()
{
    if ((!"${#BU_SCOPE_STACK[@]}"))
    then
        bu_log_err -i 1 "Dynamic stack is empty"
        return 1
    fi

    local -n deferred=BU_SCOPE_CLEANUPS_${BU_SCOPE_STACK[-1]}
    local i
    local ret=0
    bu_log_debug "Cleaning up ${BU_SCOPE_STACK[-1]}"
    for (( i=${#deferred[@]}-1; i >= 0; i-- ))
    do
        bu_log_debug "Cleaning up ${BU_SCOPE_STACK[-1]}[$i]: \"${deferred[i]}\""
        if ! eval "${deferred[i]}"
        then
            bu_log_err "Cleanup failed: \"${deferred[i]}\""
            ret=1
        fi
    done
    unset -v "BU_SCOPE_CLEANUPS_${BU_SCOPE_STACK[-1]}" 'BU_SCOPE_STACK[-1]'
    return "$ret"
}

# ```
# *Description*:
# Pop the current function-level scope including all nested scopes from the scope stack and execute all registered cleanup commands
#
# *Params*: None
# *Returns*: None
#
# *Examples*:
# ```bash
# function my_function() {
#     bu_scope_push_function
#     touch /tmp/some_temp_file
#     bu_scope_add_cleanup rm -f /tmp/some_temp_file
#     if some_condition; then
#         # Nested scope
#         bu_scope_push
#         touch /tmp/some_temp_file2
#         bu_scope_add_cleanup rm -f /tmp/some_temp_file2
#         # Early return with cleanup
#         bu_scope_pop_function
#         return
#     fi
#     bu_scope_pop_function
# }
# ```
# ```
bu_scope_pop_function()
{
    if ((!"${#BU_SCOPE_STACK[@]}"))
    then
        bu_log_err -i 1 "Dynamic stack is empty"
        return 1
    fi

    local i
    for (( i=${#BU_SCOPE_STACK[@]}-1; i >= 0; i-- ))
    do
        if [[ "${BU_SCOPE_STACK[-1]:0:1}" == _ ]]
        then
            break
        fi
    done

    if (( i < 0 ))
    then
        log_err "No function-level scope found"
        return 1
    fi
    local j
    local target=$i
    local ret=0
    for (( i=${#BU_SCOPE_STACK[@]}-1; i >= "$target"; i-- ))
    do
        local -n deferred=BU_SCOPE_CLEANUPS_${BU_SCOPE_STACK[$i]}
        bu_log_debug "Cleaning up ${BU_SCOPE_STACK[-1]}"
        for (( j=${#deferred[@]}-1; j >= 0; j-- ))
        do
            bu_log_debug "Cleaning up ${BU_SCOPE_STACK[-1]}[$j]: \"${deferred[j]}\""
            if ! eval "${deferred[j]}"
            then
                bu_log_err "Cleanup failed: \"${deferred[j]}\""
                ret=1
            fi
        done
        unset -v "BU_SCOPE_CLEANUPS_${BU_SCOPE_STACK[$i]}" "BU_SCOPE_STACK[$i]"
    done
    return "$ret"
}

# ```
# *Description*:
# Pop all scopes from the scope stack and execute all registered cleanup commands
#
# *Params*: None
#
# *Returns*:
# - Exit code 0 if all cleanups succeeded, non-zero otherwise
#
# *Examples*:
# ```bash
# bu_scope_push
# touch /tmp/some_temp_file
# bu_scope_add_cleanup rm -f /tmp/some_temp_file
# bu_scope_push
# touch /tmp/some_temp_file2
# bu_scope_add_cleanup rm -f /tmp/some_temp_file2
# bu_scope_pop_all
# ```
# ```
bu_scope_pop_all()
{
    local exit_code=0
    for (( i=${#BU_SCOPE_STACK[@]}; i > 0; i-- ))
    do
        if ! bu_scope_pop
        then
            exit_code=1
        fi
    done
    return "$exit_code"
}

# MARK: Scope-related utilities

# ```
# *Description*:
# Call pushd with suppressed output
#
# *Params*:
# - `$1`: Directory to change to
#
# *Returns*:
# - Exit code of the `pushd` command
# ```
bu_pushd_silent()
{
    pushd "$1" >/dev/null
}

# ```
# *Description*:
# Call popd with suppressed output
#
# *Params*: None
#*Returns*:
# - Exit code of the `popd` command
# ```
bu_popd_silent()
{
    popd >/dev/null
}

# ```
# *Description*:
# Close file descriptors
#
# *Params*:
# - `...`: File descriptors to close
#
# *Returns*:
# - Exit code of the `exec` command
# ```
bu_close_fd()
{
    local exit_code=0
    local ret
    local fd
    for fd
    do
        exec {fd}>&-
        ret=$?
        if ((ret))
        then
            exit_code=$ret
        fi
    done
    return "$exit_code"
}

# ```
# *Description*:
# Set a shell option for the current scope, restoring the previous value when the scope is popped
#
# *Params*:
# - `$1`: Shell option to set (e.g. `errexit`, `nounset`, etc.)
#
# *Returns*: None
#
# *Examples*:
# ```bash
# bu_scope_push
# bu_scoped_set errexit
# some_command_that_may_fail
# bu_scope_pop
# ```
# ```
bu_scoped_set_opt()
{
    local opt=$1
    if ! [[ -o "$opt" ]]
    then
        set -o "$opt"
        bu_scope_add_cleanup set +o "$opt"
    fi
}

# ```
# *Description*:
# Unset a shell option for the current scope, restoring the previous value when the scope is popped
#
# *Params*:
# - `$1`: Shell option to unset (e.g. `errexit`, `nounset`, etc.)
#
# *Returns*: None
#
# *Examples*:
# ```bash
# bu_scope_push
# bu_scoped_unset nounset
# some_command_that_may_use_unset_variables
# bu_scope_pop
# ```
# ```
bu_scoped_unset_opt()
{
    local opt=$1
    if [[ -o "$opt" ]]
    then
        set +o "$opt"
        bu_scope_add_cleanup set -o "$opt"
    fi
}

# ```
# *Description*:
# Set or unset a shell option for the current scope, restoring the previous value when the scope is popped
#
# *Params*:
# - `$1`: Shell option to set or unset, prefixed with `-` to set or `+` to unset (e.g. `-errexit`, `+nounset`, etc.)
#
# *Returns*: None
#
# *Examples*:
# ```bash
# bu_scope_push
# bu_scoped_set -e
# some_command_that_may_fail
# bu_scope_pop
# ```
bu_scoped_set()
{
    local opt
    case "${1:1}" in
    a) opt=allexport;;
    B) opt=braceexpand;;
    e) opt=errexit;;
    E) opt=errtrace;;
    T) opt=functrace;;
    h) opt=hashall;;
    H) opt=histexpand;;
    k) opt=keyword;;
    m) opt=monitor;;
    C) opt=noclobber;;
    n) opt=noexec;;
    b) opt=notify;;
    u) opt=nounset;;
    t) opt=onecmd;;
    P) opt=physical;;
    f) opt=noglob;;
    v) opt=verbose;;
    x) opt=xtrace;;
    *) bu_log_unrecognized_option "$1"; return 1;;
    esac

    case "${1:0:1}" in
    +) bu_scoped_unset_opt "$opt";;
    -) bu_scoped_set_opt "$opt";;
    *) bu_log_unrecognized_option "$1"; return 1;;
    esac
}

# ```
# *Description*:
# Push a directory onto the directory stack and register a cleanup to pop it when the scope is popped
#
# *Params*:
# - `$1`: Directory to change to
#
# *Returns*: None
# ```
bu_scoped_pushd()
{
    bu_pushd_silent "$@"
    bu_scope_add_cleanup bu_popd_silent
}

# Number of source lines shown before and after each frame when
# BU_STACKTRACE_STYLE=full. Tunable via the environment (export it before
# sourcing) — not a registered setting because it is a plain integer.
BU_STACKTRACE_CONTEXT_LINES=${BU_STACKTRACE_CONTEXT_LINES:-2}

# awk program used by __bu_traceback_highlight. Kept as a quoted heredoc so
# the shell performs no expansion on the awk source. It performs a light,
# single-pass syntax highlight: bash reserved words, brackets/parens/braces,
# comments, and single/double-quoted strings. It deliberately does not parse
# `$((...))`, `${...}`, or heredocs — "light" highlighting trades a little
# precision for zero dependencies and speed on the error path.
BU_TRACEBACK_HIGHLIGHT_AWK=$(cat <<'AWK'
function add(text, color) {
    out = out (color != "" ? color : "") text (color != "" ? rs : "")
}
BEGIN {
    split("case coproc do done elif else esac fi for function if in select then time until while", tmp)
    for (k in tmp) keywords[tmp[k]] = 1
}
{
    line = $0
    out = ""
    state = "normal"
    buf = ""
    word = ""
    i = 1
    n = length(line)
    while (i <= n) {
        c = substr(line, i, 1)
        if (state == "comment") {
            add(substr(line, i), cm)
            break
        }
        if (state == "single") {
            if (c == "'") {
                buf = buf "'"
                add(buf, st)
                state = "normal"
            } else {
                buf = buf c
            }
            i++
            continue
        }
        if (state == "double") {
            if (c == "\\" && i < n) {
                buf = buf substr(line, i, 2)
                i += 2
                continue
            }
            if (c == "\"") {
                buf = buf "\""
                add(buf, st)
                state = "normal"
            } else {
                buf = buf c
            }
            i++
            continue
        }
        if (c == "#") {
            add(substr(line, i), cm)
            break
        }
        if (c == "'") {
            buf = "'"
            state = "single"
            i++
            continue
        }
        if (c == "\"") {
            buf = "\""
            state = "double"
            i++
            continue
        }
        if (c == "(" || c == ")" || c == "[" || c == "]" || c == "{" || c == "}") {
            add(c, br)
            i++
            continue
        }
        if (c ~ /[A-Za-z0-9_]/) {
            word = ""
            while (i <= n && substr(line, i, 1) ~ /[A-Za-z0-9_]/) {
                word = word substr(line, i, 1)
                i++
            }
            add(word, (word in keywords) ? kw : "")
            continue
        }
        add(c, "")
        i++
    }
    # An unterminated quote at end-of-line is still a string; emit what we
    # accumulated so it is not silently dropped.
    if (state == "single" || state == "double") {
        add(buf, st)
    }
    print out
}
AWK
)

# ```
# *Description*:
# Lightly syntax-highlight a single line of shell source: bash reserved words
# (violet), brackets/parens/braces (yellow), comments (grey, or blue on
# 8-colour terminals), and quoted strings (green). When the terminal has no
# color support the BU_TPUT_* codes are empty and the line is returned
# unchanged.
#
# *Params*:
# - `$1`: Source line to highlight
#
# *Returns*:
# - stdout: The highlighted line
# ```
__bu_traceback_highlight()
{
    local -r line=$1
    awk \
        -v kw="${BU_TPUT_VIOLET:-}" \
        -v br="${BU_TPUT_YELLOW:-}" \
        -v cm="${BU_TPUT_GREY:-${BU_TPUT_DARK_BLUE:-}}" \
        -v st="${BU_TPUT_GREEN:-}" \
        -v rs="${BU_TPUT_RESET:-}" \
        "$BU_TRACEBACK_HIGHLIGHT_AWK" <<<"$line"
}

# ```
# *Description*:
# Print one traceback frame in the short (single-line) style.
#
# *Params*:
# - `$1`: Frame index
# - `$2`: Command text (frame 0) or function name (later frames)
# - `$3`: Source file path
# - `$4`: Line number
# ```
__bu_traceback_print_frame_short()
{
    local -r idx=$1
    local -r what=$2
    local -r file=$3
    local -r line=$4
    printf "    %s: %s%s%s at %s%s:%s%s\n" \
        "$idx" \
        "$BU_TPUT_BOLD" "$what" "$BU_TPUT_RESET" \
        "$BU_TPUT_UNDERLINE" "$(basename -- "$file")" "$line" "$BU_TPUT_NO_UNDERLINE"
}

# ```
# *Description*:
# Print one traceback frame in the full (verbose) style: a Python-style
# "File ... line N, in func" header followed by the surrounding source lines,
# with the fault line highlighted. Falls back to a single grey line when the
# source file is unavailable (missing, unreadable, or a non-numeric line).
#
# *Params*:
# - `$1`: Command text (frame 0) or function name (later frames)
# - `$2`: Source file path
# - `$3`: Line number
# ```
__bu_traceback_print_frame_full()
{
    local -r what=$1
    local -r file=$2
    local -r line=$3

    printf '  File "%s", line %s, in %s\n' \
        "${BU_TPUT_UNDERLINE}$file${BU_TPUT_NO_UNDERLINE}" \
        "${BU_TPUT_BOLD}$line${BU_TPUT_RESET}" \
        "${BU_TPUT_BOLD}${what:-<module>}${BU_TPUT_RESET}"

    if [[ -z "$file" || ! -r "$file" || ! "$line" =~ ^[0-9]+$ ]]
    then
        printf '    %s<source unavailable>%s\n' "$BU_TPUT_GREY" "$BU_TPUT_RESET"
        return 0
    fi

    local -r context=${BU_STACKTRACE_CONTEXT_LINES:-2}
    local start=$((line - context))
    local end=$((line + context))
    ((start < 1)) && start=1

    local -a snippet=()
    mapfile -t snippet < <(sed -n "${start},${end}p" "$file" 2>/dev/null || true)

    if ((${#snippet[@]} == 0))
    then
        printf '    %s<no source at line %s>%s\n' "$BU_TPUT_GREY" "$line" "$BU_TPUT_RESET"
        return 0
    fi

    local -i n=$start
    local src src_hl
    for src in "${snippet[@]}"
    do
        src_hl=$(__bu_traceback_highlight "$src")
        if (( n == line ))
        then
            printf '  %s>%s %s%5d%s %s│%s %s\n' \
                "$BU_TPUT_RED" "$BU_TPUT_RESET" \
                "$BU_TPUT_RED" "$n" "$BU_TPUT_RESET" \
                "$BU_TPUT_GREY" "$BU_TPUT_RESET" \
                "$src_hl"
        else
            printf '    %s%5d%s %s│%s %s\n' \
                "$BU_TPUT_GREY" "$n" "$BU_TPUT_RESET" \
                "$BU_TPUT_GREY" "$BU_TPUT_RESET" \
                "$src_hl"
        fi
        n=$((n + 1))
    done
    return 0
}

# ```
# *Description*:
# Dispatch one traceback frame to the active rendering style.
#
# *Params*:
# - `$1`: Style (short or full)
# - `$2`: Frame index
# - `$3`: Command text (frame 0) or function name (later frames)
# - `$4`: Source file path
# - `$5`: Line number
# ```
__bu_traceback_print_frame()
{
    local -r style=$1
    local -r idx=$2
    local -r what=$3
    local -r file=$4
    local -r line=$5
    case "$style" in
    full)
        __bu_traceback_print_frame_full "$what" "$file" "$line"
        ;;
    *)
        __bu_traceback_print_frame_short "$idx" "$what" "$file" "$line"
        ;;
    esac
}

BU_EXIT_HANDLER_CLEANING_UP=false

# ```
# *Description*:
# Exit handler to perform cleanup and print traceback on error
#
# *Params*: None
#
# *Returns*: Exit code of the script
# ```
__bu_exit_handler()
{
    local exit_code=$?
    set +xv
    local debug=false # Set to true if needed
    local dev
    if "$debug"
    then
        dev=/dev/tty
    else
        dev=/dev/stdout
    fi
    # Two failure classes reach here with non-zero exit under errexit:
    # 1. A command genuinely failed → ERR trap captured BU_ERR_COMMAND
    #    and BU_ERR_LINENO.  A traceback is useful for debugging.
    # 2. The script validated input and bailed (bu_log_err + return 1).
    #    No command "failed", the ERR trap never fired, and the logged
    #    error is the diagnostic.  Printing empty-frame traceback noise
    #    here buries the real message and trains users to ignore them.
    #
    # Gate: only print the traceback block when the ERR trap actually
    # fired (BU_ERR_COMMAND is non-empty).  debug mode bypasses the gate
    # and always prints for troubleshooting.
    if "$debug" || { [[ $- =~ e && "$exit_code" != 0 && -n "${BU_ERR_COMMAND:-}" ]]; }
    then
        set +e
        {
        echo
        echo "Script exited with code: ${BU_TPUT_RED}$exit_code${BU_TPUT_RESET}"
        echo "Traceback (most recent call last):"
        local i file line what
        for i in "${!BASH_LINENO[@]}"
        do
            if (( i == 0 ))
            then
                what=$BU_ERR_COMMAND
                line=$BU_ERR_LINENO
                file=${BASH_SOURCE[i+1]}
            else
                # Skip top-of-stack frames that carry no information
                # (no function name and line 0 — remnant of the root
                # frame when the ERR trap never fired).
                if [[ -z "${FUNCNAME[i+1]:-}" && "${BASH_LINENO[i]:-}" == "0" ]]; then
                    continue
                fi
                what=${FUNCNAME[i+1]}
                line=${BASH_LINENO[i]}
                file=${BASH_SOURCE[i+1]}
            fi
            __bu_traceback_print_frame "${BU_STACKTRACE_STYLE:-short}" "$i" "$what" "$file" "$line"
        done
        } >"$dev"

        if "${BU_EXIT_HANDLER_VSCODE_POPUP:-false}"
        then
            if command -v code &>/dev/null
            then
                code --goto "${BASH_SOURCE[1]}${BU_ERR_LINENO:+:$BU_ERR_LINENO}"
            fi
        fi
    fi

    set +e
    BU_EXIT_HANDLER_CLEANING_UP=true
    if ! bu_scope_pop_all
    then
        bu_log_err Something failed during cleanup
    fi

    if "$debug"
    then
        sleep 120
    fi
    return "$exit_code"
}

# ```
# *Description*:
# Setup the exit handler without enabling errexit
#
# *Params*: None
# *Returns*: None
# ```
bu_exit_handler_setup_no_e()
{
    trap 'BU_ERR_LINENO=$LINENO; BU_ERR_COMMAND=$BASH_COMMAND' ERR
    trap __bu_exit_handler EXIT
}

# ```
# *Description*:
# Setup the exit handler with errexit enabled
#
# *Params*: None
# *Returns*: None
# ```
bu_exit_handler_setup()
{
    set -e -E
    bu_exit_handler_setup_no_e
}

bu_exit_handler_restore()
{
    if [[ $- == *e* ]]
    then
        bu_exit_handler_setup
    fi
}

# MARK: Synchronization, file management

# ```
# *Description*:
# Acquire an exclusive lock on a file, storing the lock file descriptor in a companion .lockfd file
#
# *Params*:
# - `$1`: File path to lock
#
# *Returns*: None
# ```
bu_sync_acquire_file()
{
    local file_path=$1
    local lockfile_path=${file_path}.lock
    local fd_path=${file_path}.lockfd
    local lockfile_fd=
    exec {lockfile_fd}>"$lockfile_path"
    flock --exclusive "$lockfile_fd"
    bu_log_debug "lockfile_fd[$lockfile_fd]"
    echo "$lockfile_fd" > "$fd_path"
}

# ```
# *Description*:
# Acquire an exclusive lock on a file descriptor
#
# *Params*:
# - `$1`: File descriptor to lock
#
# *Returns*: None
# ```
bu_sync_acquire_fd()
{
    local fd=$1
    bu_log_debug "fd[$fd]"
    flock --exclusive "$fd"
}

# ```
# *Description*:
# Release an exclusive lock on a file locked by bu_sync_acquire_file, using the lock file descriptor stored in the companion .lockfd file
#
# *Params*:
# - `$1`: File path to unlock
#
# *Returns*: None
# ```
bu_sync_release_file()
{
    local file_path=$1
    local lockfile_path=${file_path}.lock
    local fd_path=${file_path}.lockfd
    local lockfile_fd=
    if ! lockfile_fd=$(cat "$fd_path")
    then
        bu_log_err "cat fd_path[$fd_path] failed"
        return 1
    fi
    if [[ -z "$lockfile_fd" ]]
    then
        bu_log_err "lockfile doesn't contain fd"
        return 1
    fi
    : > "$fd_path"
    bu_log_debug "Unlocking file descriptor lockfile_fd[$lockfile_fd]"
    if ! flock --unlock "$lockfile_fd"
    then
        bu_log_err "Unlock lockfile_fd[$lockfile_fd] failed"
        if ! exec {lockfile_fd}>&-
        then
            bu_log_err "Could not close lockfile_fd[$lockfile_fd]"
        fi
        return 1
    fi
    bu_log_debug "Closing file descriptor lockfile_fd[$lockfile_fd]"
    if ! exec {lockfile_fd}>&-
    then
        bu_log_err "Close lockfile_fd[$lockfile_fd] failed"
        return 1
    fi
    return 0
}

# ```
# *Description*:
# Release an exclusive lock on a file descriptor locked by bu_sync_acquire_fd
#
# *Params*:
# - `$1`: File descriptor to unlock
#
# *Returns*: None
# ```
bu_sync_release_fd()
{
    local fd=$1
    bu_log_debug "Unlocking fd[$fd]"
    flock --unlock "$fd"
    bu_log_debug "Closing fd[$fd]"
    if ! exec {fd}>&-
    then
        bu_log_err "Close fd[$fd] failed"
        return 1
    fi
}

# ```
# *Description*:
# Cycle a log file, keeping only the last N (possibly unique) lines
# *Params*:
# - `$1`: File path to cycle
# - `$2`: Whether to acquire a lock on the file (true/false) whilst cycling
# - `$3` (optional): Number of lines to keep (default: all)
# - `$4`: Whether to keep only unique lines. 
#         If true, only the last occurrence of each line is kept. (more expensive operation)
#         If false, the uniq command is used to remove consecutive duplicate lines.
#
# *Returns*: None
# ```
bu_sync_cycle_file()
{
    local filepath=$1
    local should_lock=$2
    local num_lines=${3:-"+1"}
    local unique=$4

    if [[ ! -e "$filepath" ]]
    then
        return 0
    fi

    if "$should_lock"
    then
        if ! bu_sync_acquire_file "$filepath"
        then
            bu_log_warn "Failed to acquire filepath[$filepath]"
            return 0
        fi
    fi

    if "$unique"
    then
        tac "$filepath" | awk '! seen[$0] { seen[$0] = 1; print $0; }' | tac
    else
        uniq "$filepath"
    fi |\
    tail -n "$num_lines" > "$filepath".tmp

    mv "$filepath"{.tmp,}

    if "$should_lock"
    then
        if ! bu_sync_release_file "$filepath"
        then
            bu_log_err "Failed to release filepath[$filepath]"
            return 1
        fi
    fi
}

# ```
# *Description*:
# Cycle the last run commands log file, keeping only the last 500 unique lines
#
# *Params*: None
# *Returns*: None
# ```
bu_sync_cycle_last_run_cmds()
{
    bu_sync_cycle_file "$BU_LAST_RUN_CMDS" true 500 false || return 1
}

# ```
# *Description*:
# Cycle numbered files, e.g. log files
#
# *Params*:
# - `$1`: Base file name (without extension)
# - `$2`: Cycle length (number of files to keep)
# - `$3` (optional): Target directory (default: current directory)
# - `$4` (optional): File extension (default: log)
#
# *Returns*:
# - Exit code:
#   - `0`: Success
#   - `1`: Failure
# - `${BU_RET[@]}`: Array containing the write and read file descriptors for the new file
#                   (`BU_RET[0]`: write fd, `BU_RET[1]`: read fd)
#
# ```
bu_sync_cycle_numbered_files()
{
    local file_base=$1
    local cycle_length=$2
    local target_dir=${3:-.}
    local file_ext=${4:-log}

    mkdir -p "$target_dir"
    local original_dir=$PWD

    if ! cd "$target_dir" 2>/dev/null
    then
        bu_log_err "Failed to cd to $target_dir"
        return 1
    fi

    if ! bu_sync_acquire_file "$file_base"
    then
        bu_log_warn "Failed to acquire lock for file_base[$file_base]"
        cd "$original_dir" || true
        return 0
    fi

    # Rotate existing log files
    if [[ -e "$file_base"."$file_ext" ]]
    then
        mv "$file_base"{.,.0.}"$file_ext"
    fi

    local i
    for (( i = cycle_length; i > 0; i-- ))
    do
        if [[ -e "$file_base.$((i-1)).$file_ext" ]]
        then
            mv "$file_base.$((i-1)).$file_ext" "$file_base.$i.$file_ext"
        fi
    done

    # Create file descriptors for the new log file
    local read_fd=
    local write_fd=
    touch "$file_base.$file_ext"
    exec {write_fd}>"$file_base.$file_ext"
    exec {read_fd}<"$file_base.$file_ext"

    bu_sync_release_file "$file_base"

    BU_RET=("$write_fd" "$read_fd")
    cd "$original_dir" || return 1
}

# ```
# *Description*:
# Poll a log file for a pattern to appear (or disappear)
#
# *Params*:
# - `--negate` (optional): If present, wait for the pattern to disappear
# - `$1`: Log file path
# - `$2`: Pattern to wait for (regular expression)
# - `$3`: Error pattern (regular expression) that causes immediate failure if found
# - `$4` (optional): Poll timeout in seconds (default: 60)
# - `$5` (optional): Poll interval in seconds (default: 3)
# - `$6` (optional): File not exists timeout in seconds (default: 20)
#
# *Returns*:
# - Exit code:
#   - `0`: if the pattern was found (or disappeared, if `--negate` is used)
#   - `1`: if the error pattern was found or the timeout was reached
# ```
bu_sync_log_poll_wait()
{
    local is_negate=false
    if [[ "$1" = --negate ]]
    then
        is_negate=true
        shift
    fi

    local log_file=$1
    local wait_pattern=$2
    local error_pattern=$3
    local poll_timeout=${4:-60}
    local poll_interval=${5:-3}
    local file_not_exists_timeout=${6:-20}
    local start=$SECONDS
    local duration=
    local file_exists_wait=false

    while :
    do
        if [[ ! -e "$log_file" ]]
        then
            if "$file_exists_wait"
            then
                bu_log_err "We had already waited for the file once, but now it is gone"
                return 1
            fi

            file_exists_wait=true

            bu_log_warn "$log_file doesn't exist, sleeping for $file_not_exists_timeout seconds in case it is being generated"
            while :
            do
                sleep "$poll_interval"
                bu_log_info 'Waiting for file to exist'
                if [[ -e "$log_file" ]]
                then
                    break
                fi
                duration=$((SECONDS - start))
                bu_log_info "wait: $duration"
                if (( duration > file_not_exists_timeout ))
                then
                    bu_log_err "File still doesn't exist after $duration"
                    return 1
                fi
            done
        fi

        sleep "$poll_interval"
        bu_log_info "Waiting for pattern[$wait_pattern], is_negate[$is_negate]"
        if grep -qE "$wait_pattern" "$log_file"
        then
            if ! "$is_negate"
            then
                bu_log_success "Found pattern[$wait_pattern]"
                break
            fi
        else
            if "$is_negate"
            then
                bu_log_success "Pattern[$wait_pattern] no longer exists"
                break
            fi
        fi

        if [[ -n "$error_pattern" ]] && grep -E "$error_pattern" "$log_file"
        then
            bu_log_err "Found error[$error_pattern]"
            return 1
        fi
        duration=$((SECONDS - start))
        bu_log_info "wait: $duration"
        bu_log_cmd_info tail -n 5 "$log_file" || true
        if (( duration > poll_timeout ))
        then
            bu_log_err "wait failed after $duration seconds"
            return 1
        fi
    done
}

# ```
# *Description*:
# Wait for all fifos in the argument list to be written to
#
# *Params*:
# - `...`: List of fifo paths to wait on
#
# *Returns*:
# - Exit code:
#   - `0`: Success
#   - `1`: Failure
# ```
bu_sync_wait_group_wait()
{
    local fifo
    local discarded
    for fifo
    do
        if [[ ! -e "$fifo" ]]
        then
            bu_log_err "The fifo[$fifo] does not exist"
            return 1
        fi
        read -r discarded <"$fifo"
    done
}

# ```
# *Description*:
# Signal readiness to all fifos in the argument list by writing "ready" to them
#
# *Params*:
# - `...`: List of fifo paths to signal readiness to
#
# *Returns*:
# - Exit code:
#   - `0`: Success
#   - `1`: Failure
# ```
bu_sync_wait_group_ready()
{
    local fifo
    for fifo
    do
        if [[ ! -e "$fifo" ]]
        then
            bu_log_err "The fifo[$fifo] does not exist"
            return 1
        fi
        echo ready > "$fifo"
    done
}

# ```
# *Description*:
# Wait for all children to be ready, then signal readiness to them
#
# *Params*:
# - `...`: List of fifo paths to wait on and signal readiness to
#
# *Returns*:
# - Exit code:
#   - `0`: Success
#   - `1`: Failure
# ```
bu_sync_wait_group_parent()
{
    bu_log_info "Wait group: Waiting on children"
    bu_sync_wait_group_wait "$@" || return 1
    bu_log_info "Wait group: Children ready"
    bu_sync_wait_group_ready "$@" || return 1
    bu_log_info "Wait group: Unblocking children"
}

# ```
# *Description*:
# Signal readiness to the parent, then wait for the parent to be ready
#
# *Params*:
# - `$1`: Parent fifo path
#
# *Returns*:
# - Exit code:
#   - `0`: Success
#   - `1`: Failure
# ```
bu_sync_wait_group_child()
{
    if (($# != 1))
    then
        bu_log_err "Expected exactly 1 parent, got $# fifos[$*]"
        return 1
    fi
    bu_log_info "Wait group: Child ready"
    bu_sync_wait_group_ready "$1" || return 1
    bu_log_info "Wait group: Waiting on parent"
    bu_sync_wait_group_wait "$1" || return 1
    bu_log_info "Wait group: Parent ready"
}

# MARK: Environment/Path utilities
# ```
# *Description*:
# Get function definition location
#
# *Params*:
# - `$1`: Function name
#
# *Returns*:
# - `stdout`: Function definition location
# ```
bu_env_whichfunc()
{
    shopt -s extdebug
    declare -F "$1"
    shopt -u extdebug
}

# ```
# *Description*:
# Append a path to a generic path-like environment variable if it is not already present
#
# *Params*:
# - `$1`: Name of the path variable (e.g. PATH, LD_LIBRARY_PATH, etc.)
# - `$2`: Path to append
#
# *Returns*: None
# ```
__bu_env_append_generic_path()
{
    local -n __path_var=$1
    local path_to_append=$2
    if [[ ":$__path_var:" != *":$path_to_append:"* ]]
    then
        __path_var=${__path_var:+$__path_var:}$path_to_append
    fi
}

# ```
# *Description*:
# Prepend a path to a generic path-like environment variable if it is not already present
#
# *Params*:
# - `$1`: Name of the path variable (e.g. PATH, LD_LIBRARY_PATH, etc.)
# - `$2`: Path to prepend
#
# *Returns*: None
# ```
__bu_env_prepend_generic_path()
{
    local -n __path_var=$1
    local path_to_prepend=$2
    if [[ ":$__path_var:" != *":$path_to_prepend:"* ]]
    then
        __path_var=$path_to_prepend${__path_var:+:$__path_var}
    fi
}

# ```
# *Description*:
# Prepend a path to a generic path-like environment variable, even if it is already present
#
# *Params*:
# - `$1`: Name of the path variable (e.g. PATH, LD_LIBRARY_PATH, etc.)
# - `$2`: Path to prepend
#
# *Returns*: None
# ```
__bu_env_prepend_generic_path_force()
{
    local -n __path_var=$1
    local path_to_prepend=$2
    __path_var=$path_to_prepend${__path_var:+:$__path_var}
}

# ```
# *Description*:
# Append a path to the PATH environment variable if it is not already present
#
# *Params*:
# - `$1`: Path to append
#
# *Returns*: None
# ```
bu_env_append_path()
{
    __bu_env_append_generic_path PATH "$1"
}

# ```
# *Description*:
# Prepend a path to the PATH environment variable if it is not already present
#
# *Params*:
# - `$1`: Path to prepend
#
# *Returns*: None
# ```
bu_env_prepend_path()
{
    __bu_env_prepend_generic_path PATH "$1"
}

# ```
# *Description*:
# Prepend a path to the PATH environment variable, even if it is already present
#
# *Params*:
# - `$1`: Path to prepend
#
# *Returns*: None
# ```
bu_env_prepend_path_force()
{
    __bu_env_prepend_generic_path_force PATH "$1"
}

# ```
# *Description*:
# Prepend a path to the LD_LIBRARY_PATH environment variable if it is not already present
#
# *Params*:
# - `$1`: Path to prepend
#
# *Returns*: None
# ```
bu_env_append_ld_library_path()
{
    __bu_env_append_generic_path LD_LIBRARY_PATH "$1"
}

# ```
# *Description*:
# Prepend a path to the PYTHONPATH environment variable if it is not already present
#
# *Params*:
# - `$1`: Path to prepend
#
# *Returns*: None
# ```
bu_env_prepend_pythonpath()
{
    __bu_env_prepend_generic_path PYTHONPATH "$1"
}

# ```
# *Description*:
# Append a path to the PYTHONPATH environment variable if it is not already present
#
# *Params*:
# - `$1`: Path to append
#
# *Returns*: None
# ```
bu_env_append_pythonpath()
{
    __bu_env_append_generic_path PYTHONPATH "$1"
}

# ```
# *Description*:
# Prepend a path to the PYTHONPATH environment variable, even if it is already present
#
# *Params*:
# - `$1`: Path to prepend
#
# *Returns*: None
# ```
bu_env_prepend_pythonpath_force()
{
    __bu_env_prepend_generic_path_force PYTHONPATH "$1"
}

# ```
# *Description*:
# Remove a path from a generic path-like environment variable
#
# *Params*:
# - `$1`: Name of the path variable (e.g. PATH, LD_LIBRARY_PATH, etc.)
# - `$2`: Path to remove
#
# *Returns*: None
# ```
__bu_env_remove_from_generic_path()
{
    local -n __path_var=$1
    local path_to_remove=$2
    if [[ "$__path_var" = "$path_to_remove" ]]
    then
    __path_var=
    else
    __path_var=${__path_var//:$path_to_remove:/:} # delete instances in the middle
    __path_var=${__path_var#$path_to_remove:} # delete instance at the beginning
    __path_var=${__path_var%:$path_to_remove} # delete instance at the end
    fi
}

# ```
# *Description*:
# Remove a path from the PATH environment variable
#
# *Params*:
# - `$1`: Path to remove
#
# *Returns*: None
# ```
bu_env_remove_from_path()
{
    __bu_env_remove_from_generic_path PATH "$1"
}

# ```
# *Description*:
# Remove a path from the LD_LIBRARY_PATH environment variable
#
# *Params*:
# - `$1`: Path to remove
#
# *Returns*: None
# ```
bu_env_remove_from_ld_library_path()
{
    __bu_env_remove_from_generic_path LD_LIBRARY_PATH "$1"
}

# ```
# *Description*:
# Remove a path from the PYTHONPATH environment variable
#
# *Params*:
# - `$1`: Path to remove
#
# *Returns*: None
# ```
bu_env_remove_from_pythonpath()
{
    __bu_env_remove_from_generic_path PYTHONPATH "$1"
}

# ```
# *Description*:
# Rename a bash function
#
# *Params*:
# - `$1`: Old function name
# - `$2`: New function name
#
# *Returns*: None
# ```
bu_env_rename_func()
{
    local old_func_name=$1
    local new_func_name=$2

    eval "$(declare -f "$old_func_name" | sed -r "s/\b$old_func_name\b/$new_func_name/g")"
}

# ```
# *Description*:
# Check if the current shell session is inside a tmux session
#
# *Params*: None
#
# *Returns*:
# - Exit code:
#   - `0`: If in tmux
#   - `1`: If not in tmux
# ```
bu_env_is_in_tmux()
{
    [[ -n "${TMUX:-}" && ("${TERM:-}" == screen* || "${TERM:-}" == tmux*) ]]
}

# ```
# *Description*:
# Check if the current shell code is executing in an autocomplete context
#
# *Params*: None
#
# *Returns*:
# - Exit code:
#   - `0`: If in autocomplete context
#   - `1`: If not in autocomplete context
#
# *Notes*
# - Set BU_COMP_FAKE to a non-empty value to force this to be false
# ```
bu_env_is_in_autocomplete()
{
    [[ -n "${COMP_CWORD:-}" && -z "${BU_COMP_FAKE:-}" ]]
}

# MARK: Run utils
# ```
# *Description*:
# Execute a command with caching based on specified environment variables and bash variables
#
# *Params*:
# - `--check`: If present, only check if the command is cached, do not execute it
# - `--error-pattern <pattern>`: Regular expression pattern to search for in the command output that indicates an error
# - `--allow-empty`: If present, do not treat empty output as an error
# - `--env-vars <var1,var2,...>`: Comma-separated list of environment variable names to include in the cache key
# - `--bash-vars <var1,var2,...>`: Comma-separated list of bash variable names to include in the cache key
# - `--dir <cache_dir>`: Directory to use for caching (default: `$BU_HASHED_CACHE_DIR`)
# - `--invalidate` or `--invalidate-cache`: If present, invalidate the cache for this command before executing
# - `--invalidate-bool` or `--invalidate-cache-bool <true|false>`: Boolean to control cache invalidation
# - `--strict-equality`: If present, use strict equality (including command line) for cache hits
# - `--`: End of options; the remaining arguments are treated as the command to execute
# - `...`: Command and its arguments to execute
#
# *Returns*:
# - Exit code:
#   - `0`: If the command was executed successfully or the cached output was used
#   - `1`: If the command failed, the error pattern was found, or the output was empty (unless `--allow-empty` is used)
# - `stdout`: The output of the command, either from cache or from execution
# - If `--check` is used, the command outputs the cache key and returns `0` if cached, `1` if not cached
# ```
bu_cached_execute()
{
    local is_check=false
    local error_pattern=
    local error_if_empty=true
    local cache_env_vars=()
    local cache_bash_vars=()
    local cache_dir=$BU_HASHED_CACHE_DIR
    local is_strict_equality=false
    local is_invalidate_cache=false

    local shift_by
    while (($#))
    do
        shift_by=1
        case "$1" in
        --check)
            is_check=true
            ;;
        --error-pattern)
            error_pattern=$2
            shift_by=2
            ;;
        --allow-empty)
            error_if_empty=false
            ;;
        --env-vars)
            bu_str_split , "$2" cache_env_vars
            shift_by=2
            ;;
        --bash-vars)
            bu_str_split , "$2" cache_bash_vars
            shift_by=2
            ;;
        --dir)
            cache_dir=$2
            shift_by=2
            ;;
        --invalidate|--invalidate-cache)
            is_invalidate_cache=true
            ;;
        --invalidate-bool|--invalidate-cache-bool)
            is_invalidate_cache=$2
            shift_by=2
            ;;
        --strict-equality)
            is_strict_equality=true
            ;;
        --)
            shift
            break
            ;;
        -*)
            bu_log_unrecognized_option "$1"
            return 1
            ;;
        *)
            break
            ;;
        esac

        shift "$shift_by"
    done

    if "$BU_INVALIDATE_CACHE"
    then
        is_invalidate_cache=true
    fi

    local command_line=("$@")
    if ! bu_symbol_is_function "${command_line[0]}" && ((${#cache_bash_vars[@]}))
    then
        bu_log_err "Cannot specify --bash-var when not calling a bash function"
        return 1
    fi

    local tmpfile
    local do_cache=true
    if ! tmpfile=$(mktemp "$BU_OUT_DIR"/bu_cached_execute.XXXXXXXXXX)
    then
        do_cache=false
    fi
    
    local hash_value
    if ! hash_value=$({
        if ((${#cache_bash_vars[@]}))
        then
            declare -p "${cache_bash_vars[@]}" | awk '{print $NF}'
        fi
        if ((${#cache_env_vars[@]}))
        then
            paste -d = <(printf '%s\n' "${cache_env_vars[@]}") <(printenv "${cache_env_vars[@]}")
        fi
        printf '%s ' "${command_line[@]}"
    } | tee "$tmpfile" | md5sum | awk '{print $1}')
    then
        bu_log_err 'Generation of cache key failed'
        do_cache=false
    fi

    if "$do_cache"
    then
        local need_to_run=true
        local stdout_file=$cache_dir/$hash_value.stdout.txt
        local command_file=$cache_dir/$hash_value.command.txt
        if "$is_invalidate_cache"
        then
            rm -f "$stdout_file"
        elif [[ -e "$stdout_file" ]]
        then
            if ! "$is_strict_equality" || diff "$tmpfile" "$command_file"
            then
                need_to_run=false
            fi
        fi

        if "$is_check"
        then
            printf '%s\n' "$hash_value"
            if "$need_to_run"
            then
                return 1
            else
                return 0
            fi
        fi

        if "$need_to_run"
        then
            mv "$tmpfile" "$command_file"
            bu_log_warn "Cache not found, running command ${command_line[*]}"
            local command_failed=false
            if ! "${command_line[@]}" > "$stdout_file"
            then
                command_failed=true
            fi

            if [[ -n "$error_pattern" ]]
            then
                bu_log_debug "Checking for error pattern: $error_pattern"
                if grep -E "$error_pattern" "$stdout_file"
                then
                    bu_log_err "Found error_pattern[$error_pattern]"
                    command_failed=true
                fi
            fi

            if "$error_if_empty"
            then
                bu_log_debug 'Checking if output is blank'
                if [[ -z $(grep '[^[:space:]]' "$stdout_file") ]]
                then
                    bu_log_err 'Command did not give any output (pass --allow-empty to skip this check)'
                    command_failed=true
                fi
            fi

            if "$command_failed"
            then
                bu_log_err "Command ${command_line[*]} failed"
                rm -f "$stdout_file" "$command_file"
                return 1
            fi
        else
            if "$error_if_empty"
            then
                bu_log_debug 'Checking if output is blank'
                if [[ ! -s "$stdout_file" ]]
                then
                    bu_log_err 'Command did not give any output (pass --allow-empty to skip this check)'
                    rm -f "$stdout_file" "$command_file"
                    return 1
                fi
            fi
        fi
        cat "$stdout_file"
    else
        "${command_line[@]}"
    fi

    if [[ -e "$tmpfile" ]]
    then
        rm -f "$tmpfile"
    fi

    return 0
}

# ```
# *Description*:
# Cycle command logs, keeping only a specified number of log files
#
# *Params*:
# - `$1`: Command name (used as the base name for log files)
# - `$2`: Cycle length (number of log files to keep)
#
# *Returns*:
# - `${BU_RET[@]}`: Array containing the write and read file descriptors for the new log file
#                   (`${BU_RET[0]}`: write fd, `${BU_RET[1]}`: read fd)
# ```
__bu_cycle_logs()
{
    BU_RET=()
    local command=$1
    local cycle_length=$2
    mkdir -p "$BU_LOG_DIR/$command"
    pushd "$BU_LOG_DIR" &>/dev/null

    if ! bu_sync_acquire_file "$command"
    then
        bu_log_warn "Failed to acquire command[$command]"
        return 1
    fi

    pushd "$command" &>/dev/null

    if [[ -e "$command.log" ]]
    then
        mv "$command.log" "$command.0.log"
    fi

    for (( i = cycle_length; i > 0; i-- ))
    do
        if [[ -e "$command.$((i-1)).log" ]]
        then
            mv "$command.$((i-1)).log" "$command.$i.log"
        fi
    done

    local read_fd=
    local write_fd=
    touch "$command.log"
    exec {write_fd}>"$command.log"
    exec {read_fd}<"$command.log"

    popd &>/dev/null

    bu_sync_release_file "$command"

    BU_RET=("$write_fd" "$read_fd")
    popd &>/dev/null
}

# ```
# *Description*:
# Log the current command to the last run commands history file
#
# *Params*:
# - `...`: Arguments to log (typically `$@` from the calling function)
#
# *Returns*: None
#
# *Examples*:
# ```bash
# bu_run_log_command "$@"
# ```
#
# *Notes*:
# - Does nothing if called from autocomplete context to avoid spam
# - Writes to `$BU_LAST_RUN_CMDS` file
# - The file will get trimmed if it gets too long
# - The command will be logged as: `<calling_script_name> <arguments>`
# ```
bu_run_log_command()
{
    if bu_env_is_in_autocomplete
    then
        return 0
    fi

    bu_basename "${BASH_SOURCE[1]}" 
    printf '%q ' "$BU_RET" "$@" >> "$BU_LAST_RUN_CMDS"
    bu_scope_add_cleanup bu_sync_cycle_last_run_cmds
}

# ```
# *Description*:
# Edit one or more files with the configured editor
#
# *Params*:
# - `...`: File paths to edit
#
# *Returns*: None
#
# *Examples*:
# ```bash
# bu_edit_file /path/to/file1.txt
# bu_edit_file /path/to/file1.txt /path/to/file2.txt
# ```
#
# *Notes*:
# - Uses `$VISUAL` or `$EDITOR` environment variables to determine the editor
# - Supports special handling for VS Code (both `code` and `bu_code_wait.sh`)
# - Falls back to VS Code (if available) or vim if no editor is configured
# ```
bu_edit_file()
{
    local files=("$@")
    if ((!$#))
    then
        bu_log_warn 'No files given'
        return
    fi
    local editor=${VISUAL:-$EDITOR}
    case "$editor" in
    *'bu_code_wait.sh'|'code '*)
        code "${files[@]}"
        ;;
    '')
        if command -v code &>/dev/null
        then
            code "${files[@]}"
        elif command -v vim &>/dev/null
        then
            vim "${files[@]}"
        elif command -v vi &>/dev/null
        then
            vi "${files[@]}"
        else
            bu_log_err "No editor found"
        fi
        ;;
    *)
        $editor "${files[@]}"
        ;;
    esac
}

# ```
# *Description*:
# Open a log file with the configured editor or viewer
#
# *Params*:
# - `$1`: Log file path to open
#
# *Returns*: None
#
# *Examples*:
# ```bash
# bu_run_open_logs /path/to/logfile.log
# ```
#
# *Notes*:
# - Uses `$VISUAL` or `$EDITOR` environment variables to determine the editor/viewer
# - Supports special handling for VS Code (both `code` and `bu_code_wait.sh`)
# - Falls back to VS Code (if available) or `less` if no editor is configured
# ```
bu_run_open_logs()
{
    local log_file=$1
    local editor=${VISUAL:-$EDITOR}
    case "$editor" in
    *'bu_code_wait.sh'|'code '*)
        code "$log_file"
        ;;
    '')
        if command -v code &>/dev/null
        then
            code "$log_file"
        else
            less "$log_file"
        fi 
        ;;
    *)
        $editor "$log_file"
        ;;
    esac
}

# ```
# *Description*:
# Sleep for a specified number of seconds, optionally displaying a progress bar if `tqdm` is available.
#
# *Params*:
# - `$1`: Number of seconds to sleep
#
# *Returns*: None
# ```
bu_sleep()
{
    local num_seconds=$1
    bu_log_info "Sleeping for $num_seconds seconds"
    if command -v tqdm &>/dev/null
    then
        for i in $(seq "$num_seconds")
        do
            sleep 1
            echo
        done | tqdm --total "$num_seconds" >/dev/null
    else
        sleep "$num_seconds"
    fi
}

# ```
# *Description*:
# Run a command with various options such as logging, debugging, and working directory management.
#
# *Params*:
# - `--gdb`: Run the command under gdb
# - `--log`: Enable logging to a file
# - `--log-stdout`: Enable logging to stdout
# - `--copy-logs-to <path>`: Copy logs to the specified path after execution
# - `--open-logs`: Open the log file after execution
# - `--kill`: Kill existing instances of the command before running
# - `--ignore-non-zero-exit-code`: Ignore non-zero exit codes from the command
# - `--watch <interval>`: Re-run the command at the specified interval (in seconds)
# - `--ldd`: Print the output of `ldd` for the command before running
# - `--dry-run`: Print the command that would be run without actually executing it
# - `--cached`: Run the command with caching
# - `--no-log-last-run-cmd`: Do not log the command to the last run commands history
# - `--cmd-log-file <file>`: Log the command to the specified file
# - `--working-directory <dir>`: Change to the specified working directory before running the command
# - `--mapfile`: Capture the command's output into an array variable
# - `--mapfile-str`: Capture the command's output into a string variable
# - `--mapfile-outparam <var>`: Specify the output variable name for mapfile options (default: BU_RET)
# - `--tmux-name <name>`: Set the tmux window name to the specified name
# - `--wait-group <fifo>`: Use the specified fifo for wait group synchronization
# - `--`: End of options; the remaining arguments are treated as the command to run
# - `...`: Command and its arguments to run
#
# *Returns*:
# - Exit code:
#   - `0`: If the command was executed successfully
#   - `1`: If the command failed (unless `--ignore-non-zero-exit-code` is used)
# - `${BU_RET[@]}`: If `--mapfile`, contains the command's output
# - `${BU_RET}`: If `--mapfile-str`, contains the command's output as a string
# ```
bu_run()
{
    bu_scope_push_function
    local invocation_dir=$PWD
    local is_gdb=false
    local is_log=false
    local is_log_stdout=false
    local copy_logs_to=
    local is_open_logs=false
    local is_kill_existing=false
    local is_ignore_non_zero_exit_code=false
    local watch_interval=
    local is_ldd=false
    local is_dry_run=false
    local is_cached_execute=false
    local is_log_last_run_cmd=true
    local cmd_log_file=
    local working_directory=
    local is_mapfile=false
    local is_mapfile_str=false
    local mapfile_outparam=BU_RET
    local tmux_name=
    local wait_group_fifo=
    local shift_by
    while (($#))
    do
        shift_by=1
        case "$1" in
        --gdb)
            is_gdb=true
            ;;
        --log)
            is_log=true
            ;;
        --log-stdout)
            is_log_stdout=true
            ;;
        --copy-logs-to)
            copy_logs_to=$2
            shift_by=2
            ;;
        --open-logs)
            is_open_logs=true
            ;;
        --kill)
            is_kill_existing=true
            ;;
        --ignore-non-zero-exit-code)
            is_ignore_non_zero_exit_code=true
            ;;
        --watch)
            watch_interval=$2
            shift_by=2
            ;;
        --ldd)
            is_ldd=true
            ;;
        --dry-run)
            is_dry_run=true
            ;;
        --cached)
            is_cached_execute=true
            ;;
        --no-log-last-run-cmd)
            is_log_last_run_cmd=false
            ;;
        --cmd-log-file)
            cmd_log_file=$2
            shift_by=2
            ;;
        --working-directory)
            working_directory=$(realpath -- "$2")
            shift_by=2
            ;;
        --mapfile)
            is_mapfile=true
            ;;
        --mapfile-str)
            is_mapfile_str=true
            ;;
        --mapfile-outparam)
            mapfile_outparam=$2
            shift_by=2
            ;;
        --tmux-name)
            tmux_name=$2
            shift_by=2
            ;;
        --wait-group)
            wait_group_fifo=$2
            shift_by=2
            ;;
        "")
            # Swallow empty options to support patterns like "$optional_option" which could be an empty string
            ;;
        --)
            shift
            break
            ;;
        -*)
            bu_log_unrecognized_option "$1"
            bu_scope_pop_function
            return 1
            ;;
        *)
            # While -- is more rigorous, this is more user-friendly.
            break
            ;;
        esac
        shift "$shift_by"
    done

    local command_list=("$@")
    local command_type
    if ! command_type=$(type -t "$command_list")
    then
        bu_log_err "type $command_list failed"
        return 1
    fi

    case "$command_type" in
    function|alias)
        ;;
    file)
        if ! command_list[0]=$(command -v "$command_list")
        then
            bu_log_err "command -v $command_list" failed
            bu_scope_pop_function
            return 1
        fi
        ;;
    *)
        bu_log_err "Unexpected type $command_type"
        bu_scope_pop_function
        return 1
    esac
    bu_basename "$command_list"
    local command_base=$BU_RET
    local gdb_prefix=()
    local cached_execute_prefix=()
    if "$is_gdb"
    then
        gdb_prefix=(gdb)
        gdb_prefix+=("${command_list[0]}" --args)
        if "$is_log" || "$is_log_stdout"
        then
            bu_log_warn "Logging not supported when debugging with gdb"
            is_log=false
            is_log_stdout=false
            copy_logs_to=
        fi
    elif "$is_cached_execute"
    then
        cached_execute_prefix=(bu_cached_execute)
    else
        # TODO: Trap here?
        :
    fi

    if "$is_log_last_run_cmd"
    then
        {
            printf '%q ' "${command_list[@]}"
            echo
        } >> "$BU_LAST_RUN_CMDS"

        if [[ -n "$cmd_log_file" ]]
        then
            bu_dirname "$cmd_log_file"
            local cmd_log_file_dir=$BU_RET
            bu_mkdir "$cmd_log_file_dir"
            {
                printf '%q ' "${command_list[@]}"
                echo
            } >> "$cmd_log_file"
        fi

        if bu_env_is_in_tmux
        then
            tmux rename-window -t "$TMUX_PANE" "${tmux_name:-$command}"
        fi
    fi

    if "$is_ldd"
    then
        bu_log_info "LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
        bu_log_cmd_info ldd "${command_list[0]}"
    fi

    bu_log_cmd_info printf '%q ' "PWD=$PWD" "${gdb_prefix[@]}" "${cached_execute_prefix[@]}" "${command_list[@]}"

    local log_file=$BU_LOG_DIR/$command_base/$command_base.log
    if "$is_dry_run"
    then
        bu_log_info 'Dry-run, not actually running'
        # This is a hack to open the last log from the previous run
        if "$is_open_logs"
        then
            bu_run_open_logs "$log_file"
        fi
        bu_scope_pop_function
        return 0
    fi

    if "$is_kill_existing"
    then
        bu_log_info 'Killing existing command'
        local command_count=$(pkill -u "$USER" --count --full "${command_list[*]}")
        case "$command_count" in
        0) ;;
        1)
            pkill -u "$USER" --signal SIGTERM --full "${command_list[*]}" || true
            sleep 5
            local new_command_count=$(pkill -u "$USER" --count --full "${command_list[*]}")
            case "$new_command_count" in
            0)
                bu_log_success 'pkill is successful'
                ;;
            1)
                bu_log_warn 'SIGTERM not successful, falling back to SIGKILL'
                pkill -u "$USER" --signal SIGKILL --full "${command_list[*]}" || true
                sleep 5
                new_command_count=$(pkill -u "$USER" --count --full "${command_list[*]}")
                if ((new_command_count))
                then
                    bu_log_err 'For some reason even SIGKILL did not kill the command, or maybe this is a new instance'
                    bu_scope_pop_function
                    return 1
                fi
                ;;
            esac
            ;;
        *)
            bu_log_err "More than 1 instance of ${command_list[*]} found"
            bu_scope_pop_function
            return 1
        esac
    fi

    local write_fd
    local read_fd
    if "$is_log" || "$is_log_stdout"
    then
        __bu_cycle_logs "$command_base" 5
        write_fd=${BU_RET[0]}
        read_fd=${BU_RET[1]}
        bu_scope_add_cleanup bu_close_fd "$write_fd" "$read_fd"
    fi

    if [[ -n "$wait_group_fifo" ]]
    then
        if ! bu_sync_wait_group_child "$wait_group_fifo"
        then
            bu_log_err "Wait group failed"
            return 1
        fi
    fi

    local command_exit_code=0
    bu_scope_push
    if [[ -z "$working_directory" ]]
    then
        bu_scoped_pushd "$invocation_dir"
    else
        bu_scoped_pushd "$working_directory"
    fi
    bu_scoped_set +e
    bu_scoped_set_opt pipefail

    if [[ -n "$watch_interval" ]]
    then
        watch -n "$watch_interval" "${command_list[@]}"
    elif "$is_log"
    then
        "${command_list[@]}" |& tee --ignore-interrupts /dev/fd/"$write_fd"
        command_exit_code=$?
    elif "$is_log_stdout"
    then
        "${command_list[@]}" | tee --ignore-interrupts /dev/fd/"$write_fd"
    else
        local command_escaped=$(printf '%q ' "${gdb_prefix[@]}" "${cached_execute_prefix[@]}" "${command_list[@]}")
        eval "$command_escaped"
        command_exit_code=$?
    fi
    bu_scope_pop

    if [[ -n "$copy_logs_to" ]]
    then
        if ! "$is_log" && ! "$is_log_stdout"
        then
            bu_scope_pop_function
            bu_log_err 'Logging not enabled, but --copy-logs-to specified'
            return 1
        fi
        if [[ -d "$copy_logs_to" ]]
        then
            copy_logs_to=$copy_logs_to/$command_base.log
        else
            bu_dirname "$copy_logs_to"
            bu_mkdir "$BU_RET"
        fi
        if [[ -n "$read_fd" ]]
        then
            cp /dev/fd/"$read_fd" "$copy_logs_to"
            bu_log_info "Logs are copied to $(realpath -- "$copy_logs_to")"
        else
            bu_log_err 'Logic error, read_fd is empty'
        fi
    elif "$is_log" || "$is_log_stdout"
    then
        bu_log_info "Logs are at $log_file"
    fi

    if "$is_mapfile" || "$is_mapfile_str"
    then
        if ! "$is_log" && ! "$is_log_stdout"
        then
            bu_log_err 'Logging not enabled, but --mapfile/--mapfile-str specified'
            bu_scope_pop_function
            return 1
        fi
        local mapfile_file=
        if [[ -n "$copy_logs_to" ]]
        then
            mapfile_file=$copy_logs_to
        elif [[ -n "$read_fd" ]]
        then
            mapfile_file=/dev/fd/$read_fd
        else
            bu_log_err 'Logic error, read_fd is empty'
        fi

        if "$is_mapfile"
        then
            mapfile -t "$mapfile_outparam" <"$mapfile_file"
        else
            mapfile -d '' "$mapfile_outparam" <"$mapfile_file"
        fi
    fi

    if "$is_open_logs"
    then
        if [[ -n "$copy_logs_to" ]]
        then
            bu_run_open_logs "$copy_logs_to"
        else
            bu_run_open_logs "$log_file"
        fi
    fi

    if "$is_ignore_non_zero_exit_code" && ((command_exit_code))
    then
        bu_log_warn "Command $command_base exited with non-zero exit code[$command_exit_code], ignoring..."
        bu_scope_pop_function
        return 0
    fi

    bu_scope_pop_function
    return "$command_exit_code"
}

# MARK: VSCode

bu_vscode_find_latest_server()
{
    if "$BU_ENV_IS_WSL"
    then
        ls -dt "$HOME"/.vscode-server/bin/* 2>/dev/null | head -n 1
    else
        ls -dt "$HOME"/.vscode-server/cli/servers/Stable-* 2>/dev/null | head -n 1
    fi
}

bu_vscode_find_latest_socket()
{
    if "$BU_ENV_IS_WSL"
    then
        ls -t /tmp/vscode-ipc* 2>/dev/null | head -n 1
    else
        ls -t /run/user/"$UID"/vscode-ipc* 2>/dev/null | head -n 1
    fi
}

bu_vscode_is_socket_inactive()
{
    local grep_result
    if ! grep_result=$(timeout 1 code --status |& grep --only-matching --max-count=1 -E 'Version|ENOENT')
    then
        return 1
    fi
    case "$grep_result" in
    Version)
        return 0
        ;;
    ENOENT)
        return 1
        ;;
    *)
        return 1
        ;;
    esac
}

# MARK: Pretty 

# ```
# *Description*:
# Pretty print associative (or non-associative) array variable
#
# *Params*:
# - `$1`: Name of the associative array variable
#
# *Returns*:
# - `stdout`: Pretty printed key-value pairs of the associative array
# ```
bu_print_var()
{
    local -n __bu_print_var_name=$1
    local key
    local value
    printf "name: %s\nvalue:\n" "$1"
    for key in "${!__bu_print_var_name[@]}"
    do
        printf "  [%s]=%s\n" "$key" "${__bu_print_var_name[$key]}"
    done
}

# ```
# *Description*:
# Pretty print the current scope stack
#
# *Params*: None
#
# *Returns*:
# - `stdout`: Pretty printed scope stack
# ```
bu_scope_print()
{
    bu_print_var BU_SCOPE_STACK
}

# MARK: Code gen

# ```
# *Description*:
# Substitute variables in the input stream
#
# *Params*:
# - `...`: List of variable names or functions to substitute.
#          Note that functions do not take any parameters,
#          so they are more like computed variables.
#
# *Returns*:
# - `stdout`: Input stream with variables substituted
# ```
bu_gen_substitute()
{
    bu_scope_push
    bu_scoped_set_opt pipefail
    local vars_to_subst=("$@")
    local var
    local sed_expr=()
    local value
    local var_result
    for var in "${vars_to_subst[@]}"
    do
        case "$(type -t "$var")" in
        function|file)
            var_result="$var"_result
            if [[ -z "${var_result}" ]]
            then
                if ! value=$("$var" | tr '\n' '\0' | sed 's/\x00/\\n/g')
                then
                    bu_log_err "Evaluation of $var failed"
                    bu_scope_pop
                    return 1
                fi
                declare -g "$var"_result=$value
            else
                value=${!var_result}
            fi
            ;;
        *)
            if [[ ! -v "$var" ]]
            then
                bu_log_warn "$var is undefined, despite being in the substitution list, skipping..."
                continue
            fi
            value=${!var}
            ;;
        esac
        if bu_is_null "$value"
        then
            continue
        fi
        sed_expr+=('s'$'\001''@'"$var"'@'$'\001'"$value"$'\001''g')
    done
    printf '%s\n' "${sed_expr[@]}" > "$BU_PROC_TMP_DIR"/sed.txt
    sed -f "$BU_PROC_TMP_DIR"/sed.txt
    bu_scope_pop
}



# MARK: Bindings

# ```
# *Description*:
# Edit the current command line using the default editor
# Meant to be bound to a readline keybinding
# ```
__bu_bind_edit()
{
    local editor=${VISUAL:-${EDITOR:-vim}}
    local tmp_file=$(mktemp).sh
    printf '%s\n' "$READLINE_LINE" > "$tmp_file"
    $editor "$tmp_file"
    READLINE_LINE=$(< "$tmp_file")
    READLINE_POINT=${#READLINE_LINE}
    rm -f "$tmp_file"
}

# ```
# *Description*:
# Toggle gdb prefix on the current command line
# Meant to be bound to a readline keybinding
# ```
__bu_bind_toggle_gdb()
{
    local words=()
    read -r -a words <<<"$READLINE_LINE"
    case "$words" in
    gdb) words=("${words[@]:3}") ;;
    '') return ;;
    *) words=(gdb "${words[0]}" --args "${words[@]}")
    esac
    READLINE_LINE=${words[*]}
}
