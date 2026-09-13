#!/usr/bin/env bats

setup() {
    bats_require_minimum_version 1.5.0
    load 'test_helper/bats-assert/load.bash'
    load 'test_helper/bats-support/load.bash'
    source "$BATS_TEST_DIRNAME/../bu_entrypoint.sh"
    export BU_TABLE_PAGER=preset:never BU_OUTPUT_FORMAT=jsonl
    export BU_OUT_STRICT=true BU_OUT_VALIDATION=warn BU_OUT_VALIDATE_RECORDS=first
    contract="$BATS_TEST_TMPDIR/contract.sh"
    printf '# Requires-All: name\n# Requires-Any: id path\n' > "$contract"
    BU_COMMANDS[validation-fixture]=$contract
    records="$BATS_TEST_TMPDIR/records.jsonl"
    printf '%s\n' '{"name":"a","id":null}' '{"name":"b"}' '{"name":"c","path":"p"}' > "$records"
}

function test_record_validation_modes { #@test
    run --separate-stderr __bu_out_strict_guard validation-fixture < "$records"
    assert_success
    assert_equal "$output" "$(cat "$records")"
    assert_equal "$stderr" ''
    export BU_OUT_VALIDATE_RECORDS=all
    run --separate-stderr __bu_out_strict_guard validation-fixture < "$records"
    assert_success
    assert_equal "$output" "$(cat "$records")"
    [[ "$stderr" == *'record 2'* && "$stderr" == *'id|path'* ]]
    export BU_OUT_VALIDATION=error
    run --separate-stderr __bu_out_strict_guard validation-fixture < "$records"
    assert_failure 2
    assert_output '{"name":"a","id":null}'
    [[ "$stderr" == *'record 2'* ]]
    export BU_OUT_VALIDATION=off
    run --separate-stderr __bu_out_strict_guard validation-fixture < "$records"
    assert_success
    assert_equal "$output" "$(cat "$records")"
    assert_equal "$stderr" ''
    export BU_OUT_STRICT=false BU_OUT_VALIDATION=error
    run --separate-stderr __bu_out_strict_guard validation-fixture < "$records"
    assert_success
    assert_equal "$stderr" ''
}

function test_record_validation_invalid_records_and_config { #@test
    local value
    for value in off warn error; do
        run bu_config_validate_value BU_OUT_VALIDATION "$value"
        assert_success
    done
    for value in first all; do
        run bu_config_validate_value BU_OUT_VALIDATE_RECORDS "$value"
        assert_success
    done
    export BU_OUT_VALIDATION=error BU_OUT_VALIDATE_RECORDS=all
    for value in 'null' '[]' 'malformed' '{}'; do
        run --separate-stderr __bu_out_strict_guard validation-fixture <<< "$value"
        assert_failure 2
        assert_output ''
        [[ "$stderr" == *'record 1'* ]]
    done
    run __bu_out_strict_guard validation-fixture </dev/null
    assert_success
    assert_output ''
    export BU_OUT_VALIDATE_RECORDS=bad
    run __bu_out_strict_guard validation-fixture < "$records"
    assert_failure
}

function test_record_validation_consumer_status_and_scope { #@test
    local depth=${#BU_SCOPE_STACK[@]} status=0
    export BU_OUT_VALIDATION=error BU_OUT_VALIDATE_RECORDS=all
    printf '%s\n' '{"name":"BU_VALIDATION_KEEP"}' '{"bad":true}' > "$records"
    BU_VALIDATION_KEEP=present
    bu remove-variable < "$records" >"$BATS_TEST_TMPDIR/out" 2>"$BATS_TEST_TMPDIR/err" || status=$?
    assert_equal "$status" 2
    assert_equal "${#BU_SCOPE_STACK[@]}" "$depth"
    assert_equal "$BU_VALIDATION_KEEP" present
    [[ ! -s "$BATS_TEST_TMPDIR/out" ]]
    # Consumers using the raw-record reader also wait before applying changes.
    run --separate-stderr bu remove-git-tag --dry-run < "$records"
    assert_failure 2
    assert_output ''
    unset BU_VALIDATION_KEEP
}

function test_record_validation_streaming_consumer { #@test
    # Execute only reversible shell-option changes in a child shell. Valid
    # records can take effect before a later error; failure must remain visible.
    printf '%s\n' '{"name":"nullglob","value":true}' '{"bad":true}' > "$records"
    run bash -c '
        source "$BU_DIR/activate" >/dev/null 2>&1
        set -e -o pipefail
        shopt -u nullglob
        export BU_OUT_VALIDATION=error BU_OUT_VALIDATE_RECORDS=all
        status=0
        bu set-shopt-option < "$1" >/dev/null 2>/dev/null || status=$?
        [[ "$status" == 2 && ${#BU_SCOPE_STACK[@]} == 0 ]]
        shopt -q nullglob
        printf caught
    ' bash "$records"
    assert_success
    assert_output caught
}

function test_record_validation_extractor_failure { #@test
    local validation_fd validation_pid status=0
    local -a values=()
    __bu_out_strict_open validation_fd validation_pid validation-fixture '(' < "$records"
    mapfile -t values <&"$validation_fd"
    __bu_out_strict_close "$validation_fd" "$validation_pid" || status=$?
    assert_equal "$status" 3
    assert_equal "${#values[@]}" 0
}
