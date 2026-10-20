#!/usr/bin/env bats

# Tests for __bu_bind_x_run (lib/core/bu_core_init.sh): the dispatcher every
# `bind -x` BashTab installs goes through on bash < 5.2.
#
# Background: before bash 5.2, `bind -x` handlers run with readline's raw
# termios still applied, and an interactive bash snapshots the tty after
# every foreground job that exits normally, except during programmable
# completion. A plain external command inside a handler thus stores
# `-echo -icanon` as the shell's cooked state; the next foreground job killed
# by a signal (Ctrl-C, SIGPIPE from a pager quit early) makes bash re-apply
# it and readline stops echoing. bash 5.2 skips the snapshot while
# dispatching a key binding, so BashTab binds handlers directly there
# (BU_BIND_X_NEEDS_TTY_GUARD=false) and the mechanism-lock test skips.
#
# All tests drive a real interactive `bash --norc` (the first `bash` on PATH)
# inside a detached tmux server, the way the tv job-control tests do. The tty
# state is read by typing `stty -a > file` into that shell: an idle prompt
# always shows -echo because readline has the terminal prepped, so the probe
# must run as a foreground command, not be taken at the prompt.

setup() {
    load "test_helper/bats-assert/load.bash"
    load "test_helper/bats-support/load.bash"

    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    command -v tmux >/dev/null || skip "tmux not available"
}

# ```md
# Poll until a file exists and is non-empty, or tries run out.
#
# Params:
# - $1: path
# - $2: max tries at 0.5s each (default 20)
# ```
function __bx_wait_file {
    local -i _w
    for (( _w = 0; _w < ${2:-20}; _w++ )); do
        [[ -s "$1" ]] && return 0
        sleep 0.5
    done
    return 1
}

# ```md
# Poll a tmux pane until its capture matches a pattern, or tries run out.
#
# Params:
# - $1: tmux socket
# - $2: target pane
# - $3: grep -E pattern to wait for
# - $4: max tries at 0.5s each (default 20)
#
# Returns:
# - pane: last captured frame (caller's local, via dynamic scope)
# ```
function __bx_wait_pane {
    local -i _w
    for (( _w = 0; _w < ${4:-20}; _w++ )); do
        pane=$(tmux -L "$1" capture-pane -t "$2" -p)
        grep -qE "$3" <<<"$pane" && return 0
        sleep 0.5
    done
    return 0
}

# ```md
# Start a detached tmux session running `bash --norc` with BashTab activated.
#
# Params:
# - $1: tmux socket
# - $2: session name
# ```
function __bx_tmux_setup {
    local pane
    tmux -L "$1" new-session -d -s "$2" -x 120 -y 30 "bash --norc"
    tmux -L "$1" send-keys -t "$2" "source \"$DIR\"/../activate >/dev/null 2>&1; echo bx-ready" Enter
    # Activation time varies wildly across hosts: wait (up to 60s).
    __bx_wait_pane "$1" "$2" '^bx-ready' 120
}

# ```md
# Arm the trap (press the bound key), spring it (Ctrl-C a foreground sleep),
# then record the cooked tty state from inside the shell.
#
# Params:
# - $1: tmux socket
# - $2: session name
# - $3: output file for `stty -a`
# ```
function __bx_press_interrupt_probe {
    tmux -L "$1" send-keys -t "$2" C-t
    sleep 0.5
    tmux -L "$1" send-keys -t "$2" "sleep 30" Enter
    sleep 0.8
    tmux -L "$1" send-keys -t "$2" C-c
    sleep 0.5
    tmux -L "$1" send-keys -t "$2" "stty -a > \"$3\"" Enter
    __bx_wait_file "$3"
}

# ```md
# Reduce `stty -a` output to the two flags that matter, e.g. "echo icanon ".
# Flags are separated by spaces, settings such as `rows 30` by semicolons.
#
# Params:
# - $1: stty -a output file
# ```
function __bx_flags {
    tr ' ;' '\n\n' < "$1" | grep -E '^-?(echo|icanon)$' | sort | tr '\n' ' '
}

function test_bind_x_run_keeps_echo_after_signalled_job { #@test
    # The dispatcher works on every bash, so this runs everywhere.
    local sock=bx$$a out=$BATS_TEST_TMPDIR/stty.txt pane
    __bx_tmux_setup "$sock" bxrun
    tmux -L "$sock" send-keys -t bxrun "bind -x '\"\\C-t\": __bu_bind_x_run /bin/true'" Enter
    sleep 0.5
    __bx_press_interrupt_probe "$sock" bxrun "$out" || { tmux -L "$sock" kill-server; fail "no stty output"; }
    local flags
    flags=$(__bx_flags "$out")
    # Readline must still draw the command line afterwards: the typed command
    # itself (not just its output line) has to be on screen, whatever the
    # prompt looks like.
    tmux -L "$sock" send-keys -t bxrun "echo bx-visible-marker" Enter
    __bx_wait_pane "$sock" bxrun '^bx-visible-marker$'
    tmux -L "$sock" kill-server
    assert_equal "$flags" "echo icanon "
    assert_regex "$pane" 'echo bx-visible-marker'
}

function test_bind_x_raw_binding_loses_echo_mechanism_lock { #@test
    # Control that documents the shell mechanism the dispatcher exists for.
    # bash 5.2+ does not exhibit it; skip there instead of failing.
    local sock=bx$$b out=$BATS_TEST_TMPDIR/stty.txt
    __bx_tmux_setup "$sock" bxraw
    tmux -L "$sock" send-keys -t bxraw "bind -x '\"\\C-t\": /bin/true'" Enter
    sleep 0.5
    __bx_press_interrupt_probe "$sock" bxraw "$out" || { tmux -L "$sock" kill-server; fail "no stty output"; }
    local flags
    flags=$(__bx_flags "$out")
    tmux -L "$sock" kill-server
    if [[ "$flags" == "echo icanon " ]]; then
        skip "this bash does not snapshot the tty inside bind -x handlers; the dispatcher is not needed here"
    fi
    assert_equal "$flags" "-echo -icanon "
}

function test_bind_x_bindings_follow_version_gate { #@test
    # bash < 5.2: Tab and every BU_KEY_BINDINGS entry go through the
    # dispatcher. bash 5.2+: the original direct bindings, untouched.
    local sock=bx$$c out=$BATS_TEST_TMPDIR/bindX.txt guard=$BATS_TEST_TMPDIR/guard.txt
    __bx_tmux_setup "$sock" bxlist
    tmux -L "$sock" send-keys -t bxlist "bu_autocomplete_enable_tab >/dev/null 2>&1; echo \"\$BU_BIND_X_NEEDS_TTY_GUARD\" > \"$guard\"; bind -X > \"$out\"" Enter
    __bx_wait_file "$out" || { tmux -L "$sock" kill-server; fail "no bind -X output"; }
    __bx_wait_file "$guard" || { tmux -L "$sock" kill-server; fail "no guard output"; }
    tmux -L "$sock" kill-server
    local line expected
    expected=false
    if (( BASH_VERSINFO[0] < 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] < 2) )); then
        expected=true
    fi
    assert_equal "$(< "$guard")" "$expected"
    if [[ "$expected" == true ]]; then
        grep -q '"\\C-i": "__bu_bind_x_run __bu_bind_fzf_tab_autocomplete"' "$out"
        grep -q '__bu_bind_x_run __bu_bind_edit' "$out"
        while IFS= read -r line; do
            [[ "$line" == *__bu_bind_x_run* ]] || fail "binding not dispatched: $line"
        done < "$out"
    else
        grep -q '"\\C-i": "__bu_bind_fzf_tab_autocomplete"' "$out"
        grep -q '__bu_bind_edit' "$out"
        if grep -q __bu_bind_x_run "$out"; then
            fail "bash $BASH_VERSION should bind directly: $(< "$out")"
        fi
    fi
}

function test_bind_x_forced_guard_dispatches_and_quotes_bindings { #@test
    # Force the bash < 5.2 wiring on any bash: a multi-word binding value must
    # survive `bind -x` reparsing as one word and still run when pressed.
    local sock=bx$$e out=$BATS_TEST_TMPDIR/bindX.txt ran=$BATS_TEST_TMPDIR/ran.txt
    __bx_tmux_setup "$sock" bxforce
    tmux -L "$sock" send-keys -t bxforce "BU_BIND_X_NEEDS_TTY_GUARD=true; BU_KEY_BINDINGS['\\C-t']='printf \"%s\\n\" bx-one \"bx two\" > \"$ran\"'; __bu_init_keybindings >/dev/null 2>&1; bu_autocomplete_enable_tab >/dev/null 2>&1; bind -X > \"$out\"" Enter
    __bx_wait_file "$out" || { tmux -L "$sock" kill-server; fail "no bind -X output"; }
    tmux -L "$sock" send-keys -t bxforce C-t
    __bx_wait_file "$ran" || { tmux -L "$sock" kill-server; fail "multi-word binding did not run"; }
    tmux -L "$sock" kill-server
    local line
    grep -q '"\\C-i": "__bu_bind_x_run __bu_bind_fzf_tab_autocomplete"' "$out"
    while IFS= read -r line; do
        [[ "$line" == *__bu_bind_x_run* ]] || fail "binding not dispatched: $line"
    done < "$out"
    assert_equal "$(< "$ran")" $'bx-one\nbx two'
}

function test_bind_x_tab_completion_then_interrupt_keeps_echo { #@test
    command -v fzf >/dev/null || skip "fzf not available"
    local sock=bx$$d out=$BATS_TEST_TMPDIR/stty.txt pane
    __bx_tmux_setup "$sock" bxtab
    tmux -L "$sock" send-keys -t bxtab "bu_autocomplete_enable_tab >/dev/null 2>&1" Enter
    sleep 0.5
    tmux -L "$sock" send-keys -t bxtab "bu get-ver" Tab
    __bx_wait_pane "$sock" bxtab 'get-version' 20
    tmux -L "$sock" send-keys -t bxtab Enter    # accept the fzf selection
    sleep 1
    tmux -L "$sock" send-keys -t bxtab C-u
    tmux -L "$sock" send-keys -t bxtab "sleep 30" Enter
    sleep 0.8
    tmux -L "$sock" send-keys -t bxtab C-c
    sleep 0.5
    tmux -L "$sock" send-keys -t bxtab "stty -a > \"$out\"" Enter
    __bx_wait_file "$out" || { tmux -L "$sock" kill-server; fail "no stty output"; }
    local flags
    flags=$(__bx_flags "$out")
    tmux -L "$sock" kill-server
    assert_equal "$flags" "echo icanon "
}
