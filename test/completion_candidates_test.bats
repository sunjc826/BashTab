#!/usr/bin/env -S bats --jobs 8

# Tests for bu_get_completion_candidates: the Tab candidates for a command
# line held as text, printed between sentinel lines, with no readline, fzf or
# terminal.

setup() {
    load "test_helper/bats-assert/load.bash"
    load "test_helper/bats-support/load.bash"

    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    # shellcheck source=../bu_entrypoint.sh
    source "$DIR"/../bu_entrypoint.sh

    # shellcheck source=./test_helper/bu_bats_decl.sh
    source "$BU_NULL"
}

# Run bu_get_completion_candidates with stdout in `$out` (stderr dropped)
# and its exit code in `$rc`
__candidates() {
    rc=0
    out=$(bu_get_completion_candidates "$@" 2>/dev/null) || rc=$?
}

function test_completion_candidates_command_prefix { #@test
    local out rc
    __candidates bu get-
    assert_equal "$rc" 0
    assert_equal "${out%%$'\n'*}" '==BEGIN AUTOCOMPLETE=='
    assert_equal "${out##*$'\n'}" '==END AUTOCOMPLETE=='
    local -a first_fields=()
    mapfile -t first_fields < <(printf '%s\n' "$out" | cut -f1)
    assert bu_list_exists_str get-command "${first_fields[@]}"
}

function test_completion_candidates_empty_last_word_lists_options { #@test
    local out rc
    __candidates bu get-command ""
    assert_equal "$rc" 0
    assert_regex "$out" $'(^|\n)--verb(\t|\n)'
}

function test_completion_candidates_option_metadata { #@test
    local out rc
    __candidates bu get-command ""
    assert_regex "$out" $'(^|\n)-[^\t\n]*\t[^\n]+'
}

function test_completion_candidates_none { #@test
    local out rc
    __candidates bu get-zzqq-no-such-command
    assert_equal "$rc" 2
    assert_equal "$out" $'==BEGIN AUTOCOMPLETE==\n==END AUTOCOMPLETE=='
}

function test_completion_candidates_no_ansi { #@test
    # Colours are set up from TERM when the framework loads (none with
    # TERM=dumb), so load it with a colour TERM, and check that the engine
    # does colour command names, subcommands and options before they are
    # stripped
    run env TERM=xterm-256color bash -c '
        source "$1"/../bu_entrypoint.sh >/dev/null 2>&1
        command_line=(bu get-command "")
        __bu_autocomplete_tab_collect 2>/dev/null
        [[ "${BU_COMPREPLY_METADATA[*]}" == *$'"'\e['"'* ]] || { echo "engine uncoloured"; exit 3; }
        for line in "b" "bu get-" "bu get-command "; do
            words=($line)
            [[ "$line" == *" " ]] && words+=("")
            bu_get_completion_candidates "${words[@]}" 2>/dev/null
        done
        exit 0
    ' _ "$DIR"
    assert_success
    assert_output --partial '==END AUTOCOMPLETE=='
    [[ "$output" != *$'\e['* ]] || fail "ESC [ in the output"
}

function test_completion_candidates_command_names { #@test
    local out rc
    __candidates b
    assert_equal "$rc" 0
    local -a first_fields=()
    mapfile -t first_fields < <(printf '%s\n' "$out" | cut -f1)
    assert bu_list_exists_str bu "${first_fields[@]}"
}

function test_completion_candidates_nounset_errexit_caller { #@test
    # The caller's options neither break the engine nor change: the "none"
    # case under errexit is the caller's to handle
    run bash -c '
        set -eu -o pipefail
        source "$1"/../bu_entrypoint.sh >/dev/null 2>&1
        set -eu -o pipefail
        bu_get_completion_candidates bu get-command "" >/dev/null 2>&1
        rc=0
        bu_get_completion_candidates bu get-zzqq >/dev/null 2>&1 || rc=$?
        [[ $- == *e* && $- == *u* && -o pipefail ]] || exit 3
        echo "ok $rc"
    ' _ "$DIR"
    assert_output 'ok 2'
}
