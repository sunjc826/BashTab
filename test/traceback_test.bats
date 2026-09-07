#!/usr/bin/env -S bats --jobs 16

# Unit tests for the exit-handler traceback rendering in lib/core/bu_core_base.sh:
# the short (single-line) and full (source-context) display styles selected by
# BU_STACKTRACE_STYLE. Rendering helpers are exercised directly with controlled
# inputs (no reliance on bash's frame arrays), plus one end-to-end test proving
# the exit handler dispatches to the selected style.

setup() {
    load "test_helper/bats-assert/load.bash"
    load "test_helper/bats-support/load.bash"

    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"

    # A fixture source file with stable, known line numbers.
    cat > "$BATS_TEST_TMPDIR/fixture.sh" <<'EOF'
line one
line two
line three
line four
line five
EOF
    FIXTURE="$BATS_TEST_TMPDIR/fixture.sh"
}

# Load the full entrypoint in a clean shell (TERM=dumb degrades all tput codes
# to empty so assertions see plain text), then invoke the private traceback
# printer with controlled inputs.
# Args: style idx what file line
function run_traceback_frame {
    run bash -c '
        export TERM=dumb
        export BU_OUT_DIR=$(mktemp -d)
        source "$1"/bu_entrypoint.sh >/dev/null 2>&1
        __bu_traceback_print_frame "$2" "$3" "$4" "$5" "$6"
    ' _ "$DIR/.." "$@"
}

function test_traceback_short_single_line { #@test
    run_traceback_frame short 3 myfunc /some/path/script.sh 42
    assert_success
    assert_output "    3: myfunc at script.sh:42"
}

function test_traceback_short_uses_basename_only { #@test
    run_traceback_frame short 1 outer /a/b/c/deep.sh 7
    assert_success
    assert_output "    1: outer at deep.sh:7"
}

function test_traceback_full_source_context { #@test
    run_traceback_frame full 0 myfunc "$FIXTURE" 3
    assert_success
    assert_line --index 0 "  File \"$FIXTURE\", line 3, in myfunc"
    assert_output --partial "1 │ line one"
    assert_output --partial "2 │ line two"
    assert_output --partial ">     3 │ line three"
    assert_output --partial "4 │ line four"
    assert_output --partial "5 │ line five"
}

function test_traceback_full_empty_func_uses_module { #@test
    run_traceback_frame full 0 "" "$FIXTURE" 3
    assert_success
    assert_line --index 0 "  File \"$FIXTURE\", line 3, in <module>"
}

function test_traceback_full_missing_file_fallback { #@test
    local missing="$BATS_TEST_TMPDIR/nonexistent.sh"
    run_traceback_frame full 0 myfunc "$missing" 3
    assert_success
    assert_line --index 0 "  File \"$missing\", line 3, in myfunc"
    assert_output --partial "<source unavailable>"
}

function test_traceback_full_context_clamps_before_first_line { #@test
    # Fault on line 1: no negative start; window begins at line 1.
    run_traceback_frame full 0 myfunc "$FIXTURE" 1
    assert_success
    assert_output --partial ">     1 │ line one"
    assert_output --partial "2 │ line two"
    assert_output --partial "3 │ line three"
    # line 4/5 are beyond the default 2-line context window for line 1.
    refute_output --partial "4 │ line four"
}

# ===========================================================================
# Syntax highlighting of source lines (the __bu_traceback_highlight helper)
# ===========================================================================

# Run the highlighter with stub color codes so assertions are deterministic.
function run_highlight {
    run bash -c '
        export TERM=dumb
        export BU_OUT_DIR=$(mktemp -d)
        source "$1"/bu_entrypoint.sh >/dev/null 2>&1
        BU_TPUT_VIOLET="<K>"; BU_TPUT_YELLOW="<B>"; BU_TPUT_GREY="<C>"; BU_TPUT_GREEN="<S>"; BU_TPUT_RESET="<R>"
        __bu_traceback_highlight "$2"
    ' _ "$DIR/.." "$1"
}

function test_traceback_highlight_keywords_brackets_comment { #@test
    run_highlight 'if (x) { y; } # note'
    assert_success
    assert_output '<K>if<R> <B>(<R>x<B>)<R> <B>{<R> y; <B>}<R> <C># note<R>'
}

function test_traceback_highlight_hash_inside_string_is_not_comment { #@test
    run_highlight 'echo "a # b"'
    assert_success
    assert_output 'echo <S>"a # b"<R>'
}

function test_traceback_highlight_unterminated_string { #@test
    run_highlight "echo 'unterminated"
    assert_success
    assert_output "echo <S>'unterminated<R>"
}

function test_traceback_highlight_passthrough_without_colors { #@test
    run bash -c '
        export TERM=dumb
        export BU_OUT_DIR=$(mktemp -d)
        source "$1"/bu_entrypoint.sh >/dev/null 2>&1
        __bu_traceback_highlight "if (x) { y; } # note"
    ' _ "$DIR/.."
    assert_success
    assert_output 'if (x) { y; } # note'
}

function test_traceback_full_applies_highlighting { #@test
    local fixture="$BATS_TEST_TMPDIR/hl.sh"
    cat > "$fixture" <<'EOF'
echo start
if (x) { y; }
echo end
EOF
    run bash -c '
        export TERM=dumb
        export BU_OUT_DIR=$(mktemp -d)
        source "$1"/bu_entrypoint.sh >/dev/null 2>&1
        BU_TPUT_VIOLET="<K>"; BU_TPUT_YELLOW="<B>"; BU_TPUT_GREY="<C>"; BU_TPUT_GREEN="<S>"; BU_TPUT_RESET="<R>"
        __bu_traceback_print_frame_full myfunc "$2" 2
    ' _ "$DIR/.." "$fixture"
    assert_success
    assert_output --partial '<K>if<R>'
    assert_output --partial '<B>(<R>x<B>)<R>'
    assert_output --partial '<B>{<R> y; <B>}<R>'
}

# End-to-end: the exit handler must dispatch to the selected style.
function test_exit_handler_full_style_end_to_end { #@test
    local script="$BATS_TEST_TMPDIR/e2e.sh"
    cat > "$script" <<'EOF'
export TERM=dumb
export BU_OUT_DIR=$(mktemp -d)
source "$1"/bu_entrypoint.sh >/dev/null 2>&1
BU_STACKTRACE_STYLE=full
bu_exit_handler_setup
failing_func() { false; }
failing_func
EOF
    run bash "$script" "$DIR/.."
    assert_failure
    assert_output --partial "Traceback (most recent call last):"
    assert_output --partial "File \"$script\", line "
    assert_output --partial "> "
}

function test_exit_handler_default_short_end_to_end { #@test
    local script="$BATS_TEST_TMPDIR/e2e_short.sh"
    cat > "$script" <<'EOF'
export TERM=dumb
export BU_OUT_DIR=$(mktemp -d)
source "$1"/bu_entrypoint.sh >/dev/null 2>&1
bu_exit_handler_setup
failing_func() { false; }
failing_func
EOF
    run bash "$script" "$DIR/.."
    assert_failure
    assert_output --partial "Traceback (most recent call last):"
    # Short style: one compact line per frame; no Python-style "File" header.
    assert_output --partial "at e2e_short.sh:"
    refute_output --partial "  File \""
}
