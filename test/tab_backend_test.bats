#!/usr/bin/env bats

# Tests for the Tab backends other than the positioned fzf dropdown
# (BU_AUTOCOMPLETE_TAB_BACKEND, lib/core/bu_core_autocomplete.sh):
# - fzf-cheap: the fzf dropdown on the prompt row, no terminal queries
# - readline:  readline's own completion, fed by a prepare handler that
#              stashes the candidates (with descriptions) and swaps the
#              command's compspec for one `complete`
#
# The helpers are tested in this shell; the backends drive a real interactive
# `bash --norc` inside a detached tmux server, as bind_x_test.bats does.

setup() {
    load "test_helper/bats-assert/load.bash"
    load "test_helper/bats-support/load.bash"

    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    source "$DIR"/../bu_entrypoint.sh
    source "$BU_NULL"
    TB_SOCK=
}

teardown() {
    # A failed assertion ends the test before its own kill-server
    if [[ -n "$TB_SOCK" ]]; then
        tmux -L "$TB_SOCK" kill-server 2>/dev/null || true
    fi
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
# - Exit code: 0 when the pattern showed up
# ```
function __tb_wait_pane {
    local -i _w
    for (( _w = 0; _w < ${4:-20}; _w++ )); do
        pane=$(tmux -L "$1" capture-pane -t "$2" -p)
        grep -qE -e "$3" <<<"$pane" && return 0
        sleep 0.5
    done
    return 1
}

# ```md
# Start a detached tmux session running `bash --norc` with BashTab activated
# and Tab bound to the given backend.
#
# Params:
# - $1: tmux socket
# - $2: session name
# - $3: Tab backend
# ```
function __tb_tmux_setup {
    local pane
    command -v tmux >/dev/null || skip "tmux not available"
    TB_SOCK=$1
    # fd 3 closed: bats waits for every holder of its output fd to exit
    tmux -L "$1" new-session -d -s "$2" -x 120 -y 30 "bash --norc" 3>&-
    tmux -L "$1" send-keys -t "$2" "PS1='tb\$ '; source \"$DIR\"/../activate >/dev/null 2>&1; bu_autocomplete_enable_tab $3 >/dev/null 2>&1; clear; echo tb-ready" Enter
    # Activation time varies wildly across hosts: wait (up to 60s).
    __tb_wait_pane "$1" "$2" '^tb-ready' 120 || { tmux -L "$1" kill-server; fail "shell did not start"; }
}

# MARK: ANSI stripping

function test_strip_ansi_arrays_sequences { #@test
    local -a a=(
        $'\e[33mget-alias\e[m\017'
        $'\e(B\e[mplain'
        $'\e]133;A\a'
        $'x\e]8;;http://a\e\\link\e]8;;\e\\y'
        $'\e[1;38;5;174mbold\e[0m'
    )
    __bu_autocomplete_strip_ansi_arrays a
    assert_equal "${#a[@]}" 5
    assert_equal "${a[0]}" get-alias
    assert_equal "${a[1]}" plain
    assert_equal "${a[2]}" ''
    assert_equal "${a[3]}" xlinky
    assert_equal "${a[4]}" bold
}

function test_strip_ansi_arrays_keeps_plain_text { #@test
    # Text that looks like the inside of a sequence is left alone when no ESC
    # precedes it, also at the very start of the first element
    local -a a=('[first' $'\e[1m[x' '(B' ']notosc' '' $'multi\nline' 'last')
    local -a b=(plain words '' x)
    local -a e=()
    __bu_autocomplete_strip_ansi_arrays a b e
    assert_equal "${#a[@]}" 7
    assert_equal "${a[0]}" '[first'
    assert_equal "${a[1]}" '[x'
    assert_equal "${a[2]}" '(B'
    assert_equal "${a[3]}" ']notosc'
    assert_equal "${a[4]}" ''
    assert_equal "${a[5]}" $'multi\nline'
    assert_equal "${a[6]}" last
    assert_equal "${b[*]}" "plain words  x"
    assert_equal "${#b[@]}" 4
    assert_equal "${#e[@]}" 0
}

# MARK: readline descriptions

function test_readline_describe_aligns_and_truncates { #@test
    COLUMNS=60
    COMPREPLY=(get-alias get-all-the-things get-x)
    BU_COMPREPLY_METADATA=("flag alias" "" "a very long description that will not fit in the remaining width of the terminal")
    __bu_autocomplete_readline_describe
    assert_equal "${COMPREPLY[0]}" "get-alias           (flag alias)"
    # No description: left bare
    assert_equal "${COMPREPLY[1]}" "get-all-the-things"
    # 60 columns: the string pins it (${#} would count the … as 3 bytes
    # under the C locale bats runs in)
    assert_equal "${COMPREPLY[2]}" "get-x               (a very long description that will not…)"
}

function test_readline_describe_common_prefix_stops_before_padding { #@test
    # Readline inserts the common prefix of the candidates: it must never
    # reach into the padding or the description
    COLUMNS=80
    COMPREPLY=(--format --from)
    BU_COMPREPLY_METADATA=("Output format" "Output format")
    __bu_autocomplete_readline_describe
    local prefix=${COMPREPLY[0]} c
    for c in "${COMPREPLY[@]}"; do
        while [[ "$c" != "$prefix"* ]]; do prefix=${prefix%?}; done
    done
    assert_equal "$prefix" "--f"
}

function test_readline_describe_leaves_single_candidate_bare { #@test
    COMPREPLY=(only)
    BU_COMPREPLY_METADATA=(description)
    __bu_autocomplete_readline_describe
    assert_equal "${COMPREPLY[*]}" only
}

function test_readline_describe_without_descriptions_is_a_no_op { #@test
    COMPREPLY=(a bb ccc)
    BU_COMPREPLY_METADATA=()
    __bu_autocomplete_readline_describe
    assert_equal "${COMPREPLY[*]}" "a bb ccc"
}

function test_readline_describe_narrow_terminal_skips_alignment { #@test
    COLUMNS=20
    COMPREPLY=(a-rather-long-word b)
    BU_COMPREPLY_METADATA=(desc1 desc2)
    __bu_autocomplete_readline_describe
    # 20 - 17 - 4 = no room to align: each description gets what is left
    assert_equal "${COMPREPLY[0]}" "a-rather-long-word"
    assert_equal "${COMPREPLY[1]}" "b  (desc2)"
}

# MARK: readline stash

function _tb_orig_completion { COMPREPLY=(original); }

function test_readline_stash_func_drops_wordbreak_prefix_and_restores_spec { #@test
    complete -F _tb_orig_completion tbcmd
    __BU_AUTOCOMPLETE_RL_SWAPPED_COMMAND=tbcmd
    __BU_AUTOCOMPLETE_RL_SWAPPED_SPEC=$(complete -p tbcmd)
    complete -F __bu_autocomplete_readline_stash_func tbcmd
    __BU_AUTOCOMPLETE_RL_STASH=(--format=json --format=jsonl)
    __BU_AUTOCOMPLETE_RL_STASH_COMPOPT=()
    __BU_AUTOCOMPLETE_RL_STASH_WORD=--format=js
    __BU_AUTOCOMPLETE_RL_STASH_FRONT='echo x | tbcmd --format=js'
    __BU_AUTOCOMPLETE_RL_STASH_IS_SET=true

    # What readline passes: the command after the pipe, and as $2 only the
    # text after the last COMP_WORDBREAKS character
    COMP_LINE='tbcmd --format=js'
    COMP_POINT=${#COMP_LINE}
    run_stash() { __bu_autocomplete_readline_stash_func tbcmd js =; }
    run_stash
    assert_equal "$?" 0
    assert_equal "${COMPREPLY[*]}" "json jsonl"
    assert_equal "$(complete -p tbcmd)" "complete -F _tb_orig_completion tbcmd"
    assert_equal "$__BU_AUTOCOMPLETE_RL_STASH_IS_SET" false
}

function test_readline_stash_func_stale_stash_retries_original { #@test
    complete -F _tb_orig_completion tbcmd
    __BU_AUTOCOMPLETE_RL_SWAPPED_COMMAND=tbcmd
    __BU_AUTOCOMPLETE_RL_SWAPPED_SPEC=$(complete -p tbcmd)
    complete -F __bu_autocomplete_readline_stash_func tbcmd
    __BU_AUTOCOMPLETE_RL_STASH=(stale)
    __BU_AUTOCOMPLETE_RL_STASH_WORD=x
    __BU_AUTOCOMPLETE_RL_STASH_FRONT='tbcmd x'
    __BU_AUTOCOMPLETE_RL_STASH_IS_SET=true

    # Another line than the one the stash was made for: 124 makes bash
    # restart completion with the (restored) original compspec
    COMP_LINE='tbcmd other'
    COMP_POINT=${#COMP_LINE}
    COMPREPLY=()
    local rc=0
    __bu_autocomplete_readline_stash_func tbcmd other tbcmd || rc=$?
    assert_equal "$rc" 124
    assert_equal "${#COMPREPLY[@]}" 0
    assert_equal "$(complete -p tbcmd)" "complete -F _tb_orig_completion tbcmd"
}

function test_readline_restore_spec_removes_spec_the_command_did_not_have { #@test
    complete -r tbnospec 2>/dev/null || true
    __BU_AUTOCOMPLETE_RL_SWAPPED_COMMAND=tbnospec
    __BU_AUTOCOMPLETE_RL_SWAPPED_SPEC=
    complete -F __bu_autocomplete_readline_stash_func tbnospec
    __bu_autocomplete_readline_restore_spec
    run complete -p tbnospec
    assert_failure
    assert_equal "$__BU_AUTOCOMPLETE_RL_SWAPPED_COMMAND" ''
}

# MARK: Interactive

function test_readline_backend_binds_tab_to_the_macro { #@test
    local sock=tb$$a pane out=$BATS_TEST_TMPDIR/bind.txt
    __tb_tmux_setup "$sock" tbbind readline
    tmux -L "$sock" send-keys -t tbbind "{ bind -X; bind -s; echo \"backend=\$BU_AUTOCOMPLETE_ACTIVE_TAB_BACKEND\"; } > \"$out\"" Enter
    __tb_wait_pane "$sock" tbbind 'tb\$ $' 20 || true
    sleep 0.5
    tmux -L "$sock" kill-server
    grep -q '__bu_bind_readline_tab_prepare' "$out" || fail "prepare handler not bound: $(< "$out")"
    grep -qF '"\C-i": "\C-x\C-_t\C-x\C-_c"' "$out" || fail "Tab macro not bound: $(< "$out")"
    grep -q '^backend=readline$' "$out" || fail "backend not recorded: $(< "$out")"
}

function test_readline_backend_completes_single_candidate { #@test
    local sock=tb$$b pane
    __tb_tmux_setup "$sock" tbone readline
    tmux -L "$sock" send-keys -t tbone 'bu get-al' Tab
    local rc=0
    __tb_wait_pane "$sock" tbone 'tb\$ bu get-alias' 20 || rc=$?
    tmux -L "$sock" kill-server
    ((rc == 0)) || fail "not completed: $pane"
}

function test_readline_backend_lists_candidates_with_descriptions { #@test
    local sock=tb$$c pane
    __tb_tmux_setup "$sock" tblist readline
    # First Tab: nothing to insert (common prefix = the word); the second
    # Tab on the same line lists, as readline does
    tmux -L "$sock" send-keys -t tblist 'bu query-object --f' Tab
    sleep 1
    tmux -L "$sock" send-keys -t tblist Tab
    local rc=0
    __tb_wait_pane "$sock" tblist '^--format +\(.*[Oo]utput format' 20 || rc=$?
    tmux -L "$sock" kill-server
    ((rc == 0)) || fail "no described list: $pane"
    # The descriptions are never inserted into the line
    grep -qE 'tb\$ bu query-object --f$' <<<"$pane" || fail "line changed: $pane"
}

function test_readline_backend_leaves_original_compspec_in_place { #@test
    local sock=tb$$d pane out=$BATS_TEST_TMPDIR/spec.txt
    __tb_tmux_setup "$sock" tbspec readline
    tmux -L "$sock" send-keys -t tbspec 'bu get-al' Tab
    __tb_wait_pane "$sock" tbspec 'tb\$ bu get-alias' 20 || true
    tmux -L "$sock" send-keys -t tbspec C-u "complete -p bu > \"$out\"" Enter
    sleep 1
    tmux -L "$sock" kill-server
    assert_equal "$(< "$out")" "complete -F __bu_autocomplete_completion_func_cli bu"
}

function test_fzf_cheap_backend_completes_single_candidate { #@test
    command -v fzf >/dev/null || skip "fzf not available"
    local sock=tb$$e pane
    __tb_tmux_setup "$sock" tbcheap fzf-cheap
    # --select-1: a single match is inserted without opening fzf
    tmux -L "$sock" send-keys -t tbcheap 'bu get-al' Tab
    local rc=0
    __tb_wait_pane "$sock" tbcheap 'tb\$ bu get-alias' 20 || rc=$?
    tmux -L "$sock" kill-server
    ((rc == 0)) || fail "not completed: $pane"
}

function test_fzf_cheap_backend_picks_from_the_dropdown { #@test
    command -v fzf >/dev/null || skip "fzf not available"
    local sock=tb$$f pane
    __tb_tmux_setup "$sock" tbpick fzf-cheap
    tmux -L "$sock" send-keys -t tbpick 'bu query-object --f' Tab
    # The line in front of the word is fzf's prompt; metadata beside each
    # candidate
    __tb_wait_pane "$sock" tbpick '--format +.*[Oo]utput format' 20 || { tmux -L "$sock" kill-server; fail "no dropdown: $pane"; }
    grep -qE '^bu query-object --f' <<<"$pane" || { tmux -L "$sock" kill-server; fail "no prompt: $pane"; }
    tmux -L "$sock" send-keys -t tbpick 'o'
    __tb_wait_pane "$sock" tbpick '1/3' 20 || true
    tmux -L "$sock" send-keys -t tbpick Enter
    local rc=0
    __tb_wait_pane "$sock" tbpick 'tb\$ bu query-object --format' 20 || rc=$?
    tmux -L "$sock" kill-server
    ((rc == 0)) || fail "not inserted: $pane"
}
