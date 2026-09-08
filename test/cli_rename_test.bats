#!/usr/bin/env -S bats --jobs 16

# ===========================================================================
# Tests for generic CLI rename (BU_USER_DEFINED_CLI_COMMAND_NAME) support.
# These must run in a dedicated file because BU_CLI_COMMAND_NAME is set
# once at init time, before the guarded variable block.
# ===========================================================================

setup() {
    load "test_helper/bats-assert/load.bash"
    load "test_helper/bats-support/load.bash"

    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"

    # Set the CLI name BEFORE sourcing so bu_core_var.sh picks it up
    export BU_USER_DEFINED_CLI_COMMAND_NAME=xx
    source "$DIR"/../bu_entrypoint.sh

    # shellcheck source=./test_helper/bu_bats_decl.sh
    source "$BU_NULL"
}

function test_cli_rename_help_uses_cli_name { #@test
    # Bug 1: help text should reference the actual CLI name, not hardcoded "bu"
    run __bu_cli_help
    assert_success

    # The old hardcoded "bu" prose patterns must NOT appear
    refute_output --partial 'bu is a Verb-Noun CLI'
    refute_output --partial 'Type bu <TAB>'
    refute_output --partial 'Run bu <command>'

    # Strip ANSI escapes to check plain text for "xx" (renamed CLI)
    local plain
    plain=$(printf '%s' "$output" | sed 's/'$'\e''\[[0-9;]*[a-zA-Z]//g' | sed 's/'$'\e''[()].//g')
    [[ "$plain" == *'Help for xx'* ]]
    [[ "$plain" == *'xx is a Verb-Noun CLI'* ]]
    [[ "$plain" == *'xx get-command | xx where'* ]]
}

function test_cli_help_key_bindings_module_provenance { #@test
    # The key-bindings table gains a Module column, and every core default
    # binding is stamped with module "bu".
    run __bu_cli_help
    assert_success

    local plain
    plain=$(printf '%s' "$output" | sed 's/'$'\e''\[[0-9;]*[a-zA-Z]//g' | sed 's/'$'\e''[()].//g')

    # Module column header appears in the rendered table (command names use
    # lowercase "module", so the capitalized header is unambiguous).
    [[ "$plain" == *'Module'* ]]

    # Sanity: there are live bindings to assert over.
    assert [ "${#BU_KEY_BINDINGS[@]}" -gt 0 ]

    # Every default binding carries a module stamp, all "bu" in the core set.
    local kb_key
    for kb_key in "${!BU_KEY_BINDINGS[@]}"; do
        if [[ "${BU_KEY_BINDING_MODULES[$kb_key]:-}" != bu ]]; then
            printf 'binding %s has module %s, expected bu\n' \
                "$kb_key" "${BU_KEY_BINDING_MODULES[$kb_key]:-}" >&2
            return 1
        fi
    done
}

function test_cli_rename_pipeline_field_completion { #@test
    # Bug 2: pipeline field completion should resolve producer fields
    # when the CLI is renamed. The registries are keyed on "bu <cmd>",
    # so "xx get-command" must be canonicalized to "bu get-command".
    local command_line_front_before_pipe="xx get-command"
    __bu_out_complete_pipeline_fields ""
    assert_equal "${BU_RET[*]}" "name verb noun namespace type definition synopsis fields stage input output requires_all requires_any module shadows shadowed_by"
}

function test_cli_rename_alias_completion { #@test
    # Bug 3: BU_CLI_COMMAND_ALIASES allows additional names to be
    # accepted by the completion function guard.
    BU_CLI_COMMAND_ALIASES+=(j)

    # Completion invoked with alias "j" should NOT bail at the guard
    COMPREPLY=()
    COMP_CWORD=1
    COMP_WORDS=(j "")
    COMP_LINE="j "
    COMP_POINT=2
    __bu_autocomplete_completion_func_cli j "" ""
    # Should have completions (all registered commands)
    assert [ "${#COMPREPLY[@]}" -gt 0 ]
}

function test_cli_alias_pipeline_field_canonicalization { #@test
    # A pipeline stage typed with a CLI completion alias must canonicalize
    # to "bu <cmd>" so the stage-effect registry matches and field
    # propagation works through transforms (query-object select, etc.).
    BU_CLI_COMMAND_ALIASES+=(j)

    __bu_out_canonicalize_stage "j query-object select name"
    assert_equal "$BU_CANONICAL_STAGE" "bu query-object select name"

    local -a _cal_in=(aa bb cc)
    local -a _cal_out=()
    __bu_out_analyze_stage "j query-object select name" _cal_in _cal_out
    assert_equal "${_cal_out[*]}" "name"
}

function test_cli_rename_parse_command_context_uses_cli_name { #@test
    # bu_parse_command_context must use \$BU_CLI_COMMAND_NAME in its
    # --as-if token, not the hardcoded literal 'bu'.  Otherwise a
    # renamed CLI never expands nested sub-options.
    local -a autocompletion=()
    bu_parse_command_context --__my_marker extra-arg
    # Find the word immediately following --as-if; it must be the
    # renamed CLI name (xx), not the hardcoded "bu".
    local -i i
    local found_cli_name=false
    for (( i = 0; i < ${#autocompletion[@]}; i++ )); do
        if [[ "${autocompletion[$i]}" == '--as-if' ]]; then
            local next=${autocompletion[$i+1]:-}
            [[ "$next" != bu ]] || return 1
            [[ "$next" == "$BU_CLI_COMMAND_NAME" ]] && found_cli_name=true
        fi
    done
    assert_equal "$found_cli_name" true
}
