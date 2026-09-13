#!/usr/bin/env bats

setup() {
    load "test_helper/bats-assert/load.bash"
    load "test_helper/bats-support/load.bash"
    source "$BATS_TEST_DIRNAME/../bu_entrypoint.sh"
    export BU_TABLE_PAGER=preset:never
    export BU_OUTPUT_FORMAT=
    query_data="$BATS_TEST_TMPDIR/records.jsonl"
    printf '%s\n' \
        '{"name":"alpha","team":"a","x":10,"active":true,"nested":{"n":1}}' \
        '{"name":"beta","team":"b","x":30,"active":true,"nested":{"n":2}}' \
        '{"name":"gamma","team":"a","x":20,"active":false,"nested":{"n":1}}' \
        '{"name":"delta","team":"b","x":null,"active":true}' > "$query_data"
}

# Compare observable results through the public command, not compiler strings.
assert_query_modes_equal() {
    local pipeline_output combined_output
    pipeline_output=$(BU_QUERY_EXECUTOR=pipeline bu query-object --from "$query_data" "$@")
    combined_output=$(BU_QUERY_EXECUTOR=combined bu query-object --from "$query_data" "$@")
    assert_equal "$combined_output" "$pipeline_output"
}

function test_query_executor_config { #@test
    assert_equal "${BU_CONFIG_PROPERTIES[BU_QUERY_EXECUTOR,default]}" pipeline
    run bu_config_validate_value BU_QUERY_EXECUTOR combined
    assert_success
    run bu_config_validate_value BU_QUERY_EXECUTOR pipeline
    assert_success
    run bu_config_validate_value BU_QUERY_EXECUTOR invalid
    assert_failure
    run env BU_CONFIG_LOCAL_FILE="$BATS_TEST_TMPDIR/config.sh" bash -c \
        'source "$BU_DIR/activate"; bu set-config BU_QUERY_EXECUTOR combined; bu query-object first 0 </dev/null'
    assert_success
    run env BU_QUERY_EXECUTOR=invalid bash -c \
        'source "$BU_DIR/activate"; bu query-object first 0 </dev/null'
    assert_failure
    assert_output --partial 'Invalid BU_QUERY_EXECUTOR'
}

function test_query_executor_filter_project_sort { #@test
    local output
    assert_query_modes_equal where x -ge 10 where '.active == true' grep -i 'ALPHA|BETA' \
        select label=name, value=x order-by value desc first 01
    run bu query-object --from "$query_data" --debug select label=name order-by label
    assert_success
    assert_output --partial '"outputFields":["label"]'
    output=$(BU_QUERY_EXECUTOR=combined bu query-object --from "$query_data" \
        where x -ge 10 where '.active == true' grep -i 'ALPHA|BETA' \
        select label=name, value=x order-by value desc first 01)
    assert_equal "$output" '{"label":"beta","value":30}'
}

function test_query_executor_group_all_aggregates { #@test
    local output
    assert_query_modes_equal group-by team agg count,sum:x,avg:x,min:x,max:x,first:x,last:x,collect:x \
        having count -gt 1 having '.sum_x > 0' select team,total=sum_x,avg_x,collect_x order-by total desc
    assert_query_modes_equal group-by team,active
    assert_query_modes_equal group-by missing agg count
    output=$(BU_QUERY_EXECUTOR=combined bu query-object --from "$query_data" \
        group-by team agg count,avg:x order-by team)
    assert_equal "$output" $'{"team":"a","count":2,"avg_x":15}\n{"team":"b","count":2,"avg_x":30}'
}

function test_query_executor_distinct_expand { #@test
    local output
    assert_query_modes_equal select nested expand distinct
    assert_query_modes_equal select team distinct order-by team desc first 1
    printf '%s\n' '{"a":{"x":1,"y":2},"b":[1,2]}' \
        '{"b":[1,2],"a":{"y":2,"x":1}}' '{"a":null,"b":[2,1]}' > "$query_data"
    assert_query_modes_equal distinct
    output=$(BU_QUERY_EXECUTOR=combined bu query-object --from "$query_data" distinct)
    assert_equal "$output" $'{"a":{"x":1,"y":2},"b":[1,2]}\n{"a":null,"b":[2,1]}'
}

function test_query_executor_native_files_and_outfile { #@test
    local file expected output
    expected=$(BU_QUERY_EXECUTOR=pipeline bu query-object --from "$query_data" select name)
    jq -s . "$query_data" > "$BATS_TEST_TMPDIR/records.json"
    printf 'name\tx\nalpha\t10\nbeta\t30\ngamma\t20\ndelta\t0\n' > "$BATS_TEST_TMPDIR/records.tsv"
    for file in "$query_data" "$BATS_TEST_TMPDIR/records.json" "$BATS_TEST_TMPDIR/records.tsv"; do
        output=$(BU_QUERY_EXECUTOR=combined bu query-object --from "$file" select name)
        assert_equal "$output" "$expected"
    done
    BU_QUERY_EXECUTOR=combined bu query-object --from "$BATS_TEST_TMPDIR/records.json" \
        select name outfile "$BATS_TEST_TMPDIR/result.jsonl"
    assert_equal "$(cat "$BATS_TEST_TMPDIR/result.jsonl")" "$expected"
    output=$(BU_QUERY_EXECUTOR=combined bu query-object --from "$BATS_TEST_TMPDIR/records.tsv" \
        where x -gt 15 select name order-by name)
    assert_equal "$output" $'{"name":"beta"}\n{"name":"gamma"}'
}

function test_query_executor_csv { #@test
    command -v jc >/dev/null || skip "jc is required for CSV import"
    query_data="$BATS_TEST_TMPDIR/records.csv"
    printf 'name,note\nalpha,"hello, world"\nbeta,"two\nlines"\n' > "$query_data"
    assert_query_modes_equal select name,note
    assert_query_modes_equal first 1
}

function test_query_executor_formats_aliases_and_debug { #@test
    local format output pipeline_plan combined_plan
    for format in jsonl json tsv table list; do
        assert_query_modes_equal where active -eq true select name,x --format "$format" --columns name:Name,x:Value
    done
    output=$(BU_QUERY_EXECUTOR=combined bu select name < "$query_data")
    assert_equal "$output" "$(BU_QUERY_EXECUTOR=pipeline bu select name < "$query_data")"
    pipeline_plan=$(BU_QUERY_EXECUTOR=pipeline bu query-object --debug group-by team agg count)
    combined_plan=$(BU_QUERY_EXECUTOR=combined bu query-object --debug group-by team agg count)
    assert_equal "$combined_plan" "$pipeline_plan"
}

function test_query_executor_empty_and_zero { #@test
    local output
    : > "$query_data"
    assert_query_modes_equal select name distinct
    assert_query_modes_equal group-by team agg count order-by count first 2
    : > "$BATS_TEST_TMPDIR/empty.tsv"
    output=$(BU_QUERY_EXECUTOR=combined bu query-object --from "$BATS_TEST_TMPDIR/empty.tsv")
    assert_equal "$output" ''
    printf '\nignored\n' > "$BATS_TEST_TMPDIR/empty.tsv"
    query_data="$BATS_TEST_TMPDIR/empty.tsv"
    assert_query_modes_equal
    query_data="$BATS_TEST_TMPDIR/records.jsonl"
    printf 'malformed\n' > "$query_data"
    output=$(BU_QUERY_EXECUTOR=combined bu query-object --from "$query_data" first 0)
    assert_equal "$output" ''
    printf '{"name":"ok"}\nmalformed\n' > "$query_data"
    output=$(BU_QUERY_EXECUTOR=combined bu query-object --from "$query_data" first 1)
    assert_equal "$output" '{"name":"ok"}'
}

function test_query_executor_errors_and_cleanup { #@test
    local initial_depth=${#BU_SCOPE_STACK[@]}
    local status=0
    export BU_QUERY_EXECUTOR=combined
    printf 'malformed\n' > "$query_data"
    bu query-object --from "$query_data" select name >"$BATS_TEST_TMPDIR/out" 2>"$BATS_TEST_TMPDIR/err" || status=$?
    [[ "$status" != 0 ]]
    assert_equal "${#BU_SCOPE_STACK[@]}" "$initial_depth"
    [[ -s "$BATS_TEST_TMPDIR/err" ]]
    printf '{"name":"ok"}\n' > "$query_data"
    run bu query-object --from "$query_data" where '.name | error("bad value")'
    assert_failure
    assert_output --partial 'bad value'
    run bu query-object --from "$query_data" select bad-key
    assert_failure
    run bu query-object --from "$query_data" group-by name agg bogus:name
    assert_failure
    # A failing sink must survive the query's cleanup, even without pipefail.
    query_with_failed_sink() {
        bu_out() { cat >/dev/null; return 23; }
        bu query-object --from "$query_data"
    }
    run query_with_failed_sink
    assert_failure 23
    query_with_failed_converter() {
        jc() { return 29; }
        bu query-object --from "$BATS_TEST_TMPDIR/failing.csv"
    }
    : > "$BATS_TEST_TMPDIR/failing.csv"
    run query_with_failed_converter
    assert_failure 29
}

function test_query_executor_catch_errors_under_errexit { #@test
    printf 'malformed\n' > "$query_data"
    run env BU_USER_DEFINED_CLI_COMMAND_NAME=qx BU_QUERY_EXECUTOR=combined bash -c '
        source "$BU_DIR/activate" >/dev/null 2>&1
        set -e
        for pipefail in off on; do
            if [[ "$pipefail" == on ]]; then set -o pipefail; fi
            for cli in bu qx; do
                status=0
                "$cli" query-object --from "$1" select name 2>/dev/null || status=$?
                [[ "$status" != 0 && "$-" == *e* && ${#BU_SCOPE_STACK[@]} == 0 ]]
                if "$cli" select name --from "$1" 2>/dev/null; then exit 1; fi
                [[ ${#BU_SCOPE_STACK[@]} == 0 ]]
            done
        done
        [[ $(set -o) == *"pipefail"*"on"* ]]
        printf caught
    ' bash "$query_data"
    assert_success
    assert_output caught
}

function test_query_executor_first_stops_without_eof { #@test
    # A FIFO writer keeps its fd open until the reader confirms completion.
    # This catches accidental slurping/draining and avoids timing a slow sleep.
    local fifo="$BATS_TEST_TMPDIR/input.fifo"
    local helper="$BATS_TEST_TMPDIR/reader.sh"
    local result="$BATS_TEST_TMPDIR/result"
    local reader query_fd
    command -v timeout >/dev/null || skip "timeout is required for the FIFO completion check"
    mkfifo "$fifo"
    cat > "$helper" <<'EOF'
source "$BU_DIR/activate" >/dev/null 2>&1
set -e -o pipefail
BU_QUERY_EXECUTOR=combined bu query-object where keep -eq true select name first 2 < "$1" > "$2"
printf done > "$3"
EOF
    timeout 15 bash "$helper" "$fifo" "$result" "$BATS_TEST_TMPDIR/done" &
    reader=$!
    exec {query_fd}> "$fifo"
    printf '%s\n' '{"name":"skip","keep":false}' '{"name":"one","keep":true}' \
        '{"name":"two","keep":true}' >&"$query_fd"
    wait "$reader"
    exec {query_fd}>&-
    assert_equal "$(cat "$result")" $'{"name":"one"}\n{"name":"two"}'
    assert_equal "$(cat "$BATS_TEST_TMPDIR/done")" done
}

function test_query_executor_first_native_large_file_is_quiet { #@test
    # Ignoring PIPE reproduces recording environments where broken writes are
    # noisy EPIPE errors instead of silent SIGPIPE exits.
    jq -nc 'range(10000) | {n: .}' > "$query_data"
    run bash -c 'source "$BU_DIR/activate" >/dev/null 2>&1; trap "" PIPE; set -o pipefail; BU_QUERY_EXECUTOR=combined bu query-object --from "$1" select n first 2' bash "$query_data"
    assert_success
    assert_output $'{"n":0}\n{"n":1}'
}
