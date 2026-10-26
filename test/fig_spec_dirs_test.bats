#!/usr/bin/env -S bats --jobs 8

# Tests for the Fig spec search path: __bu_fig_spec_path looks in the
# colon-separated BU_FIG_SPEC_DIRS, in order, before the bundle
# (BU_FIG_SPEC_DIR, by default fig_specs/build).

setup() {
    load "test_helper/bats-assert/load.bash"
    load "test_helper/bats-support/load.bash"

    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    # shellcheck source=../bu_entrypoint.sh
    source "$DIR"/../bu_entrypoint.sh

    # shellcheck source=./test_helper/bu_bats_decl.sh
    source "$BU_NULL"

    SPEC_ROOT=$(mktemp -d)
    mkdir -p "$SPEC_ROOT"/first "$SPEC_ROOT"/second "$SPEC_ROOT"/bundle
}

teardown() {
    rm -rf "$SPEC_ROOT"
}

# Write a minimal Fig spec for $2 into directory $1
__write_spec() {
    printf '{"name":"%s","options":[{"name":"--alpha","description":"Alpha"},{"name":"--beta"}]}\n' "$2" >"$1/$2.json"
}

function test_fig_spec_dirs_later_entry_found { #@test
    __write_spec "$SPEC_ROOT"/second zzcmd
    local BU_FIG_SPEC_DIRS=$SPEC_ROOT/first:$SPEC_ROOT/second
    __bu_fig_spec_path zzcmd
    assert_equal "$BU_RET" "$SPEC_ROOT/second/zzcmd.json"
}

function test_fig_spec_dirs_first_entry_wins { #@test
    __write_spec "$SPEC_ROOT"/first zzcmd
    __write_spec "$SPEC_ROOT"/second zzcmd
    local BU_FIG_SPEC_DIRS=$SPEC_ROOT/first:$SPEC_ROOT/second
    __bu_fig_spec_path zzcmd
    assert_equal "$BU_RET" "$SPEC_ROOT/first/zzcmd.json"
}

function test_fig_spec_dirs_missing_dir_falls_through_to_bundle { #@test
    __write_spec "$SPEC_ROOT"/bundle tar
    local BU_FIG_SPEC_DIRS=/nonexistent
    local BU_FIG_SPEC_DIR=$SPEC_ROOT/bundle
    __bu_fig_spec_path tar
    assert_equal "$BU_RET" "$SPEC_ROOT/bundle/tar.json"
}

function test_fig_spec_dirs_missing_dir_falls_through_to_default_bundle { #@test
    local -r bundled=$DIR/../fig_specs/build/tar.json
    [[ -f "$bundled" ]] || skip "Fig specs not built"
    local BU_FIG_SPEC_DIRS=/nonexistent
    unset -v BU_FIG_SPEC_DIR
    __bu_fig_spec_path tar
    assert_equal "$(realpath -- "$BU_RET")" "$(realpath -- "$bundled")"
}

function test_fig_spec_dirs_unknown_command { #@test
    local BU_FIG_SPEC_DIRS=$SPEC_ROOT/first:$SPEC_ROOT/second
    run __bu_fig_spec_path zz-no-such-command-zz
    assert_failure 1
}

function test_fig_spec_dirs_empty_is_noop { #@test
    __write_spec "$SPEC_ROOT"/bundle zzcmd
    local BU_FIG_SPEC_DIR=$SPEC_ROOT/bundle
    local BU_FIG_SPEC_DIRS=
    __bu_fig_spec_path zzcmd
    assert_equal "$BU_RET" "$SPEC_ROOT/bundle/zzcmd.json"
    unset -v BU_FIG_SPEC_DIRS
    __bu_fig_spec_path zzcmd
    assert_equal "$BU_RET" "$SPEC_ROOT/bundle/zzcmd.json"
}

function test_fig_spec_dirs_completion { #@test
    __write_spec "$SPEC_ROOT"/second zzcmd
    local BU_FIG_SPEC_DIRS=$SPEC_ROOT/first:$SPEC_ROOT/second
    local -a COMPREPLY=() BU_COMPREPLY_METADATA=()
    local -a command_line=(zzcmd --a)
    __bu_autocomplete_fig_completion_func zzcmd --a
    assert_equal "${COMPREPLY[*]}" --alpha
}
