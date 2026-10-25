# bash-ide source=./bu_core_base.sh

# Internal function to resolve tmux split mode into tmux command arguments
#
# @arg $1 {string} split_mode Split mode (one of `none`, `vertical`, `horizontal`)
# @set BU_RET[@] Array containing the tmux command with arguments to create a new pane/window
#
# @returns
# - Exit code 0 on success, 1 if split mode is invalid
#
# @notes
# - `none` creates a new window in a new tmux session
# - `vertical` splits the current pane vertically
# - `horizontal` splits the current pane horizontally
# - Returns pane ID using stable format `#{pane_id}` instead of window index
#
# @example
# ```bash
# __bu_spawn_tmux_resolve_split_mode vertical
# # $BU_RET contains: (tmux split-window -vd -t $TMUX_PANE -P -F '#{pane_id}' bash --init-file)
# ```
# bash-ide parse-func-sig
__bu_spawn_tmux_resolve_split_mode()
{
    local split_mode=$1
    local -a tmux_args
    case "$split_mode" in
    none)
        tmux_args=(new-window -d)
        ;;
    vertical)
        tmux_args=(split-window -vd -t "$TMUX_PANE")
        ;;
    horizontal)
        tmux_args=(split-window -hd -t "$TMUX_PANE")
        ;;
    *)
        bu_log_err "Bad split mode[$split_mode]"
        return 1
        ;;
    esac
    # Default format: #{session_name}:#{window_index}
    # But window index is not stable, so we should a custom stable format #{pane_id}
    tmux_args+=(-P -F '#{pane_id}')

    BU_RET=(tmux "${tmux_args[@]}" bash --init-file)
}

# Stops the commands running in the given tmux panes
#
# @arg $@ {string} args... Tmux pane ids
bu_spawn_tmux_stop_commands()
{
    # q: To exit tmux scroll mode
    # C-c: Kills most non-interactive applications, for interactive applications, neutralizes the q
    # C-d: EOF, kills most interactive applications. We don't want to always enable this because it can kill the bash shell itself.
    # Note that the keys need to be delivered one at a time, I find that
    # tmux send-keys q C-c C-d does not work
    # Not sure why. Does the kernel line discipline need some delay in between key presses for
    # them to each take effect?
    local keys=(q C-c)
    case "$1" in
    --repl)
        keys+=(C-d)
        shift
        ;;
    esac
    local pane key
    for pane
    do
        for key in "${keys[@]}"
        do
            tmux send-keys -t "$pane" "$key"
        done
    done
}

# Waits for the commands associated with the ret file fds to finish, and checks their exit codes
#
# @arg $@ {string} args... ret file fds
#
# @returns
# - Exit code:
#   - 0: all commands returned 0
#   - Non-zero: The exit code of the last command that returned a non-zero exit code
# bash-ide parse-func-sig
bu_spawn_tmux_join_commands()
{
    bu_log_info "Joining fds[$*]"
    local fd
    local exit_code=0
    local command_exit_code
    for fd
    do
        if ! bu_sync_acquire_fd "$fd"
        then
            bu_log_err 'bu_sync_acquire_fd failed'
            return 1
        fi
        bu_log_debug "Reading from fd[$fd]"
        if ! read -r command_exit_code <&"$fd"
        then
            bu_log_err "Read from fd[$fd] failed"
            return 1
        fi
        if ! bu_sync_release_fd "$fd"
        then
            bu_log_err 'bu_sync_release_fd failed'
            return 1
        fi
        if ((command_exit_code))
        then
            exit_code=$command_exit_code
        fi
    done
    return "$exit_code"
}

# *Description*:
# Combines `bu_spawn_tmux_stop_commands` and `bu_spawn_tmux_join_commands`. Stops the given panes, and joins the ret files.
#
# *Params*:
# - `$1`, `$3`, all odd indices: Pane ids
# - `$2`, `$4`, all even indices: Ret file fds
#
# *Returns*:
# - Exit code:
#   - 0: all commands returned 0
#   - Non-zero: The exit code of the last command that returned a non-zero exit code
bu_spawn_tmux_stop_join_commands()
{
    local stop_options=()
    case "$1" in
    --repl) stop_options+=("$1"); shift;;
    esac
    if (($# / 2 * 2 != $#))
    then
        bu_log_err 'There should be an even number of arguments'
        return 1
    fi

    local to_stop=()
    local to_join=()
    while (($#))
    do
        to_stop+=("$1")
        to_join+=("$2")
        shift 2
    done
    bu_spawn_tmux_stop_commands "${stop_options[@]}" "${to_stop[@]}"
    bu_spawn_tmux_join_commands "${to_join[@]}"
}

BU_TMUX_PANES_FILE=$BU_PROC_TMP_DIR/tmux_panes.txt
# bash-ide parse-func-sig
bu_spawn_init()
{
    if ! bu_env_is_in_tmux
    then
        bu_log_err 'Not in tmux'
        return 1
    fi
    : >"$BU_TMUX_PANES_FILE"
}

bu_spawn()
{
    if ! bu_env_is_in_tmux
    then
        bu_log_err 'Not in tmux'
        return 1
    fi
    local split_mode=none
    local is_split_opposite=false
    local is_joinable=false
    local is_scoped=false
    local is_delete_pane=false # TODO
    local is_wait=false
    local is_function=
    local is_source_bashrc=true
    local is_repl=false
    local shift_by
    while (($#))
    do
        shift_by=1
        case "$1" in
        --split|--split-opposite)
            shift_by=2
            split_mode=$2
            case "$split_mode" in
            ''|n|none|new-window) split_mode=none ;;
            v|vert|vertical|split-vertical) split_mode=vertical ;;
            h|hori|horizontal|split-horizontal) split_mode=horizontal ;;
            *) bu_log_err "Unexpected split mode[$split_mode]"; return 1 ;;
            esac
            if [[ "$1" = --split-opposite ]]
            then
                is_split_opposite=true
            fi
            ;;
        --joinable)
            is_joinable=true
            ;;
        --scoped)
            is_scoped=true
            ;;
        --delete-pane)
            is_delete_pane=true
            ;;
        --wait)
            is_joinable=true
            is_wait=true
            ;;
        --command)
            is_function=false
            ;;
        --function)
            is_function=true
            ;;
        --no-bashrc)
            is_source_bashrc=false
            ;;
        --repl)
            is_repl=true
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
    local remaining_options=("$@")
    local command=${remaining_options[0]}

    if "$is_split_opposite"
    then
        case "$split_mode" in
        none) ;;
        vertical) split_mode=horizontal ;;
        horizontal) split_mode=vertical ;;
        esac
    fi

    bu_log_info "Spawning ${remaining_options[*]}"

    if [[ -z "$is_function" ]]
    then
        if [[ -t 0 ]]
        then
            is_function=false
        else
            is_function=true
        fi
    fi

    local stop_options=()
    if "$is_repl"
    then
        stop_options+=(--repl)
    fi

    local exit_code=0

    local pane_id=


    local tmp_file
    tmp_file=$(mktemp "$BU_TMP_DIR"/tmux.XXXXXXXXXX) || return 1
    local fifo_file=$tmp_file.fifo
    local ret_file=$tmp_file.ret
    local ret_file_fd=
    local driver_file=$tmp_file.driver.sh
    if "$is_joinable"
    then
        mkfifo "$fifo_file" || return 1
        : > "$ret_file" || return 1
        exec {ret_file_fd}<"$ret_file" || return 1
    fi

    local random_part
    if "$is_function"
    then
        bu_basename "$tmp_file"
        random_part=${BU_RET#tmux.}
    fi 

    {
        echo 'rm '"$tmp_file"
        # Serialize the environment
        awk '
        BEGIN {
            for( v in ENVIRON ) { 
                if( v !~ /^(TMUX|TERM|BASH)(_.*|$)/ ) 
                    printf "export %s=\"%s\"\n", v, ENVIRON[v] 
            }
        }
        '
        if [[ -n "$command" ]] && bu_symbol_is_function "$command"
        then
            printf "%s\n" "$(declare -f "$command")"
        fi
        echo . /etc/profile
        if "$is_source_bashrc"
        then
        echo . "$HOME"/.bashrc
        fi
        echo 'source '"$BU_DIR"/bu_entrypoint.sh
        if "$is_joinable"
        then
        # echo 1 first to account for possible Ctrl-C
        echo 'echo 1 >'"$ret_file"
        echo 'exec {RET_FILE_FD}>'"$ret_file"
        echo 'rm '"$ret_file"
        echo 'bu_exit_handler_setup_no_e'
        echo 'bu_scope_push'
        # shellcheck disable=SC2016
        echo 'bu_sync_acquire_fd "$RET_FILE_FD"'
        # shellcheck disable=SC2016
        echo 'bu_scope_add_cleanup bu_release_fd "$RET_FILE_FD"'
        echo 'echo >'"$fifo_file"
        fi

        if "$is_function"
        then
        echo 'function func_'"$random_part"'() {'
        cat /dev/stdin
        echo '}'
        echo 'func_'"$random_part"
        else
        printf '%q ' "${remaining_options[@]}"
        fi

        echo
        if "$is_joinable"
        then
        # shellcheck disable=SC2016
        echo 'echo $? >&"$RET_FILE_FD"'
        echo 'bu_scope_pop'
        fi
    } > "$tmp_file"

    if ! "$is_joinable"
    then
        __bu_spawn_tmux_resolve_split_mode "$split_mode" || return 1
        pane_id=$("${BU_RET[@]}" "$tmp_file")
    else
        {
            echo 'rm '"$driver_file"
            echo . /etc/profile
            if "$is_source_bashrc"
            then
            echo . "$HOME"/.bashrc
            fi
            echo bash "$tmp_file"
        } > "$driver_file"

        bu_log_cmd_info cat "$tmp_file"
        __bu_spawn_tmux_resolve_split_mode "$split_mode" || return 1
        pane_id=$("${BU_RET[@]}" "$driver_file")
        local discarded
        # shellcheck disable=SC2034
        read -r discarded <"$fifo_file"
        rm -f "$fifo_file"
    fi

    if ! "$is_joinable"
    then
        if "$is_scoped"
        then
            bu_scope_add_cleanup bu_spawn_tmux_stop_commands "${stop_options[@]}" "$pane_id"
        fi
    else
        if "$is_wait" && "$is_scoped"
        then
            bu_scope_add_cleanup bu_spawn_tmux_join_commands "$ret_file_fd"
        elif "$is_wait"
        then
            if ! bu_spawn_tmux_join_commands "$ret_file_fd"
            then
                exit_code=1
            fi
        elif "$is_scoped"
        then
            bu_scope_add_cleanup bu_spawn_tmux_stop_join_commands "${stop_options[@]}" "$pane_id" "$ret_file_fd"
        fi
    fi

    bu_sync_acquire_file "$BU_TMUX_PANES_FILE"
    printf '%s\n' "$pane_id" >> "$BU_TMUX_PANES_FILE"
    bu_sync_release_file "$BU_TMUX_PANES_FILE"
    bu_log_debug "exit_code[$exit_code]"

    if "$is_joinable"
    then
        BU_RET=("$pane_id" "$ret_file_fd")
    else
        BU_RET=("$pane_id")
    fi

    return "$exit_code"    
}

