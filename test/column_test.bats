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
printf 'Producer must never execute\n' >&2
return 99
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
    run bu get-column
    assert_failure
    out=$(bu get-column get-column --format jsonl)
    assert_equal "$(jq -s length <<< "$out")" 7
    out=$(bu get-column --help | sed $'s/\033\\[[0-9;]*m//g;s/\017//g;s/\033(B//g')
    [[ "$out" == *'OUTPUT COLUMNS'* ]]
    [[ "$out" == *'derived      string  How the column was derived'* ]]
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
