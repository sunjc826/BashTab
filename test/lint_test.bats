#!/usr/bin/env bats

# ===========================================================================
# bu validate-script — the tree-sitter lint rule engine.
#
# Each fixture in test/fixtures/lint/ pairs a rule with the near-miss forms it
# must NOT report: that is where a text-matching linter goes wrong, so it is
# what these tests pin down.
# ===========================================================================

# The rule engine is a standalone node process, so nearly every test here
# needs no BashTab environment at all. Sourcing bu_entrypoint.sh in setup()
# costs more than all 20 tests combined, so only the one test that calls a
# framework function loads it (see the header-window test below).
setup() {
    load "test_helper/bats-assert/load.bash"
    load "test_helper/bats-support/load.bash"

    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    BU_ROOT="$( cd "$DIR"/.. >/dev/null 2>&1 && pwd )"

    FIXTURES=$DIR/fixtures/lint
    ENGINE=$BU_ROOT/lib/lint/bu_lint.js
}

# Emit "LINE RULE" per finding, so assertions stay readable.
lint_fixture() {
    node "$ENGINE" "$1" | awk -F'\t' '{print $2, $3}'
}

# ===========================================================================
# BU001 — arithmetic command at statement position
# ===========================================================================

function test_bu001_reports_bare_arithmetic_command { #@test
    run lint_fixture "$FIXTURES"/bu001_arith.sh
    assert_success
    assert_line "4 BU001"
}

function test_bu001_reports_arithmetic_inside_a_one_liner_loop { #@test
    # The construct is at STATEMENT position but not at LINE position: this is
    # the case a `^\s*\(\(` regex cannot see.
    run lint_fixture "$FIXTURES"/bu001_arith.sh
    assert_line "9 BU001"
}

function test_bu001_ignores_expansion_and_condition_forms { #@test
    # x=$((i++)) is an arithmetic_expansion; `if ((..))` / `while ((..))`
    # consume the status; `: $((i++))` is the documented fix.
    run lint_fixture "$FIXTURES"/bu001_arith.sh
    assert_equal "${#lines[@]}" 2
}

# ===========================================================================
# BU010 / BU011 — declare without -g at file scope
# ===========================================================================

function test_bu011_reports_file_scope_associative_declare { #@test
    run lint_fixture "$FIXTURES"/bu010_declare.sh
    assert_success
    assert_line "2 BU011"
}

function test_bu011_reports_file_scope_declare_even_when_indented { #@test
    # Inside `if` at file scope: indentation says "nested", scope says global.
    run lint_fixture "$FIXTURES"/bu010_declare.sh
    assert_line "9 BU011"
}

function test_bu011_ignores_function_scope_and_g_and_f_flags { #@test
    # A declare inside a function body (even at column 0), `declare -g`, and
    # `declare -ft` (a function attribute, not a variable) are all correct.
    run lint_fixture "$FIXTURES"/bu010_declare.sh
    assert_equal "${#lines[@]}" 2
}

# ===========================================================================
# BU021 / BU024 — the case-block parser DSL
# ===========================================================================

function test_bu021_reports_flag_annotation_that_parses_an_argument { #@test
    run lint_fixture "$FIXTURES"/bu021_flag.sh
    assert_success
    assert_output "6 BU021"
}

function test_bu024_reports_unterminated_enum_list { #@test
    run lint_fixture "$FIXTURES"/bu024_sentinel.sh
    assert_success
    assert_output "3 BU024"
}

# ===========================================================================
# BU040 / BU041 — command headers
# ===========================================================================

function test_bu040_reports_missing_synopsis_and_dispatch { #@test
    run lint_fixture "$FIXTURES"/commands/demo/bu-no-headers.sh
    assert_success
    assert_equal "${#lines[@]}" 2
    assert_line "1 BU040"
}

function test_bu041_reports_directive_header_past_its_window { #@test
    # Dispatch / Tab-Execute are only honored in the first 8 lines.
    run lint_fixture "$FIXTURES"/commands/demo/bu-late-header.sh
    assert_success
    assert_output "9 BU041"
}

# ===========================================================================
# BU000 — parse coverage
# ===========================================================================

function test_bu000_reports_unparsed_regions_instead_of_passing_silently { #@test
    # Valid bash that tree-sitter-bash 0.25.1 cannot parse. The file must be
    # reported as reduced coverage, never as clean.
    run lint_fixture "$FIXTURES"/broken_parse.sh
    assert_success
    assert_line --index 0 --partial "BU000"
}

function test_bu000_fixture_is_valid_bash { #@test
    # Pins the claim BU000 makes: the file is fine, the grammar is not.
    run bash -n "$FIXTURES"/broken_parse.sh
    assert_success
}

# ===========================================================================
# Engine contracts
# ===========================================================================

function test_engine_exits_nonzero_on_error_severity_findings { #@test
    run node "$ENGINE" "$FIXTURES"/bu024_sentinel.sh
    assert_failure 1
}

function test_engine_exits_zero_when_only_warnings_remain { #@test
    run node "$ENGINE" "$FIXTURES"/bu001_arith.sh
    assert_success
}

function test_engine_strict_exits_two_on_warnings { #@test
    run node "$ENGINE" --strict "$FIXTURES"/bu001_arith.sh
    assert_failure 2
}

function test_baseline_suppresses_known_findings { #@test
    local -r baseline=$BATS_TEST_TMPDIR/baseline
    node "$ENGINE" --write-baseline "$baseline" "$FIXTURES"/bu024_sentinel.sh
    run node "$ENGINE" --baseline "$baseline" "$FIXTURES"/bu024_sentinel.sh
    assert_success
    assert_output ""
}

function test_rule_filter_selects_a_single_rule { #@test
    run node "$ENGINE" --rules BU001 "$FIXTURES"/bu010_declare.sh
    assert_success
    assert_output ""
}

# ===========================================================================
# Self-consistency — the checker and the codebase must not drift apart
# ===========================================================================

function test_the_command_script_passes_its_own_rules { #@test
    run node "$ENGINE" "$BU_ROOT"/commands/core/bu-validate-script.sh
    assert_success
    assert_output ""
}

function test_generated_command_template_synopsis_is_inside_the_header_window { #@test
    # A `# Synopsis:` past line 30 is ignored by __bu_command_headers_parse,
    # so every command generated from the template would lose its synopsis.
    source "$BU_ROOT"/bu_entrypoint.sh
    # shellcheck source=./test_helper/bu_bats_decl.sh
    source "$BU_NULL"

    local -r generated=$BATS_TEST_TMPDIR/bu-generated.sh
    sed 's/@BU_SCRIPT_NAME@/bu_generated/g' "$BU_ROOT"/lib/templates/script_template.sh > "$generated"
    local synopsis=
    __bu_command_header_get "$generated" Synopsis synopsis
    assert_not_equal "$synopsis" ""
}

function test_repository_has_no_error_severity_findings_outside_the_baseline { #@test
    run node "$ENGINE" --root "$BU_ROOT" --severity error --baseline "$BU_ROOT"/.bulintbaseline \
        $(find "$BU_ROOT"/lib/core "$BU_ROOT"/commands "$BU_ROOT"/config -name '*.sh' -type f)
    assert_success
    assert_output ""
}
