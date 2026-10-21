#!/usr/bin/env -S bats --jobs 8

# Tests for glob name filters on getter cmdlets: the bu_glob_* helpers
# (PowerShell -Name semantics), the --glob autocomplete DSL marker (match
# hint, validation, --help label), and the commands that adopt them.

setup() {
    load "test_helper/bats-assert/load.bash"
    load "test_helper/bats-support/load.bash"

    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    # shellcheck source=../bu_entrypoint.sh
    source "$DIR"/../bu_entrypoint.sh

    # shellcheck source=./test_helper/bu_bats_decl.sh
    source "$BU_NULL"
}

# ===========================================================================
# bu_glob_has_wildcard / bu_glob_match / bu_glob_excludes
# ===========================================================================

function test_bu_glob_has_wildcard { #@test
    bu_glob_has_wildcard 'BU_*'
    bu_glob_has_wildcard 'get-?'
    bu_glob_has_wildcard 'v[12]'
    bu_glob_has_wildcard '@(a|b)'
    run bu_glob_has_wildcard HOME
    assert_failure
    run bu_glob_has_wildcard 'BU_\*'
    assert_failure
    run bu_glob_has_wildcard 'a(b)'
    assert_failure
    run bu_glob_has_wildcard ''
    assert_failure
}

function test_bu_glob_match { #@test
    bu_glob_match BU_OUT_DIR 'BU_OUT*' HOME
    bu_glob_match HOME 'BU_OUT*' HOME
    bu_glob_match anything
    bu_glob_match v1 'v[12]'
    run bu_glob_match PATH 'BU_*'
    assert_failure
    # A plain name is an exact match, not a substring
    run bu_glob_match HOMEDIR HOME
    assert_failure
    # Escaped wildcards are literal
    bu_glob_match 'a*b' 'a\*b'
    run bu_glob_match axb 'a\*b'
    assert_failure
}

function test_bu_glob_excludes { #@test
    bu_glob_excludes BU_OUT_JQ '*_JQ'
    run bu_glob_excludes BU_OUT_JQ
    assert_failure
    run bu_glob_excludes BU_OUT_DIR '*_JQ'
    assert_failure
}

function test_bu_glob_report_missing { #@test
    local -A seen=([HOME]=1 ['a*b']=1)
    run bu_glob_report_missing variable seen HOME 'NOSUCH_*' 'a\*b'
    assert_success
    assert_output ''
    run bu_glob_report_missing variable seen HOME NOSUCH
    assert_failure
    assert_output --partial "No variable named 'NOSUCH'"
    refute_output --partial "'HOME'"
}

# ===========================================================================
# Completion: --glob marker
# ===========================================================================

function test_glob_word_quoting { #@test
    __bu_autocomplete_glob_word 'BU_*'
    assert_equal "${BU_RET[*]}" 'BU_* true'
    __bu_autocomplete_glob_word "'BU_*"
    assert_equal "${BU_RET[*]}" 'BU_* false'
    __bu_autocomplete_glob_word "'BU_*'"
    assert_equal "${BU_RET[*]}" 'BU_* false'
    __bu_autocomplete_glob_word '"BU_*"'
    assert_equal "${BU_RET[*]}" 'BU_* false'
    # Escaped: bash passes BU_* to the command without expanding it
    __bu_autocomplete_glob_word 'BU_\*'
    assert_equal "${BU_RET[*]}" 'BU_* false'
    __bu_autocomplete_glob_word HOME
    assert_equal "${BU_RET[*]}" 'HOME false'
}

function test_glob_hint_lists_matches { #@test
    local bu_autocomplete_hint="Variable name or pattern"
    local -a COMPREPLY=(BU_OUT_DIR BU_OUT_JQ HOME BU_OUT_DIR)
    local -a BU_COMPREPLY_METADATA=(a b c d)
    __bu_autocomplete_glob_hint 'BU_OUT*' "'BU_OUT*'" false false
    assert_equal "${#COMPREPLY[@]}" 0
    assert_equal "${#BU_COMPREPLY_METADATA[@]}" 0
    assert_equal "$bu_autocomplete_hint" "Variable name or pattern · 'BU_OUT*' matches 2: BU_OUT_DIR BU_OUT_JQ"
}

function test_glob_hint_no_match_and_overflow { #@test
    local bu_autocomplete_hint=
    local -a COMPREPLY=(a b)
    __bu_autocomplete_glob_hint 'z*' 'z*' false false
    assert_equal "$bu_autocomplete_hint" "'z*' matches nothing"

    local i
    COMPREPLY=()
    for i in {1..12}; do COMPREPLY+=("n$i"); done
    bu_autocomplete_hint=
    __bu_autocomplete_glob_hint 'n*' "'n*'" false false
    assert_equal "$bu_autocomplete_hint" "'n*' matches 12: n1 n2 n3 n4 n5 n6 n7 n8 n9 n10 … (+2 more)"
}

function test_glob_hint_warns_when_bash_would_expand { #@test
    local tmpdir
    tmpdir=$(mktemp -d)
    touch "$tmpdir/BU_notes.txt"
    local bu_autocomplete_hint=
    local -a COMPREPLY=(BU_OUT_DIR)
    pushd "$tmpdir" >/dev/null
    __bu_autocomplete_glob_hint 'BU_*' 'BU_*' true false
    popd >/dev/null
    rm -rf "$tmpdir"
    assert_equal "$bu_autocomplete_hint" "'BU_*' matches 1: BU_OUT_DIR · unquoted, bash expands it to 1 file(s) here first: quote it as 'BU_*'"
}

function test_glob_completion_end_to_end { #@test
    local COMPREPLY=() BU_COMPREPLY_METADATA=()
    bu_autocomplete_get_autocompletions bu get-command --verb "'conv*" 2>/dev/null
    assert_equal "${#COMPREPLY[@]}" 2
    assert_equal "${COMPREPLY[0]}" "Hint: Command verb or pattern · 'conv*' matches 2: convert-to convert-from"

    # A plain prefix still completes normally
    COMPREPLY=()
    bu_autocomplete_get_autocompletions bu get-command --verb convert-t 2>/dev/null
    assert_equal "${COMPREPLY[*]}" 'convert-to'
}

function test_glob_completion_show_command_matches_get_command { #@test
    # show-command passes its filters to get-command: same completion.
    __glob_complete() {
        local COMPREPLY=() BU_COMPREPLY_METADATA=()
        bu_autocomplete_get_autocompletions bu "$@" 2>/dev/null
        printf '%s\n' "${COMPREPLY[*]}"
    }
    local opt word expected actual mismatches=
    for opt in --verb --noun; do
        for word in "'conv*" convert-t "'git-b*" git-b; do
            expected=$(__glob_complete get-command "$opt" "$word")
            actual=$(__glob_complete show-command "$opt" "$word")
            [[ "$actual" == "$expected" ]] || mismatches+="$opt $word: [$actual] != [$expected]"$'\n'
        done
    done
    assert_equal "$mismatches" ''
}

function test_glob_validate_positional_accepts_patterns { #@test
    __glob_validate() {
        local is_help=false error_msg=
        local -a autocompletion=("$@")
        bu_validate_positional "$value"
        echo "$is_help"
    }
    value='a*' run __glob_validate --glob --enum alpha beta enum--
    assert_output false
    value='zeta' run __glob_validate --glob --enum alpha beta enum--
    assert_output true
    # Without --glob a pattern is just an unknown value
    value='a*' run __glob_validate --enum alpha beta enum--
    assert_output true
}

# ===========================================================================
# --help
# ===========================================================================

function test_help_parser_marks_glob_arms { #@test
    local tmpdir
    tmpdir=$(mktemp -d)
    cat > "$tmpdir/demo.sh" <<'SCRIPT'
case "$1" in
    --name)# NAME
        # Name or pattern
        bu_parse_positional $# --glob --hint "Name"
        ;;
    --plain)# VALUE
        bu_parse_positional $# --hint "Value"
        ;;
    *)# WIDGET
        # Widget name or pattern
        if bu_env_is_in_autocomplete
        then
            autocompletion=(--glob --enum a b enum--)
        fi
        ;;
esac
SCRIPT
    local -a bu_script_options=() bu_script_option_synopsis=() bu_script_option_docs=() bu_script_option_glob=()
    eval "$(bu_autohelp_parse_case_block_help "$tmpdir/demo.sh" "" "" "")"
    rm -rf "$tmpdir"
    assert_equal "${bu_script_options[*]}" '--name --plain *'
    assert_equal "${bu_script_option_glob[0]:-}" 1
    assert_equal "${bu_script_option_glob[1]:-}" ''
    assert_equal "${bu_script_option_glob[2]:-}" 1
}

function test_help_shows_glob_labels { #@test
    run bu get-variable --help
    assert_success
    # Line-wise: --regexp on the whole output lets `.` cross newlines
    assert_line --regexp 'NAME.*\(positional, glob\)'
    assert_line --regexp '--exclude.*PATTERN.*\(glob\)'
    assert_output --partial "(glob): takes a plain name or a bash pattern"
    refute_line --regexp '--format.*\(glob\)'
}

# ===========================================================================
# Option parser regex: no catastrophic backtracking
# ===========================================================================

function test_option_regex_does_not_hang_on_long_words { #@test
    command -v mawk >/dev/null || skip "mawk not installed"
    # mawk backtracks; the old nested-quantifier regex took >20s on this body
    awk() { mawk "$@"; }
    local tmpdir
    tmpdir=$(mktemp -d)
    cat > "$tmpdir/demo.sh" <<'SCRIPT'
case "$1" in
    --format)# FORMAT
        format=$2
        ;;
    *)
        if bu_env_is_in_autocomplete_and_some_more_words && [[ "$1" != -* ]]
        then
            names+=("$1")
        fi
        ;;
esac
SCRIPT
    run timeout 10 bash -c 'source "$1"/lib/core/bu_core_base.sh >/dev/null 2>&1
        source "$1"/lib/core/bu_core_autocomplete.sh >/dev/null 2>&1
        awk() { mawk "$@"; }
        bu_autocomplete_parse_case_block_options_v2 "$2" "" "" 1' _ "$DIR/.." "$tmpdir/demo.sh"
    rm -rf "$tmpdir"
    assert_success
    assert_output --partial 'bu_script_options[0]="--format"'
}

# ===========================================================================
# Commands
# ===========================================================================

function test_get_variable_patterns_and_exclude { #@test
    GLOB_TEST_A=1 GLOB_TEST_B=2 GLOB_TEST_C=3
    run bu get-variable 'GLOB_TEST_*' --exclude GLOB_TEST_B --format tsv
    assert_success
    assert_equal "$(cut -f1,4 <<<"$output")" $'GLOB_TEST_A\t1\nGLOB_TEST_C\t3'
}

function test_get_variable_missing_name_is_an_error { #@test
    GLOB_TEST_A=1
    run bu get-variable GLOB_TEST_A GLOB_TEST_NOSUCH 'GLOB_NOSUCH_*' --format tsv
    assert_failure
    assert_output --partial "No variable named 'GLOB_TEST_NOSUCH'"
    assert_output --partial $'GLOB_TEST_A\tstring'
    refute_output --partial "GLOB_NOSUCH_"
}

function test_get_config_patterns { #@test
    run bu get-config 'BU_OUT_DI?' --format tsv
    assert_success
    assert_line --regexp $'^BU_OUT_DIR\t'
    assert_equal "${#lines[@]}" 1

    run bu get-config BU_NO_SUCH_SETTING --format tsv
    assert_failure
    assert_output --partial "No setting named 'BU_NO_SUCH_SETTING'"
}

function test_get_alias_missing_name_is_an_error { #@test
    run bu get-alias zz_no_such_alias
    assert_failure
    assert_output --partial "No alias named 'zz_no_such_alias'"
}

function test_get_environment_name_patterns { #@test
    command -v jc >/dev/null || skip "jc not installed"
    export GLOB_ENV_A=1 GLOB_ENV_B=2
    run bu get-environment --name 'GLOB_ENV_*' --name GLOB_ENV_NOSUCH --format tsv
    assert_failure
    assert_output --partial "No environment variable named 'GLOB_ENV_NOSUCH'"
    assert_line $'GLOB_ENV_A\t1'
    assert_line $'GLOB_ENV_B\t2'
}
