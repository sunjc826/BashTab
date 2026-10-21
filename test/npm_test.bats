#!/usr/bin/env -S bats --jobs 16

# Unit tests for bu get-npm-package (npm ls --json wrapper).
# Uses a fixture project at test/fixtures/npm-project with known dependencies.

setup() {
    load "test_helper/bats-assert/load.bash"
    load "test_helper/bats-support/load.bash"

    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    # shellcheck source=../bu_entrypoint.sh
    source "$DIR"/../bu_entrypoint.sh

    # shellcheck source=./test_helper/bu_bats_decl.sh
    source "$BU_NULL"

    FIXTURE="$DIR/fixtures/npm-project"
}

# ===========================================================================
# Schema verification
# ===========================================================================

function test_bu_get_npm_package_root_record { #@test
    cd "$FIXTURE"
    local root
    root=$(bu get-npm-package | head -1 | jq -c .)
    assert_equal "$(jq -r .name <<<"$root")" "bashtab-npm-fixture"
    assert_equal "$(jq -r .version <<<"$root")" "1.0.0"
    assert_equal "$(jq -r .depth <<<"$root")" "0"
    assert_equal "$(jq -r ._path <<<"$root")" "bashtab-npm-fixture"
    assert_equal "$(jq -r ._parent_path <<<"$root")" "null"
    assert_equal "$(jq -r .resolved <<<"$root")" "null"
}

function test_bu_get_npm_package_schema_fields { #@test
    cd "$FIXTURE"
    local keys
    keys=$(bu get-npm-package | head -1 | jq -r 'keys_unsorted[]' | sort | tr '\n' ' ')
    assert_equal "$keys" "_parent_path _path depth name resolved version "
}

function test_bu_get_npm_package_depth_1 { #@test
    cd "$FIXTURE"
    local count
    count=$(bu get-npm-package | jq -c 'select(.depth == 1)' | wc -l)
    assert_equal "$count" "2"
}

function test_bu_get_npm_package_depth_2 { #@test
    cd "$FIXTURE"
    # ms is under debug at depth 2
    local ms
    ms=$(bu get-npm-package | jq -c 'select(.name == "ms")')
    assert_equal "$(jq -r .depth <<<"$ms")" "2"
    assert_equal "$(jq -r ._parent_path <<<"$ms")" "bashtab-npm-fixture/debug"
    assert_equal "$(jq -r .version <<<"$ms")" "2.1.3"
}

function test_bu_get_npm_package_path_structure { #@test
    cd "$FIXTURE"
    local paths
    paths=$(bu get-npm-package | jq -r '._path' | sort | tr '\n' ' ')
    assert_equal "$paths" "bashtab-npm-fixture bashtab-npm-fixture/chalk bashtab-npm-fixture/debug bashtab-npm-fixture/debug/ms "
}

# ===========================================================================
# Pipeline integration
# ===========================================================================

function test_bu_get_npm_package_filter_depth { #@test
    cd "$FIXTURE"
    local names
    names=$(bu get-npm-package | bu where '.depth == 1' | bu select name | jq -r .name | sort | tr '\n' ' ')
    assert_equal "$names" "chalk debug "
}

function test_bu_get_npm_package_subtree_filter { #@test
    cd "$FIXTURE"
    local names
    names=$(bu get-npm-package | bu where '._path | startswith("bashtab-npm-fixture/debug")' | bu select name | jq -r .name | sort | tr '\n' ' ')
    assert_equal "$names" "debug ms "
}

function test_bu_get_npm_package_total_count { #@test
    cd "$FIXTURE"
    local count
    count=$(bu get-npm-package | wc -l)
    assert_equal "$count" "4"
}

# ===========================================================================
# Completion
# ===========================================================================

function test_e2e_get_npm_package_pipeline_fields { #@test
    local command_line_front_before_pipe="bu get-npm-package | "
    bu_autocomplete_get_autocompletions bu select ""
    assert_equal "${COMPREPLY[*]}" "name version resolved depth _path _parent_path --help -h"
}

# ===========================================================================
# bu get-npm-outdated
# ===========================================================================

function test_bu_get_npm_outdated_schema { #@test
    cd "$FIXTURE"
    # chalk is pinned to an older version so it always appears as outdated
    local record
    record=$(bu get-npm-outdated | jq -c 'select(.name == "chalk")')
    assert_equal "$(jq -r .current <<<"$record")" "5.3.0"
    # latest changes over time — just verify it exists and is a semver
    local latest
    latest=$(jq -r .latest <<<"$record")
    assert_regex "$latest" '^[0-9]+\.[0-9]+\.[0-9]+'
    assert_equal "$(jq -r .dependent <<<"$record")" "npm-project"
}

function test_bu_get_npm_outdated_field_keys { #@test
    cd "$FIXTURE"
    local keys
    keys=$(bu get-npm-outdated | head -1 | jq -r 'keys_unsorted[]' | sort | tr '\n' ' ')
    assert_equal "$keys" "current dependent latest location name wanted "
}

function test_bu_get_npm_outdated_pipeline { #@test
    cd "$FIXTURE"
    local out
    out=$(bu get-npm-outdated | bu select name,current,wanted,latest | jq -c 'select(.name == "chalk")')
    assert_equal "$(jq -r .current <<<"$out")" "5.3.0"
    # wanted may equal current for pinned versions; just verify it is a semver
    assert_regex "$(jq -r .wanted <<<"$out")" '^[0-9]+\.[0-9]+\.[0-9]+'
}

# ===========================================================================
# bu get-pnpm-package (uses BashTab itself as the pnpm project)
# ===========================================================================

function test_bu_get_pnpm_package_schema { #@test
    # Verify the output schema fields
    local keys
    keys=$(bu get-pnpm-package | head -1 | jq -r 'keys_unsorted[]' | sort | tr '\n' ' ')
    assert_equal "$keys" "_parent_path _path depth description from license name path resolved version "
}

function test_bu_get_pnpm_package_root { #@test
    local root
    root=$(bu get-pnpm-package | head -1 | jq -c .)
    assert_equal "$(jq -r .name <<<"$root")" "bashtab"
    assert_equal "$(jq -r .depth <<<"$root")" "0"
}

function test_bu_get_pnpm_package_known_dep { #@test
    # tree-sitter is a direct dependency of BashTab
    local ts
    ts=$(bu get-pnpm-package | jq -c 'select(.name == "tree-sitter")' | head -1)
    assert_equal "$(jq -r .depth <<<"$ts")" "1"
    assert_equal "$(jq -r .license <<<"$ts")" "MIT"
    assert_equal "$(jq -r ._parent_path <<<"$ts")" "bashtab"
}
