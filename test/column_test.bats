#!/usr/bin/env bats

setup() {
    load "test_helper/bats-assert/load.bash"
    load "test_helper/bats-support/load.bash"
    source "$BATS_TEST_DIRNAME/../bu_entrypoint.sh"
    export BU_TABLE_PAGER=preset:never
    export BU_OUTPUT_FORMAT=
    widget="$BATS_TEST_TMPDIR/bu-get-widget.sh"
    cat > "$widget" <<'FIXTURE'
#!/usr/bin/env bash
# Dispatch: source
# Pipeline: producer
# Synopsis: List widgets
# Column: name string Widget name
# Column: up bool Widget responds to pings
# Column: lag int ns Ping round trip, p50
# Column: host string Widget host
printf '%s\n' '{"name":"a","up":true,"lag":5}' '{"name":"b","up":false,"lag":1.5,"extra":"x"}'
FIXTURE
    bu_preinit_register_user_defined_subcommand_file "$widget" get-widget source
    # Late fixture registration runs after init's verb/noun indexing.
    BU_COMMAND_PROPERTIES[get-widget,verb]=get
    BU_COMMAND_PROPERTIES[get-widget,noun]=widget
}

function test_column_parse_types_units_description { #@test
    __bu_column_parse_line 'lag int ns Ping round trip, p50'
    assert_equal "${BU_RET[0]}" lag
    assert_equal "${BU_RET[1]}" int
    assert_equal "${BU_RET[2]}" ns
    assert_equal "${BU_RET[3]}" 'Ping round trip, p50'
    __bu_column_parse_line 'count int nanoseconds are not a unit'
    assert_equal "${BU_RET[2]}" ''
    assert_equal "${BU_RET[3]}" 'nanoseconds are not a unit'
    __bu_column_parse_line 'count numeric Total count'
    assert_equal "${BU_RET[1]}" any
    assert_equal "${BU_RET[3]}" 'numeric Total count'
    __bu_column_parse_line 'name'
    assert_equal "${BU_RET[1]}" any
    run __bu_column_parse_line '   '
    assert_failure
}

function test_column_fields_precedence { #@test
    local fields
    __bu_command_fields_get "$widget" fields
    assert_equal "$fields" 'name up lag host'
    printf '%s\n' '# Fields: host name' '# Column: lag int ns Latency' > "$BATS_TEST_TMPDIR/both.sh"
    __bu_command_fields_get "$BATS_TEST_TMPDIR/both.sh" fields
    assert_equal "$fields" 'host name'
    printf '%s\n' '# Fields: ' '# Column: lag int ns Latency' > "$BATS_TEST_TMPDIR/empty.sh"
    __bu_command_fields_get "$BATS_TEST_TMPDIR/empty.sh" fields
    assert_equal "$fields" ''
}

function test_column_header_continuation_single_and_batch { #@test
    local file="$BATS_TEST_TMPDIR/long.sh" i
    local -a values=()
    for ((i=1; i<29; i++)); do printf '# padding\n'; done > "$file"
    printf '%s\n' '# Column: a int A' '# Column: b int B' '# Column: c int C' '# Column: d int D' \
        'true' '# Column: ignored int Later' >> "$file"
    __bu_command_header_get_all "$file" Column values
    assert_equal "${#values[@]}" 4
    assert_equal "${values[3]}" 'd int D'
    __bu_command_headers_batch "$BATS_TEST_TMPDIR" long.sh
    __bu_command_header_get_all "$file" Column values
    assert_equal "${#values[@]}" 4
    assert_equal "${values[3]}" 'd int D'
}

function test_column_registry_and_lazy_rows { #@test
    local rows
    local BU_CLI_COMMAND_NAME=$BU_CLI_COMMAND_NAME
    bu_register_output_columns 'bu widget-function' 'name string Widget name' 'lag int ns Latency'
    assert_equal "${BU_OUT_PRODUCER_FIELDS[bu widget-function]}" 'name lag'
    __bu_column_for_command 'bu widget-function' rows
    assert_equal "$rows" $'name\x1fstring\x1f\x1fWidget name\nlag\x1fint\x1fns\x1fLatency'
    __bu_column_for_command 'bu get-widget' rows
    assert_equal "$rows" "${BU_OUT_PRODUCER_COLUMNS[bu get-widget]}"
    [[ "$rows" == *$'lag\x1fint\x1fns\x1fPing round trip, p50'* ]]
    BU_CLI_COMMAND_NAME=widgets
    __bu_column_for_command 'widgets get-widget' rows
    [[ "$rows" == *$'lag\x1fint\x1fns\x1fPing round trip, p50'* ]]
}

function test_column_lineage_producer_and_filters { #@test
    local plain filtered
    plain=$(__bu_column_explain_pipeline 'get-widget')
    filtered=$(__bu_column_explain_pipeline 'get-widget | where up -eq true | sort name')
    assert_equal "$filtered" "$plain"
    assert_equal "$(jq -s length <<< "$plain")" 4
    assert_equal "$(jq -r 'select(.column == "lag") | [.type,.unit,.source,.producer] | join("|")' <<< "$plain")" 'int|ns|declared|bu get-widget'
}

function test_column_lineage_select_rename_and_map { #@test
    local out
    local -A hints=()
    out=$(__bu_column_explain_pipeline 'get-widget | select name,rtt=lag')
    assert_equal "$(jq -r 'select(.column == "rtt") | [.column,.type,.unit,.description,.source,.derived] | join("|")' <<< "$out")" \
        'rtt|int|ns|Ping round trip, p50|derived|renamed from lag'
    __bu_column_explain_pipeline --map hints 'get-widget | select name,rtt=lag'
    assert_equal "${hints[rtt]}" $'int\x1fns\x1fPing round trip, p50'
    assert_equal "${#hints[@]}" 2
}

function test_column_lineage_aggregates { #@test
    local out
    out=$(__bu_column_explain_pipeline 'get-widget | query-object group-by host agg count,avg:lag,worst=max:lag')
    assert_equal "$(jq -r '[.column,.type,.unit,.description] | join("|")' <<< "$out")" \
        $'host|string||Widget host\ncount|int||Number of records per host\navg_lag|float|ns|Average of lag per host (lag: Ping round trip, p50)\nworst|int|ns|Maximum of lag per host (lag: Ping round trip, p50)'
    out=$(__bu_column_explain_pipeline 'get-widget | query-object agg sum:lag,min:lag,first:lag,last:lag,collect:lag select total=sum_lag')
    assert_equal "$(jq -r '[.column,.type,.unit,.derived] | join("|")' <<< "$out")" 'total|int|ns|renamed from sum_lag'
    out=$(__bu_column_explain_pipeline 'get-widget | query-object agg first:lag,last:lag,collect:lag')
    assert_equal "$(jq -r '.type' <<< "$out")" $'int\nint\narray'
}

function test_column_lineage_count_alias { #@test
    local out
    out=$(__bu_column_explain_pipeline 'get-widget | count')
    assert_equal "$(jq -r '[.column,.type,.unit,.description] | join("|")' <<< "$out")" 'count|int||Number of records'
}

function test_column_lineage_fields_only_and_unknown_stage { #@test
    local out
    printf '%s\n' '# Dispatch: source' '# Pipeline: producer' '# Fields: id label' > "$BATS_TEST_TMPDIR/bu-get-plain.sh"
    bu_preinit_register_user_defined_subcommand_file "$BATS_TEST_TMPDIR/bu-get-plain.sh" get-plain source
    out=$(__bu_column_explain_pipeline get-plain)
    assert_equal "$(jq -r '[.source,.type,.description] | join("|")' <<< "$out")" $'none||\nnone||'
    run __bu_column_explain_pipeline 'get-widget | jq .'
    assert_failure
    assert_output --partial 'Cannot trace'
    run bu get-column 'get-widget | jq .'
    assert_failure
}

function test_column_trace_is_static_with_quoted_patterns { #@test
    local out marker="$BATS_TEST_TMPDIR/not-executed"
    out=$(__bu_column_explain_pipeline 'get-widget | where name -eq select | grep "foo|bar" | select name')
    assert_equal "$(jq -r .column <<< "$out")" name
    out=$(__bu_column_explain_pipeline "get-widget | where name -eq '\$(touch $marker)' | select name")
    assert_equal "$(jq -r .column <<< "$out")" name
    [[ ! -e "$marker" ]]
}

function test_column_commands_alias_usage_self_help { #@test
    local out
    out=$(bu get-column 'get-widget | select name' --format tsv)
    assert_equal "$out" $'name\tstring\t\tWidget name\tdeclared\tbu get-widget\t'
    out=$(bu explain-column get-widget --format jsonl)
    assert_equal "$(jq -s length <<< "$out")" 4
    assert_equal "$(jq -sr '.[2].unit' <<< "$out")" ns
    run bu get-column </dev/null
    assert_failure
    out=$(bu get-column get-column --format jsonl)
    assert_equal "$(jq -s length <<< "$out")" 8
    assert_equal "$(jq -sr '.[-1].column' <<< "$out")" observed
    out=$(bu get-column --help | sed $'s/\033\\[[0-9;]*m//g;s/\017//g;s/\033(B//g')
    [[ "$out" == *'OUTPUT COLUMNS'* ]]
    [[ "$out" == *'derived      string  How the column was derived'* ]]
    [[ "$out" == *'observed     string  Pipe form only: value types seen on stdin'* ]]
}

function test_column_core_producers_declare_columns { #@test
    local cmd rows fields
    for cmd in get-command get-module get-config; do
        __bu_column_for_command "bu $cmd" rows
        [[ -n "$rows" ]]
        __bu_command_fields_get "${BU_COMMANDS[$cmd]}" fields
        [[ "$fields" == name\ * ]]
    done
    assert_equal "$(bu get-command --verb get --noun widget --columns fields --format tsv)" 'name up lag host'
}

function test_column_completion_renamed_fields { #@test
    local command_line_front_before_pipe='bu get-widget | bu select name,rtt=lag | '
    local out
    out=$(bu_get_completion_candidates bu where '')
    [[ "$out" == *$'name\tstring  Widget name'* ]]
    [[ "$out" == *$'rtt\tint ns  Ping round trip, p50'* ]]
}

function test_column_completion_comma_fields { #@test
    local command_line_front_before_pipe='bu get-widget | '
    local out
    out=$(bu_get_completion_candidates bu select 'name,l')
    [[ "$out" == *$'name,lag\tint ns  Ping round trip, p50'* ]]
    out=$(bu_get_completion_candidates bu query-object group-by 'host,l')
    [[ "$out" == *$'host,lag\tint ns  Ping round trip, p50'* ]]
    out=$(bu_get_completion_candidates bu query-object --columns 'name,l')
    [[ "$out" == *$'name,lag\tint ns  Ping round trip, p50'* ]]
}

function test_column_hints_preserve_ret_and_absent_producer { #@test
    local BU_OUT_COMPLETE_PRODUCER='get-widget'
    local -a COMPREPLY=(existing) BU_COMPREPLY_METADATA=(existing)
    BU_RET=('keep me' other)
    __bu_column_attach_hints 1 .lag name,host
    assert_equal "${BU_RET[*]}" 'keep me other'
    assert_equal "${BU_COMPREPLY_METADATA[0]}" existing
    assert_equal "${BU_COMPREPLY_METADATA[1]}" 'int ns  Ping round trip, p50'
    assert_equal "${BU_COMPREPLY_METADATA[2]}" 'string  Widget host'
    BU_OUT_COMPLETE_PRODUCER=
    __bu_column_attach_hints 0 name
    assert_equal "${BU_COMPREPLY_METADATA[0]}" existing
}

function test_column_registry_function_alias_and_transform { #@test
    local out
    __bu_column_test_producer() { return 99; }
    bu_preinit_register_user_defined_subcommand_function __bu_column_test_producer get-virtual function
    bu_register_stage_effect 'bu get-virtual' producer
    bu_register_output_columns 'bu get-virtual' 'total int Widget count'
    bu_preinit_register_new_alias virtual get-virtual '{...}'
    out=$(__bu_column_explain_pipeline virtual)
    assert_equal "$(jq -r '[.column,.type,.description] | join("|")' <<< "$out")" 'total|int|Widget count'
    bu_register_output_columns 'bu virtual' 'label string Alias label'
    bu_register_stage_effect 'bu virtual' producer
    out=$(__bu_column_explain_pipeline virtual)
    assert_equal "$(jq -r .column <<< "$out")" label
    bu_register_stage_effect 'bu get-virtual' transform
    out=$(__bu_column_explain_pipeline 'get-widget | get-virtual')
    assert_equal "$(jq -r .column <<< "$out")" total
}

function test_column_query_comma_spacing_and_keyword_field { #@test
    local out
    bu_register_output_columns 'bu get-widget' 'name string Widget name' 'first int First value' 'lag int ns Latency'
    out=$(__bu_column_explain_pipeline 'get-widget | query-object select first, r=lag')
    assert_equal "$(jq -r .column <<< "$out")" $'first\nr'
    out=$(__bu_column_explain_pipeline 'get-widget | query-object agg count , avg:lag')
    assert_equal "$(jq -r .column <<< "$out")" $'count\navg_lag'
}

# MARK: Pipe form (sidecars). Pipelines run in the test shell and write to a
# file: `run bash -c` would lose the functions.

__column_test_rows() {
    jq -r '[.column, .type, .source, (.observed // "null")] | join("|")' "$1"
}

# Stands in for a bu stage: record a sidecar on its own stdout pipe.
# $1: pgid to record (empty = the real one), $2: stage
__column_test_forge() {
    local me=$BASHPID link pgid=$1
    # Capture the pid first: fd 1 of a command substitution is its own pipe.
    link=$(readlink "/proc/$me/fd/1")
    link=${link#pipe:[}
    link=${link%]}
    [[ -n "$pgid" ]] || __bu_pipemeta_pgid "$me" pgid
    mkdir -p "$BU_OUT_DIR/pipes"
    printf 'pgid %s\nupstream \nstage %s\n' "$pgid" "$2" > "$BU_OUT_DIR/pipes/$link"
    printf '%s\n' '{"name":"a","up":true,"lag":5}'
}

function test_column_pipe_declared_with_observed_types { #@test
    local out="$BATS_TEST_TMPDIR/out.jsonl"
    BU_OUT_DIR="$BATS_TEST_TMPDIR/out"
    bu get-widget | bu where up -eq true | bu get-column --format jsonl > "$out"
    run __column_test_rows "$out"
    assert_output "name|string|declared|string
up|bool|declared|bool
lag|int|declared|int
host|string|declared|absent"
}

function test_column_pipe_mixed_types_and_undeclared_field { #@test
    local out="$BATS_TEST_TMPDIR/out.jsonl"
    BU_OUT_DIR="$BATS_TEST_TMPDIR/out"
    bu get-widget | bu get-column --format jsonl > "$out"
    assert_equal "$(jq -r 'select(.column == "lag") | .observed' "$out")" 'int,float'
    assert_equal "$(jq -r 'select(.column == "lag") | .unit' "$out")" ns
    assert_equal "$(jq -r 'select(.column == "extra") | [.type, .source, .unit, .producer] | join("|")' "$out")" 'string|inferred||'
    assert_equal "$(jq -sr 'map(.column) | join(" ")' "$out")" 'name up lag host extra'
}

function test_column_pipe_broken_chain_is_inferred { #@test
    local out="$BATS_TEST_TMPDIR/out.jsonl"
    BU_OUT_DIR="$BATS_TEST_TMPDIR/out"
    bu get-widget | grep . | bu get-column --format jsonl > "$out" 2>/dev/null
    run __column_test_rows "$out"
    assert_output "name|string|inferred|string
up|bool|inferred|bool
lag|any|inferred|int,float
extra|string|inferred|string"
}

function test_column_pipe_regular_file_stdin { #@test
    local out="$BATS_TEST_TMPDIR/out.jsonl" in="$BATS_TEST_TMPDIR/in.jsonl"
    BU_OUT_DIR="$BATS_TEST_TMPDIR/out"
    printf '%s\n' '{"k":1}' '{"k":null}' > "$in"
    bu get-column --format jsonl < "$in" > "$out" 2>/dev/null
    run __column_test_rows "$out"
    assert_output 'k|int|inferred|int,null'
}

function test_column_pipe_empty_stream_observes_nothing { #@test
    local out="$BATS_TEST_TMPDIR/out.jsonl"
    BU_OUT_DIR="$BATS_TEST_TMPDIR/out"
    bu get-widget | bu where name -eq nobody | bu get-column --format jsonl > "$out"
    run __column_test_rows "$out"
    assert_output "name|string|declared|null
up|bool|declared|null
lag|int|declared|null
host|string|declared|null"
}

function test_column_pipe_forged_sidecar_same_pgid { #@test
    local out="$BATS_TEST_TMPDIR/out.jsonl"
    BU_OUT_DIR="$BATS_TEST_TMPDIR/out"
    __column_test_forge '' 'bu get-widget' | bu get-column --format jsonl > "$out"
    run __column_test_rows "$out"
    assert_output "name|string|declared|string
up|bool|declared|bool
lag|int|declared|int
host|string|declared|absent"
}

function test_column_pipe_forged_sidecar_other_pgid_rejected { #@test
    local out="$BATS_TEST_TMPDIR/out.jsonl"
    BU_OUT_DIR="$BATS_TEST_TMPDIR/out"
    __column_test_forge 1 'bu get-widget' | bu get-column --format jsonl > "$out" 2>/dev/null
    run __column_test_rows "$out"
    assert_output "name|string|inferred|string
up|bool|inferred|bool
lag|int|inferred|int"
}

function test_column_pipe_sidecars_consumed { #@test
    local out="$BATS_TEST_TMPDIR/out.jsonl"
    local -a left=()
    BU_OUT_DIR="$BATS_TEST_TMPDIR/out"
    bu get-widget | bu where up -eq true | bu get-column > "$out"
    left=("$BU_OUT_DIR"/pipes/*)
    [[ -d "$BU_OUT_DIR/pipes" ]]
    [[ ! -e "${left[0]}" ]]
}

function test_column_pipe_metadata_switch_and_placeholder { #@test
    local -a left=()
    BU_OUT_DIR="$BATS_TEST_TMPDIR/out"
    BU_OUT_PIPE_METADATA=false bu get-widget | cat > /dev/null
    left=("$BU_OUT_DIR"/pipes/*)
    [[ ! -e "${left[0]}" ]]
    bu get-widget | cat > /dev/null
    left=("$BU_OUT_DIR"/pipes/*)
    assert_equal "${#left[@]}" 1
    assert_equal "$(sed -n 3p "${left[0]}")" 'stage bu get-widget'
    rm -f "${left[0]}"
    # Filter values never reach the sidecar verbatim when they could break the lexer.
    bu get-widget | bu where name -eq 'a b|c' | cat > /dev/null
    run grep -h '^stage' "$BU_OUT_DIR"/pipes/*
    assert_line 'stage bu where name -eq _'
    # Not written when stdout is not a pipe.
    rm -f "$BU_OUT_DIR"/pipes/*
    bu get-widget > /dev/null
    left=("$BU_OUT_DIR"/pipes/*)
    [[ ! -e "${left[0]}" ]]
}

function test_column_pipemeta_read_and_pgid { #@test
    local file="$BATS_TEST_TMPDIR/sidecar" pgid=
    __bu_pipemeta_pgid "$BASHPID" pgid
    assert_equal "$pgid" "$(ps -o pgid= -p "$BASHPID" | tr -d ' ')"
    printf 'pgid 42\nupstream 7\nstage bu select a,b\n' > "$file"
    __bu_pipemeta_read "$file" 42
    assert_equal "${BU_RET[0]}" 'bu select a,b'
    assert_equal "${BU_RET[1]}" 7
    run __bu_pipemeta_read "$file" 43
    assert_failure
    run __bu_pipemeta_read "$BATS_TEST_TMPDIR/missing" 42
    assert_failure
    printf 'pgid 42\nupstream 7\n' > "$file"
    run __bu_pipemeta_read "$file" 42
    assert_failure
}
