# bash-ide source=./bu_core_base.sh
# bash-ide source=./bu_core_autocomplete.sh
# bash-ide source=./bu_core_early_init.sh
# bash-ide source=../../config/bu_config_static.sh

# MARK: Initialization logic
__bu_init_env()
{
    bu_env_append_path "$BU_LIB_BIN_DIR"
    __bu_init_env_commands
}

# ```md
# Whether `bind -x` handlers must go through `__bu_bind_x_run`.
#
# Before bash 5.2, an interactive bash snapshots the tty as its "cooked"
# state after every foreground job that exits normally, skipping that only
# during programmable completion (jobs.c `wait_for` -> `get_tty_state`). A
# `bind -x` handler runs with readline's raw termios still applied, so any
# plain external command inside it stores raw mode as cooked; the next
# foreground job killed by a signal makes bash re-apply that snapshot and
# keystrokes stop echoing until `stty sane`. bash 5.2 also skips the snapshot
# while readline is dispatching a key with the terminal prepped
# (CHANGES, bash-5.2-beta: "Fixed a problem with SIGINT during the execution
# of a command bound with `bind -x' affecting the saved terminal settings"),
# so 5.2+ binds handlers directly, exactly as before.
# ```
BU_BIND_X_NEEDS_TTY_GUARD=false
if (( BASH_VERSINFO[0] < 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] < 2) ))
then
    BU_BIND_X_NEEDS_TTY_GUARD=true
fi

# ```md
# Dispatcher for `bind -x` handlers on bash < 5.2 (see
# BU_BIND_X_NEEDS_TTY_GUARD for the bug it works around).
#
# Two halves, both required:
# 1. A subshell killed by SIGPIPE is a signalled foreground job, so bash
#    re-applies its last *cooked* snapshot before the handler body runs. The
#    body then runs cooked, and every plain job inside snapshots cooked.
#    SIGPIPE deaths are never reported (DONT_REPORT_SIGPIPE is bash's
#    default), so this prints nothing.
# 2. Readline's mode is put back through command substitution: a comsub child
#    is not a job and is not snapshotted. A plain `stty` here would store raw
#    mode again and recreate the bug.
# Without a controlling tty the command simply runs.
#
# Params:
# - $1: command text, eval'd (what `bind -x` would otherwise run verbatim)
# ```
__bu_bind_x_run()
{
    local __bu_bx_pre
    if ! __bu_bx_pre=$(stty -g </dev/tty 2>/dev/null)
    then
        eval "$1"
        return
    fi
    ( kill -PIPE "$BASHPID" ) || :
    eval "$1"
    : "$(stty "$__bu_bx_pre" </dev/tty 2>/dev/null)"
}

__bu_init_keybindings()
{
    if [[ $- == *i* ]]
    then
        local shortcut_key
        for shortcut_key in "${!BU_KEY_BINDINGS[@]}"
        do
            bu_log_debug "Mapping shortcut_key[$shortcut_key] to command[${BU_KEY_BINDINGS[$shortcut_key]}]"
            if "$BU_BIND_X_NEEDS_TTY_GUARD"
            then
                # `bind -x` reparses its command text: pass the value as one
                # quoted word for the dispatcher to eval.
                bind -x '"'"$shortcut_key"'": __bu_bind_x_run '"$(printf '%q' "${BU_KEY_BINDINGS[$shortcut_key]}")"
            else
                bind -x '"'"$shortcut_key"'": '"${BU_KEY_BINDINGS[$shortcut_key]}"
            fi
        done

        if "${BU_AUTOCOMPLETE_BIND_TAB_TO_FZF:-false}"
        then
            bu_autocomplete_enable_tab
        fi
    fi
}

BU_DEFAULT_EDITOR=${VISUAL:-}
BU_DEFAULT_TERMINAL_EDITOR=${EDITOR:-}
__bu_init_editor()
{
    if [[ -n "$BU_DEFAULT_EDITOR" || -n "$BU_DEFAULT_TERMINAL_EDITOR" ]]
    then
        return
    fi

    local editor
    for editor in "${BU_TERMINAL_EDITOR_PREFERENCE[@]}"
    do
        if command -v "$editor" &>/dev/null
        then
            BU_DEFAULT_EDITOR=$editor
            BU_DEFAULT_TERMINAL_EDITOR=$editor
        fi
    done

    for editor in "${BU_VISUAL_EDITOR_PREFERENCE[@]}"
    do
        if command -v "$editor" &>/dev/null
        then
            BU_DEFAULT_EDITOR=$editor
        fi
    done

    if [[ -d "$HOME"/.vscode-server ]]
    then
        # For server/container environments
        __bu_init_remote_vscode
    else
        export VISUAL=$BU_DEFAULT_EDITOR
        export EDITOR=$BU_DEFAULT_EDITOR
    fi
}
    

# Technically, WSL code setup isn't needed,
# for e.g. the code CLI at /mnt/c/Users/<user>/AppData/Local/Programs/Microsoft VS Code/bin/code
# when entering wsl.
# Though note that the code CLI binary in /mnt/c and 
# the vscode server code CLI binary in ~/.vscode-server
# are 2 different binaries, though with similar options.
__bu_init_remote_vscode()
{
    # Check if this is a vscode server environment
    if [[ ! -d "$HOME"/.vscode-server ]]
    then
        return
    fi

    if [[ -n "${VSCODE_IPC_HOOK_CLI:-}" && -n "${VSCODE_GIT_ASKPASS_NODE:-}" ]]
    then
        # This is the "real" VSCode integrated terminal
        bu_log_info setting vscode links
        ln -sf "$VSCODE_IPC_HOOK_CLI" "$BU_OUT_DIR"/VSCODE_IPC_HOOK_CLI.sock
        ln -sf "$(realpath -- "$(dirname -- "$VSCODE_GIT_ASKPASS_NODE")"/..)" "$BU_OUT_DIR"/vscode_server_instance
    else
        # This is an external terminal
        if [[ -n "${VSCODE_IPC_HOOK_CLI:-}" ]]
        then
            # VSCODE_IPC_HOOK_CLI was already set, e.g. in a parent process
            bu_log_info "code cli already initialized, to force VSCode CLI setup again, run ${BU_TPUT_BOLD}unset -v VSCODE_IPC_HOOK_CLI${BU_TPUT_RESET}" 
            return
        fi
        if  [[ ! ( -e "$BU_OUT_DIR"/VSCODE_IPC_HOOK_CLI.sock && -d "$BU_OUT_DIR"/vscode_server_instance ) ]]
        then
            local latest_server=$(bu_vscode_find_latest_server)
            local latest_socket=$(bu_vscode_find_latest_socket)
            if [[ -n "$latest_server" && -n "$latest_socket" ]]
            then
                ln -sf "$latest_socket" "$BU_OUT_DIR"/VSCODE_IPC_HOOK_CLI.sock
                ln -sf "$latest_server" "$BU_OUT_DIR"/vscode_server_instance
            else
                bu_log_info vscode server not found
                unset VSCODE_IPC_HOOK_CLI
                if [[ "${VISUAL:-}" == code* || "${EDITOR:-}" == code* ]]
                then
                    export VISUAL=
                    export EDITOR=$default_editor
                fi
                return
            fi
        fi
        export VSCODE_IPC_HOOK_CLI="$BU_OUT_DIR"/VSCODE_IPC_HOOK_CLI.sock
        if [[ -e "$BU_OUT_DIR"/vscode_server_instance/server/bin/remote-cli ]]
        then
            # Remote SSH
            bu_env_append_path "$BU_OUT_DIR"/vscode_server_instance/server/bin/remote-cli
        elif [[ -e "$BU_OUT_DIR"/vscode_server_instance/bin/remote-cli ]]
        then
            # WSL
            bu_env_prepend_path "$BU_OUT_DIR"/vscode_server_instance/bin/remote-cli
        else
            bu_log_err Cannot find code binary
            return 1
        fi
        if [[ -z "$VISUAL" || -z "$EDITOR" ]]
        then
            if bu_vscode_is_socket_inactive
            then
                rm -f "$BU_OUT_DIR"/VSCODE_IPC_HOOK_CLI.sock "$BU_OUT_DIR"/vscode_server_instance
                export VISUAL=
                export EDITOR=$default_editor
                bu_log_warn code server is not running
            else
                export VISUAL=$BU_LIB_BIN_DIR/bu_code_wait.sh
                export EDITOR=$VISUAL
                bu_log_info code cli initialized
            fi
        fi

        # Do we need this?
        # bu_ext_source "$(code --locate-shell-integration-path bash)"
    fi
}

__bu_init_tmux()
{
    if ! bu_env_is_in_tmux
    then
        return
    fi

    bu_log_debug Setting window status
    tmux set-option window-status-format '#I:#{?@bu_use_window_name,#{window_name},#{b:pane_current_path}}#F'
    tmux set-option window-status-current-format '#I:#{?@bu_use_window_name,#{window_name},#{b:pane_current_path}}#F'
}

__bu_init_autocomplete()
{
    # Keep NAME@VALUE together for programmable completion (like bash-completion).
    shopt -u hostcomplete
    local completion_command
    for completion_command in "${!BU_AUTOCOMPLETE_COMPLETION_FUNCS[@]}"
    do
        local completion_func=${BU_AUTOCOMPLETE_COMPLETION_FUNCS[$completion_command]}
        bu_log_debug "Completing command[$completion_command] with completion_func[$completion_func]"
        complete -F "$completion_func" "$completion_command"
    done

    local command
    local function_or_script_path
    local function_or_script_basename
    for command in "${!BU_COMMANDS[@]}"
    do
        function_or_script_path=${BU_COMMANDS[$command]}
        bu_basename "$function_or_script_path"
        function_or_script_basename=$BU_RET
        # If it is a function, or if the script can be found on PATH, then define completion for it.
        if command -v "$function_or_script_basename" &>/dev/null
        then
            complete -F __bu_autocomplete_completion_func_script "$function_or_script_basename"
        fi
    done

    complete -F __bu_autocomplete_completion_func_source source
    complete -F __bu_autocomplete_completion_func_source .
    complete -F __bu_autocomplete_completion_func_default -D
}

bu_init()
{
    __bu_init_env
    __bu_init_keybindings
    __bu_init_editor
    __bu_init_tmux
    __bu_init_autocomplete
    __bu_expose
}

bu_init
