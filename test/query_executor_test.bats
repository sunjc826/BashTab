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
    local status=0 mode
    for mode in pipeline combined; do
        export BU_QUERY_EXECUTOR=$mode
        status=0
        printf 'malformed\n' > "$query_data"
        bu query-object --from "$query_data" select name >"$BATS_TEST_TMPDIR/out" 2>"$BATS_TEST_TMPDIR/err" || status=$?
        [[ "$status" != 0 ]]
        assert_equal "${#BU_SCOPE_STACK[@]}" "$initial_depth"
        [[ -s "$BATS_TEST_TMPDIR/err" ]]
        printf '{"name":"ok"}\n' > "$query_data"
        run bu query-object --from "$query_data" where '.name | error("bad value")'
        assert_failure
        assert_output --partial 'bad value'
        assert_output --partial "query-object [$mode]:"
        run bu query-object --from "$query_data" select bad-key
        assert_failure
        run bu query-object --from "$query_data" group-by name agg bogus:name
        assert_failure
        # A failing sink must survive the query's cleanup, even without pipefail.
        query_with_failed_sink() {
            bu_out() { cat >/dev/null; return 23; }
            bu query-object --from "$query_data" where '.name | error("upstream failure")'
        }
        run query_with_failed_sink
        assert_failure 23
        assert_output --partial "format stage failed (status 23)"
        query_with_failed_converter() {
            jc() { return 29; }
            bu query-object --from "$BATS_TEST_TMPDIR/failing.csv"
        }
        : > "$BATS_TEST_TMPDIR/failing.csv"
        run query_with_failed_converter
        assert_failure 29
    done
}

function test_query_executor_catch_errors_under_errexit { #@test
    printf 'malformed\n' > "$query_data"
    run env BU_USER_DEFINED_CLI_COMMAND_NAME=qx BU_QUERY_EXECUTOR=combined bash -c '
        source "$BU_DIR/activate" >/dev/null 2>&1
        set -e
        for pipefail_mode in off on; do
            if [[ "$pipefail_mode" == on ]]; then set -o pipefail; fi
            for executor in pipeline combined; do
                export BU_QUERY_EXECUTOR=$executor
                for cli in bu qx; do
                    status=0
                    "$cli" query-object --from "$1" select name 2>/dev/null || status=$?
                    [[ "$status" != 0 && "$-" == *e* && ${#BU_SCOPE_STACK[@]} == 0 ]]
                    if "$cli" select name --from "$1" 2>/dev/null; then exit 1; fi
                    [[ ${#BU_SCOPE_STACK[@]} == 0 ]]
                done
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

function test_query_executor_expected_cancellation_and_real_failure { #@test
    local mode
    query_with_closed_output() {
        bu_out() { cat >/dev/null; return 141; }
        bu query-object --from "$query_data" first 2
    }
    jq -nc 'range(20000) | {n: .}' > "$query_data"
    for mode in pipeline combined; do
        export BU_QUERY_EXECUTOR=$mode
        run bu query-object --from "$query_data" select n first 2
        assert_success
        assert_output $'{"n":0}\n{"n":1}'
        run bu query-object --from "$query_data" where '.n | error("real failure")' first 2
        assert_failure 5
        assert_output --partial 'real failure'
        run query_with_closed_output
        assert_failure 141
        assert_output --partial 'format stage failed (status 141)'
    done
}

function test_query_executor_native_input_and_outfile_failures { #@test
    local mode
    printf 'malformed\n' > "$BATS_TEST_TMPDIR/bad.json"
    for mode in pipeline combined; do
        export BU_QUERY_EXECUTOR=$mode
        run bu query-object --from "$BATS_TEST_TMPDIR/bad.json" select name
        assert_failure
        assert_output --partial 'Invalid numeric literal'
        assert_output --partial "query-object [$mode]:"
        if [[ -c /dev/full ]]; then
            run bu query-object --from "$query_data" outfile /dev/full
            assert_failure
            assert_output --partial 'format stage failed'
        fi
    done
}

function test_query_executor_help_and_parse_error_cleanup { #@test
    local mode status initial_depth=${#BU_SCOPE_STACK[@]}
    for mode in pipeline combined; do
        export BU_QUERY_EXECUTOR=$mode
        bu query-object --help >"$BATS_TEST_TMPDIR/help"
        assert_equal "${#BU_SCOPE_STACK[@]}" "$initial_depth"
        status=0
        bu query-object --format invalid >"$BATS_TEST_TMPDIR/help" 2>&1 || status=$?
        assert_equal "$status" 1
        assert_equal "${#BU_SCOPE_STACK[@]}" "$initial_depth"
    done
}

function test_query_plan_debug_compatibility { #@test
    local mode
    for mode in pipeline combined; do
        export BU_QUERY_EXECUTOR=$mode
        run bu query-object --debug where '.name | error("must not run")' first 5
        assert_success
        assert_output '{"clauses":["where"],"outputFields":null}'
        run bu query-object --debug select label=name, x distinct order-by label desc first 05
        assert_success
        assert_output '{"clauses":["select","distinct","order-by"],"outputFields":["label","x"]}'
        run bu query-object --debug --explain --format json group-by team agg count,mean=avg:x having count -gt 1
        assert_success
        assert_output '{"clauses":["group-by","agg","having"],"outputFields":["team","count","mean"]}'
        run bu query-object --debug select nested expand
        assert_success
        assert_output '{"clauses":["select"],"outputFields":["nested"]}'
    done
}

function test_query_plan_explain_execution { #@test
    local mode plan
    for mode in pipeline combined; do
        export BU_QUERY_EXECUTOR=$mode
        run bu query-object select name,x --explain order-by x desc first 5
        assert_success
        assert_output --partial "Executor: $mode"
        assert_output --partial 'SELECT  name,x  [streaming]'
        assert_output --partial 'ORDER-BY  x descending  [buffers-input]'
        if [[ "$mode" == pipeline ]]; then
            assert_output --partial 'head -n 5'
        else
            assert_output --partial 'jq (combined query)'
        fi
        plan=$(bu query-object --explain --format json where active -eq true group-by team \
            agg count,avg:x having count -gt 1 select team,mean=avg_x distinct order-by mean desc first 05)
        run jq -e --arg mode "$mode" '
            .version == 1 and .executor == $mode and
            .outputFields == ["team","mean"] and
            [.stages[].clause] == ["where","group-by","having","select","distinct","order-by","first"] and
            .stages[1].operation.aggregates == ["count","avg:x"] and
            .stages[4].processing == "retains-seen-values" and
            .stages[5].operation.direction == "descending" and
            .stages[6].operation == 5 and .output.processing == "buffers-results"
        ' <<< "$plan"
        assert_success
    done
}

function test_query_plan_no_input_or_outfile_mutation { #@test
    local mode flag query_fd line plan initial_depth=${#BU_SCOPE_STACK[@]}
    local outfile="$BATS_TEST_TMPDIR/untouched.jsonl"
    local fifo="$BATS_TEST_TMPDIR/unopened.jsonl"
    command -v timeout >/dev/null || skip "timeout is required for the FIFO planning check"
    mkfifo "$fifo"
    printf 'keep me\n' > "$outfile"
    for mode in pipeline combined; do
        export BU_QUERY_EXECUTOR=$mode
        for flag in --debug --explain; do
            exec {query_fd}< "$query_data"
            bu query-object "$flag" --format json select name outfile "$outfile" <&"$query_fd" >/dev/null
            IFS= read -r line <&"$query_fd"
            exec {query_fd}<&-
            assert_equal "$line" '{"name":"alpha","team":"a","x":10,"active":true,"nested":{"n":1}}'
            assert_equal "${#BU_SCOPE_STACK[@]}" "$initial_depth"
        done
        # An unopened FIFO would block forever if planning tried to read it.
        run timeout 15 bash -c '
            source "$BU_DIR/activate" >/dev/null 2>&1
            bu query-object --explain --format jsonl --from "$1" where ".name | error(\"must not run\")" outfile "$2"
        ' bash "$fifo" "$outfile"
        assert_success
        plan=$output
        run jq -e --arg path "$fifo" '.input.source == $path and .input.format == "jsonl"' <<< "$plan"
        assert_success
        assert_equal "$(cat "$outfile")" 'keep me'
    done
}

function test_query_plan_input_and_output_buffering { #@test
    local plan
    export BU_QUERY_EXECUTOR=combined
    printf 'not JSON\n' > "$BATS_TEST_TMPDIR/unread.json"
    plan=$(bu query-object --explain --format jsonl --from "$BATS_TEST_TMPDIR/unread.json" first 2)
    run jq -e '.input.processing == "buffers-json-value" and .output.processing == "streaming"' <<< "$plan"
    assert_success
    plan=$(bu query-object --explain --format jsonl --from "$BATS_TEST_TMPDIR/unread.json" order-by name first 0)
    run jq -e '.input.processing == "not-read" and any(.notes[]; contains("bypasses input"))' <<< "$plan"
    assert_success
    plan=$(bu query-object --explain --format jsonl select nested expand distinct)
    run jq -e '.outputFields == null and .stages[0].operation.expand == true and .stages[1].processing == "retains-seen-values"' <<< "$plan"
    assert_success
    export BU_OUTPUT_FORMAT=table
    run bu query-object --explain outfile "$BATS_TEST_TMPDIR/new.jsonl" first 2
    assert_success
    assert_output --partial '(table; buffers-results)'
    [[ ! -e "$BATS_TEST_TMPDIR/new.jsonl" ]]
}
