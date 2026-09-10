#!/usr/bin/env -S bats --jobs 16

# Unit tests for lib/core/bu_core_out.sh (structured output) and the
# cmdlet wrapper commands (format-table, format-list, convert-to-*, out-default).
#
# All tests are TTY-independent: stdout inside $( ) / run is a pipe, so
# `bu out` auto-dispatch deterministically resolves to jsonl, and table
# headers are never bold.

setup() {
    load "test_helper/bats-assert/load.bash"
    load "test_helper/bats-support/load.bash"

    # get the containing directory of this file
    # use $BATS_TEST_FILENAME instead of ${BASH_SOURCE[0]} or $0,
    # as those will point to the bats executable's location or the preprocessed file respectively
    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    # shellcheck source=../bu_entrypoint.sh
    source "$DIR"/../bu_entrypoint.sh

    # shellcheck source=./test_helper/bu_bats_decl.sh
    source "$BU_NULL"
}

# ===========================================================================
# bu_out_record
# ===========================================================================

function test_bu_out_record_basic { #@test
    run bu_out_record name=bashtab version=0.1.0
    assert_success
    assert_output '{"name":"bashtab","version":"0.1.0"}'
}

function test_bu_out_record_escaping { #@test
    # Quotes, backslashes, newlines and unicode must survive the JSON round-trip
    local out
    out=$(bu_out_record 'weird=a"b\c' $'multi=line1\nline2' 'unicode=✓' | jq -r '.weird + "|" + .multi + "|" + .unicode')
    assert_equal "$out" $'a"b\\c|line1\nline2|✓'
}

function test_bu_out_record_typed_values { #@test
    run bu_out_record alive:=true retries:=3
    assert_success
    assert_output '{"alive":true,"retries":3}'
}

function test_bu_out_record_invalid_key { #@test
    run bu_out_record 'bad-key=x'
    assert_failure
}

function test_bu_out_record_missing_equals { #@test
    run bu_out_record novalue
    assert_failure
}

# ===========================================================================
# bu_out_from_tsv / bu_out_from_lines
# ===========================================================================

function test_bu_out_from_tsv_basic { #@test
    local out
    out=$(printf 'bashtab\t0.1.0\t/x\nmyapp\t-\t/y\n' | bu_out_from_tsv --columns name,version,path)
    assert_equal "$out" '{"name":"bashtab","version":"0.1.0","path":"/x"}
{"name":"myapp","version":"-","path":"/y"}'
}

function test_bu_out_from_tsv_extra_fields_dropped { #@test
    local out
    out=$(printf 'a\t1\tEXTRA\n' | bu_out_from_tsv --columns name,version)
    assert_equal "$out" '{"name":"a","version":"1"}'
}

function test_bu_out_from_tsv_missing_fields_absent { #@test
    local out
    out=$(printf 'b\n' | bu_out_from_tsv --columns name,version)
    assert_equal "$out" '{"name":"b"}'
}

function test_bu_out_from_tsv_blank_lines_skipped { #@test
    local out
    out=$(printf 'a\t1\n\nb\t2\n' | bu_out_from_tsv --columns name,version)
    assert_equal "$out" '{"name":"a","version":"1"}
{"name":"b","version":"2"}'
}

function test_bu_out_from_tsv_requires_columns { #@test
    run bu_out_from_tsv </dev/null
    assert_failure
}

function test_bu_out_from_lines_basic { #@test
    local out
    out=$(printf 'a.txt\nb.txt\n' | bu_out_from_lines --column file)
    assert_equal "$out" '{"file":"a.txt"}
{"file":"b.txt"}'
}

# ===========================================================================
# bu_format_table (buffered)
# ===========================================================================

function test_bu_format_table_basic { #@test
    local out
    out=$(printf '%s\n' '{"name":"bashtab","version":"0.1.0"}' '{"name":"myapp","version":"-"}' \
        | bu_format_table --columns name,version)
    assert_equal "$out" 'name     version
-------  -------
bashtab  0.1.0
myapp    -'
}

function test_bu_format_table_default_columns_and_value_types { #@test
    # No --columns: keys of the first record in insertion order.
    # Numbers/booleans render via tostring, null renders empty.
    local out
    out=$(printf '%s\n' '{"name":"x","n":3,"ok":true,"missing":null}' | bu_format_table)
    assert_equal "$out" 'name  n  ok    missing
----  -  ----  -------
x     3  true'
}

function test_bu_format_table_truncates_to_terminal_width { #@test
    local out
    out=$(COLUMNS=30; printf '%s\n' '{"name":"bashtab","path":"/a/very/long/path/that/exceeds"}' \
        | bu_format_table --columns name,path)
    assert_equal "$out" 'name     path
-------  ---------------------
bashtab  /a/very/long/path/th…'
}

function test_bu_format_table_empty_input_explicit_columns_shows_header { #@test
    # With explicit --columns, render header + separator even for zero rows
    local out
    out=$(printf '' | bu_format_table --columns name,version)
    # header line + separator line, no data rows
    local expected="name  version"$'\n'"----  -------"
    assert_equal "$out" "$expected"
}

function test_bu_format_table_empty_input_no_columns_silent { #@test
    # Without --columns and zero rows, nothing to render → silent
    local out
    out=$(printf '' | bu_format_table)
    assert_equal "$out" ''
}

function test_bu_format_table_no_trailing_spaces { #@test
    local out
    # grep exits 1 when it finds zero trailing-space matches; that is the pass case
    out=$(printf '%s\n' '{"name":"a"}' '{"name":"a-longer-name"}' | bu_format_table --columns name | grep -c ' $' || :)
    assert_equal "$out" '0'
}

function test_bu_format_table_colors_wrap_cells { #@test
    # Explicit --colors applies ANSI even when piped; header stays plain (not a TTY)
    local out
    out=$(printf '%s\n' '{"name":"x"}' | bu_format_table --columns name --colors name=red | grep -c $'\033')
    assert_equal "$out" '2'
}

# ===========================================================================
# bu_format_table --stream
# ===========================================================================

function test_bu_format_table_stream_proportional_widths { #@test
    local out
    out=$(COLUMNS=40; printf '%s\n' '{"name":"bashtab","version":"0.1.0"}' '{"name":"myapp","version":"-"}' \
        | bu_format_table --stream --columns name,version)
    assert_equal "$out" 'name                 version
-------------------  -------------------
bashtab              0.1.0
myapp                -'
}

function test_bu_format_table_stream_requires_columns { #@test
    run bu_format_table --stream </dev/null
    assert_failure
}

# ===========================================================================
# bu_format_list / json / jsonl / tsv
# ===========================================================================

function test_bu_format_list_basic { #@test
    local out
    out=$(printf '%s\n' '{"name":"bashtab","version":"0.1.0"}' '{"name":"myapp","version":"-"}' | bu_format_list)
    assert_equal "$out" 'name    : bashtab
version : 0.1.0

name    : myapp
version : -'
}

function test_bu_format_json_array { #@test
    local out
    out=$(printf '%s\n' '{"a":1}' '{"a":2}' | bu_format_json | jq -c .)
    assert_equal "$out" '[{"a":1},{"a":2}]'
}

function test_bu_format_jsonl_compacts { #@test
    local out
    out=$(printf '%s\n' '{ "a": 1 }' | bu_format_jsonl)
    assert_equal "$out" '{"a":1}'
}

function test_bu_format_tsv_columns { #@test
    local out
    out=$(printf '%s\n' '{"name":"x","path":"/p"}' | bu_format_tsv --columns name,path)
    assert_equal "$out" $'x\t/p'
}

# ===========================================================================
# bu_out dispatch
# ===========================================================================

function test_bu_out_piped_defaults_to_jsonl { #@test
    local out
    out=$(printf '%s\n' '{"a":1}' | bu_out)
    assert_equal "$out" '{"a":1}'
}

function test_bu_out_env_override { #@test
    local out
    out=$(printf '%s\n' '{"a":1}' | BU_OUTPUT_FORMAT=json bu_out | jq -c .)
    assert_equal "$out" '[{"a":1}]'
}

function test_bu_out_explicit_format_beats_env { #@test
    local out
    out=$(printf '%s\n' '{"a":1}' | BU_OUTPUT_FORMAT=json bu_out --format tsv --columns a)
    assert_equal "$out" '1'
}

function test_bu_out_invalid_format { #@test
    run bu_out --format yaml </dev/null
    assert_failure
}

# ===========================================================================
# Transforms: bu_out_where / bu_out_select / bu_out_sort_by
# ===========================================================================

function test_bu_out_where_filters { #@test
    local out
    out=$(printf '%s\n' '{"name":"a","type":"source"}' '{"name":"b","type":"execute"}' | bu_out_where '.type == "source"')
    assert_equal "$out" '{"name":"a","type":"source"}'
}

function test_bu_out_where_requires_expression { #@test
    run bu_out_where </dev/null
    assert_failure
}

function test_bu_out_select_projects_and_reorders { #@test
    local out
    out=$(printf '%s\n' '{"name":"a","version":"1","path":"/x"}' | bu_out_select version,name)
    assert_equal "$out" '{"version":"1","name":"a"}'
}

function test_bu_out_select_renames { #@test
    local out
    out=$(printf '%s\n' '{"name":"a","version":"1"}' | bu_out_select name,ver=version)
    assert_equal "$out" '{"name":"a","ver":"1"}'
}

function test_bu_out_select_invalid_key { #@test
    run bu_out_select 'bad-key=x' </dev/null
    assert_failure
}

function test_bu_out_sort_by_ascending { #@test
    local out
    out=$(printf '%s\n' '{"n":3}' '{"n":1}' '{"n":2}' | bu_out_sort_by n)
    assert_equal "$out" '{"n":1}
{"n":2}
{"n":3}'
}

function test_bu_out_sort_by_descending { #@test
    local out
    out=$(printf '%s\n' '{"n":3}' '{"n":1}' '{"n":2}' | bu_out_sort_by n --desc)
    assert_equal "$out" '{"n":3}
{"n":2}
{"n":1}'
}

function test_bu_out_sort_by_strings { #@test
    local out
    out=$(printf '%s\n' '{"name":"gamma"}' '{"name":"alpha"}' | bu_out_sort_by name | jq -r .name | tr '\n' ' ')
    assert_equal "$out" 'alpha gamma '
}

function test_bu_out_sort_by_requires_key { #@test
    run bu_out_sort_by </dev/null
    assert_failure
}

# ===========================================================================
# Column labels (key:Label)
# ===========================================================================

function test_bu_format_table_labels { #@test
    local out
    out=$(printf '%s\n' '{"name":"bashtab","version":"0.1.0"}' | bu_format_table --columns name:Module,version)
    assert_equal "$out" 'Module   version
-------  -------
bashtab  0.1.0'
}

function test_bu_format_table_label_widens_column { #@test
    local out
    out=$(printf '%s\n' '{"name":"x"}' | bu_format_table --columns name:ModuleName)
    assert_equal "$out" 'ModuleName
----------
x'
}

function test_bu_format_table_label_with_spaces { #@test
    local out
    out=$(printf '%s\n' '{"name":"x","version":"1"}' | bu_format_table --columns 'name:Module Name,version')
    assert_equal "$out" 'Module Name  version
-----------  -------
x            1'
}

function test_bu_format_list_labels { #@test
    local out
    out=$(printf '%s\n' '{"name":"bashtab","version":"0.1.0"}' | bu_format_list --columns name:Module,version)
    assert_equal "$out" 'Module  : bashtab
version : 0.1.0'
}

function test_bu_format_table_stream_labels { #@test
    local out
    out=$(COLUMNS=40; printf '%s\n' '{"name":"bashtab","version":"0.1.0"}' | bu_format_table --stream --columns name:Module,version)
    assert_equal "$out" 'Module               version
-------------------  -------------------
bashtab              0.1.0'
}

function test_bu_format_tsv_strips_labels { #@test
    local out
    out=$(printf '%s\n' '{"name":"x","version":"1"}' | bu_format_tsv --columns name:Module,version)
    assert_equal "$out" $'x\t1'
}

function test_bu_format_table_colors_use_key_not_label { #@test
    # --colors refers to the record key even when the display label differs
    local out
    out=$(printf '%s\n' '{"name":"x"}' | bu_format_table --columns name:Module --colors name=red | grep -c $'\033')
    assert_equal "$out" '2'
}

# ===========================================================================
# bu_format_table --style
# ===========================================================================

function test_bu_format_table_style_ascii { #@test
    local out
    out=$(printf '%s\n' '{"name":"bashtab","version":"0.1.0"}' '{"name":"myapp","version":"-"}' \
        | bu_format_table --columns name,version --style ascii)
    assert_equal "$out" '+---------+---------+
| name    | version |
+---------+---------+
| bashtab | 0.1.0   |
| myapp   | -       |
+---------+---------+'
}

function test_bu_format_table_style_unicode { #@test
    local out
    out=$(printf '%s\n' '{"name":"bashtab","version":"0.1.0"}' '{"name":"myapp","version":"-"}' \
        | bu_format_table --columns name,version --style unicode)
    assert_equal "$out" '┌─────────┬─────────┐
│ name    │ version │
├─────────┼─────────┤
│ bashtab │ 0.1.0   │
│ myapp   │ -       │
└─────────┴─────────┘'
}

function test_bu_format_table_style_double { #@test
    local out
    out=$(printf '%s\n' '{"name":"bashtab","version":"0.1.0"}' '{"name":"myapp","version":"-"}' \
        | bu_format_table --columns name,version --style double)
    assert_equal "$out" '╔═════════╦═════════╗
║ name    ║ version ║
╠═════════╬═════════╣
║ bashtab ║ 0.1.0   ║
║ myapp   ║ -       ║
╚═════════╩═════════╝'
}

function test_bu_format_table_style_clickhouse { #@test
    # ClickHouse PrettyCompact: single-line box with no header separator rule
    local out
    out=$(printf '%s\n' '{"name":"bashtab","version":"0.1.0"}' '{"name":"myapp","version":"-"}' \
        | bu_format_table --columns name,version --style clickhouse)
    assert_equal "$out" '┌─────────┬─────────┐
│ name    │ version │
│ bashtab │ 0.1.0   │
│ myapp   │ -       │
└─────────┴─────────┘'
}

function test_bu_format_table_style_markdown { #@test
    local out
    out=$(printf '%s\n' '{"name":"bashtab","version":"0.1.0"}' '{"name":"myapp","version":"-"}' \
        | bu_format_table --columns name,version --style markdown)
    assert_equal "$out" '| name    | version |
| ------- | ------- |
| bashtab | 0.1.0   |
| myapp   | -       |'
}

function test_bu_format_table_style_mysql { #@test
    local out
    out=$(printf '%s\n' '{"name":"bashtab","version":"0.1.0"}' '{"name":"myapp","version":"-"}' \
        | bu_format_table --columns name,version --style mysql)
    assert_equal "$out" '+---------+---------+
| name    | version |
+---------+---------+
| bashtab | 0.1.0   |
+---------+---------+
| myapp   | -       |
+---------+---------+'
}

function test_bu_format_table_style_psql { #@test
    local out
    out=$(printf '%s\n' '{"name":"bashtab","version":"0.1.0"}' '{"name":"myapp","version":"-"}' \
        | bu_format_table --columns name,version --style psql)
    assert_equal "$out" 'name    | version
-------+-------
bashtab | 0.1.0
myapp   | -'
}

function test_bu_format_table_style_plain { #@test
    # plain: no header underline, no bold — just padded columns
    local out
    out=$(printf '%s\n' '{"name":"bashtab","version":"0.1.0"}' '{"name":"myapp","version":"-"}' \
        | bu_format_table --columns name,version --style plain)
    assert_equal "$out" 'name     version
bashtab  0.1.0
myapp    -'
}

function test_bu_format_table_style_unknown_errors { #@test
    run bu_format_table --columns name --style bogus </dev/null
    assert_failure
}

function test_bu_format_table_style_stream { #@test
    local out
    out=$(COLUMNS=40; printf '%s\n' '{"name":"bashtab","version":"0.1.0"}' '{"name":"myapp","version":"-"}' \
        | bu_format_table --stream --columns name,version --style ascii)
    assert_equal "$out" '+------------------+------------------+
| name             | version          |
+------------------+------------------+
| bashtab          | 0.1.0            |
| myapp            | -                |
+------------------+------------------+'
}

function test_bu_format_table_style_default_from_env { #@test
    # BU_TABLE_STYLE selects the default style when --style is absent
    local out
    out=$(printf '%s\n' '{"name":"x","version":"1"}' | BU_TABLE_STYLE=unicode bu_format_table --columns name,version)
    assert_equal "$out" '┌──────┬─────────┐
│ name │ version │
├──────┼─────────┤
│ x    │ 1       │
└──────┴─────────┘'
}

# ===========================================================================
# Integration: bu commands with structured output
# ===========================================================================

function test_bu_get_module_piped_defaults_to_jsonl { #@test
    local out
    out=$(BU_MODULE_LIST="alpha:1.0.0:/a" bu get-module | jq -c '{name,version,path}')
    assert_equal "$out" '{"name":"alpha","version":"1.0.0","path":"/a"}'
}

function test_bu_get_module_json_array { #@test
    local out
    out=$(BU_MODULE_LIST="alpha:1.0.0:/tmp/alpha;beta:-:/opt/beta" bu get-module --format json | jq -c 'map({name,version,path})')
    assert_equal "$out" '[{"name":"alpha","version":"1.0.0","path":"/tmp/alpha"},{"name":"beta","version":"-","path":"/opt/beta"}]'
}

function test_bu_get_module_columns { #@test
    local out
    out=$(BU_MODULE_LIST="alpha:1.0.0:/a" bu get-module --format tsv --columns name,version)
    assert_equal "$out" $'alpha\t1.0.0'
}

function test_bu_get_module_non_git_path_exact_shape { #@test
    # A registered path outside any git repo yields empty describe/branch and
    # a typed null dirty — no probe of the caller's CWD.
    local out
    out=$(BU_MODULE_LIST="alpha:1.0.0:/nonexistent/preinit.sh" bu get-module)
    assert_equal "$out" '{"name":"alpha","rank":null,"version":"1.0.0","path":"/nonexistent/preinit.sh","describe":"","branch":"","dirty":null}'
}

function test_bu_get_module_git_identity { #@test
    local repo="$BATS_TEST_TMPDIR/modgit"
    mkdir -p "$repo"
    git -C "$repo" init -q -b feature-x
    git -C "$repo" config user.email test@example.com
    git -C "$repo" config user.name Test
    printf 'x\n' > "$repo/file"
    git -C "$repo" add -A
    git -C "$repo" commit -qm init

    local out
    out=$(BU_MODULE_LIST="alpha:1.0.0:$repo/preinit.sh" bu get-module)
    assert_equal "$(printf '%s' "$out" | jq -r .branch)" "feature-x"
    assert_equal "$(printf '%s' "$out" | jq -r '.dirty | type')" "boolean"
    assert_equal "$(printf '%s' "$out" | jq -r .dirty)" "false"
    # no tags → describe falls back to the short sha
    local describe
    describe=$(printf '%s' "$out" | jq -r .describe)
    [[ -n "$describe" ]]
    [[ "$describe" != *-dirty ]]
    assert_equal "$(printf '%s' "$out" | jq -c keys_unsorted)" '["name","rank","version","path","describe","branch","dirty"]'
}

function test_bu_get_module_git_dirty { #@test
    local repo="$BATS_TEST_TMPDIR/modgit-dirty"
    mkdir -p "$repo"
    git -C "$repo" init -q -b main
    git -C "$repo" config user.email test@example.com
    git -C "$repo" config user.name Test
    printf 'a\n' > "$repo/file"
    git -C "$repo" add -A
    git -C "$repo" commit -qm init
    printf 'b\n' > "$repo/file"   # dirty a tracked file

    local out
    out=$(BU_MODULE_LIST="alpha:1.0.0:$repo/preinit.sh" bu get-module)
    assert_equal "$(printf '%s' "$out" | jq -r .dirty)" "true"
    assert_equal "$(printf '%s' "$out" | jq -r '.dirty | type')" "boolean"
    assert_equal "$(printf '%s' "$out" | jq -r '.describe | endswith("-dirty")')" "true"

    # typed booleans match the structured where DSL
    local matched
    matched=$(BU_MODULE_LIST="alpha:1.0.0:$repo/preinit.sh" bu get-module | bu query-object where dirty -eq true | jq -r .name)
    assert_equal "$matched" "alpha"
}

function test_bu_get_module_no_status { #@test
    local repo="$BATS_TEST_TMPDIR/modgit-nostatus"
    mkdir -p "$repo"
    git -C "$repo" init -q -b main
    git -C "$repo" config user.email test@example.com
    git -C "$repo" config user.name Test
    printf 'x\n' > "$repo/file"
    git -C "$repo" add -A
    git -C "$repo" commit -qm init

    local out
    out=$(BU_MODULE_LIST="alpha:1.0.0:$repo/preinit.sh" bu get-module --no-status)
    assert_equal "$(printf '%s' "$out" | jq -r .describe)" ""
    assert_equal "$(printf '%s' "$out" | jq -r .branch)" ""
    assert_equal "$(printf '%s' "$out" | jq -r .dirty)" "null"
}

function test_bu_get_command_metadata { #@test
    local out def
    out=$(bu get-command | jq -c 'select(.name == "get-module")')
    # definition shape: an existing file ending in the command script name
    def=$(printf '%s' "$out" | jq -r .definition)
    [[ -f "$def" ]]
    [[ "$def" == */bu-get-module.sh ]]
    assert_equal "$(printf '%s' "$out" | jq -c 'del(.definition, .shadows, .shadowed_by)')" '{"name":"get-module","verb":"get","noun":"module","namespace":"bu","type":"source","synopsis":"List loaded BashTab modules","fields":"name rank version path describe branch dirty","stage":"producer","input":"none","output":"jsonl","requires_all":"","requires_any":"","module":"bu"}'
}

function test_bu_get_command_multi_word_verb { #@test
    # convert-to is a multi-word verb (BU_MULTI_WORD_VERBS): noun is jsonl, not to-jsonl
    local out def
    out=$(bu get-command | jq -c 'select(.name == "convert-to-jsonl")')
    def=$(printf '%s' "$out" | jq -r .definition)
    [[ -f "$def" ]]
    [[ "$def" == */bu-convert-to-jsonl.sh ]]
    assert_equal "$(printf '%s' "$out" | jq -c 'del(.definition, .shadows, .shadowed_by)')" '{"name":"convert-to-jsonl","verb":"convert-to","noun":"jsonl","namespace":"bu","type":"source","synopsis":"Normalize and emit JSONL records","fields":"","stage":"codec","input":"jsonl","output":"jsonl","requires_all":"","requires_any":"","module":"bu"}'
}

function test_bu_get_command_verb_filter_multi_word { #@test
    local out
    out=$(bu get-command --verb convert-to | jq -sc 'map(.name)')
    assert_equal "$out" '["convert-to-base64","convert-to-csv","convert-to-json","convert-to-jsonl","convert-to-tsv"]'
}

function test_bu_get_command_table_header { #@test
    # Column padding depends on the longest registered command name, which
    # varies with the user's modules, so assert on structure not exact widths
    local out
    out=$(bu get-command --format table | head -1)
    assert_regex "$out" '^name +type +definition +synopsis *$'
}

function test_bu_get_command_table_legacy_columns { #@test
    # Explicit --columns still renders the legacy display set
    local out
    out=$(bu get-command --format table --columns name,verb,noun,namespace,type | head -1)
    assert_regex "$out" '^name +verb +noun +namespace +type *$'
}

function test_bu_get_command_alias_definition { #@test
    local out
    # gc: definition is the expansion spec verbatim, synopsis empty (unregistered)
    out=$(bu get-command | jq -c 'select(.name == "gc")')
    assert_equal "$(printf '%s' "$out" | jq -r .definition)" 'get-command --namespace {} {?} --verb {} {?} --noun {} {...}'
    assert_equal "$(printf '%s' "$out" | jq -r .synopsis)" ''
    # A registered --synopsis wins over the empty default
    bu_preinit_register_new_alias syn-alias-test query-object --where {...} --synopsis "My alias synopsis"
    out=$(bu get-command | jq -c 'select(.name == "syn-alias-test")')
    assert_equal "$(printf '%s' "$out" | jq -r .definition)" 'query-object --where {...}'
    assert_equal "$(printf '%s' "$out" | jq -r .synopsis)" 'My alias synopsis'
}

function test_bu_pipeline_format_table_cmdlet { #@test
    local out
    out=$(BU_MODULE_LIST="alpha:1.0.0:/a" bu get-module | bu format-table --columns name,version)
    assert_equal "$out" 'name   version
-----  -------
alpha  1.0.0'
}

function test_bu_pipeline_convert_to_json_cmdlet { #@test
    local out
    out=$(BU_MODULE_LIST="alpha:1.0.0:/a" bu get-module | bu convert-to-json | jq -c 'map(.name)')
    assert_equal "$out" '["alpha"]'
}

function test_bu_pipeline_out_default_cmdlet { #@test
    local out
    out=$(BU_MODULE_LIST="alpha:1.0.0:/a" bu get-module | bu out-default --format tsv --columns name)
    assert_equal "$out" 'alpha'
}

function test_bu_pipeline_jq_as_where { #@test
    # The PowerShell pipeline payoff: jq between bu commands as Where-Object
    local out
    out=$(bu get-command | jq -c 'select(.verb == "get" and .namespace == "bu" and (.name == "get-command" or .name == "get-module"))' | bu out-default --format tsv --columns name | tr '\n' ' ')
    assert_equal "$out" 'get-command get-module '
}

function test_bu_pipeline_where_select_sort_table { #@test
    # Full transform chain piped into a table sink.
    # Uses the deterministic BU_MODULE_LIST fixture: asserting on the sorted
    # bu command registry breaks whenever a command is added or removed.
    local out
    out=$(BU_MODULE_LIST="zeta:1.0.0:/z;alpha:2.0.0:/a" bu get-module | bu_out_where '.version != ""' | bu_out_select name,version | bu_out_sort_by name | bu_format_table | head -3)
    assert_equal "$out" 'name   version
-----  -------
alpha  2.0.0'
}

# ===========================================================================
# Cmdlet wrappers: where / select / sort /
# convert-from-* / new-record
# ===========================================================================

function test_bu_where_alias_cmdlet { #@test
    local out
    out=$(bu get-command | bu where '.verb == "get" and .namespace == "bu" and (.name == "get-command" or .name == "get-module")' | jq -r .name | tr '\n' ' ')
    assert_equal "$out" 'get-command get-module '
}

function test_bu_select_alias_cmdlet { #@test
    local out
    out=$(BU_MODULE_LIST="alpha:1.0.0:/a" bu get-module | bu select name,ver=version)
    assert_equal "$out" '{"name":"alpha","ver":"1.0.0"}'
}

function test_bu_sort_alias_cmdlet { #@test
    local out
    out=$(printf '%s\n' '{"n":3}' '{"n":1}' | bu sort n | jq -r .n | tr '\n' ' ')
    assert_equal "$out" '1 3 '
}

function test_bu_sort_alias_cmdlet_desc { #@test
    local out
    out=$(printf '%s\n' '{"n":3}' '{"n":1}' | bu sort n --desc | jq -r .n | tr '\n' ' ')
    assert_equal "$out" '3 1 '
}

function test_bu_convert_from_tsv_roundtrip { #@test
    # convert-to-tsv | convert-from-tsv is a lossless round trip for plain values
    local out
    out=$(BU_MODULE_LIST="alpha:1.0.0:/a" bu get-module | bu convert-to-tsv --columns name,version | bu convert-from-tsv --columns name,version)
    assert_equal "$out" '{"name":"alpha","version":"1.0.0"}'
}

function test_bu_convert_from_lines_cmdlet { #@test
    local out
    out=$(printf 'a.txt\nb.txt\n' | bu convert-from-lines --column file)
    assert_equal "$out" '{"file":"a.txt"}
{"file":"b.txt"}'
}

function test_bu_new_record_cmdlet { #@test
    run bu new-record name=bashtab alive:=true retries:=3
    assert_success
    assert_output '{"name":"bashtab","alive":true,"retries":3}'
}

function test_bu_get_command_convert_from_multi_word_verb { #@test
    # convert-from is a multi-word verb: noun is tsv, not from-tsv
    local out def
    out=$(bu get-command | jq -c 'select(.name == "convert-from-tsv")')
    def=$(printf '%s' "$out" | jq -r .definition)
    [[ -f "$def" ]]
    [[ "$def" == */bu-convert-from-tsv.sh ]]
    assert_equal "$(printf '%s' "$out" | jq -c 'del(.definition, .shadows, .shadowed_by)')" '{"name":"convert-from-tsv","verb":"convert-from","noun":"tsv","namespace":"bu","type":"source","synopsis":"Convert TSV text to JSONL records","fields":"","stage":"recordify_tsv","input":"tsv","output":"jsonl","requires_all":"","requires_any":"","module":"bu"}'
}

function test_bu_full_powershell_pipeline { #@test
    # The whole story in one pipeline: produce | Where | Select | Sort | Format
    local out
    out=$(bu get-command \
        | bu where '.namespace == "bu" and .verb == "convert-to"' \
        | bu select name \
        | bu sort name \
        | bu format-table)
    assert_equal "$out" 'name
-----------------
convert-to-base64
convert-to-csv
convert-to-json
convert-to-jsonl
convert-to-tsv'
}

# ===========================================================================
# Pipeline field completion (__bu_out_complete_pipeline_fields)
# ===========================================================================

function test_pipeline_fields_registry_binding_style { #@test
    # The fzf binding exposes the producer text as command_line_front_before_pipe
    local command_line_front_before_pipe="bu get-command | "
    __bu_out_complete_pipeline_fields ""
    assert_equal "${BU_RET[*]}" "name verb noun namespace type definition synopsis fields stage input output requires_all requires_any module shadows shadowed_by"
}

function test_pipeline_fields_registry_prefix_with_flags { #@test
    # Producer carries flags: longest-prefix registry match still applies
    local command_line_front_before_pipe="bu get-command --verb get | "
    __bu_out_complete_pipeline_fields ""
    assert_equal "${BU_RET[*]}" "name verb noun namespace type definition synopsis fields stage input output requires_all requires_any module shadows shadowed_by"
}

function test_pipeline_fields_ts_pipe_before { #@test
    # The tree-sitter binding exposes the producer text as pipe_before
    local pipe_before="bu get-module | "
    __bu_out_complete_pipeline_fields ""
    assert_equal "${BU_RET[*]}" "name rank version path describe branch dirty"
}

function test_pipeline_fields_comp_words_fallback { #@test
    # No binding locals: walk COMP_WORDS for the last standalone pipe
    local command_line_front_before_pipe= pipe_before=
    COMP_WORDS=(bu get-command \| bu select "")
    COMP_CWORD=4
    __bu_out_complete_pipeline_fields ""
    assert_equal "${BU_RET[*]}" "name verb noun namespace type definition synopsis fields stage input output requires_all requires_any module shadows shadowed_by"
}

function test_pipeline_fields_no_pipe_empty { #@test
    local command_line_front_before_pipe= pipe_before=
    COMP_WORDS=(bu select na)
    COMP_CWORD=2
    run __bu_out_complete_pipeline_fields "na"
    assert_failure
}

function test_pipeline_fields_comp_line_fallback { #@test
    # Completion drivers that expose the full line in COMP_LINE but truncate
    # COMP_WORDS to the post-pipe segment still resolve the producer
    local command_line_front_before_pipe= pipe_before=
    COMP_WORDS=(bu select "")
    COMP_CWORD=2
    COMP_LINE='bu get-command | bu select '
    COMP_POINT=${#COMP_LINE}
    __bu_out_complete_pipeline_fields ""
    assert_equal "${BU_RET[*]}" "name verb noun namespace type definition synopsis fields stage input output requires_all requires_any module shadows shadowed_by"
    unset COMP_LINE COMP_POINT
}

function test_pipeline_fields_comp_line_multi_stage { #@test
    # The last unquoted pipe delimits the producer; earlier stages stay intact
    local command_line_front_before_pipe= pipe_before=
    COMP_LINE='bu get-command | bu where name | bu select '
    COMP_POINT=${#COMP_LINE}
    __bu_out_resolve_producer
    assert_equal "$BU_RET" "bu get-command | bu where name"
    unset COMP_LINE COMP_POINT
}

function test_pipeline_fields_comp_line_segment_separators { #@test
    # The producer starts after any earlier ;, && or || segment separator
    local command_line_front_before_pipe= pipe_before=
    local line
    for line in \
        'false || bu get-command | bu select ' \
        'true && bu get-command | bu select ' \
        'true; bu get-command | bu select '
    do
        COMP_LINE=$line
        COMP_POINT=${#COMP_LINE}
        __bu_out_resolve_producer
        assert_equal "$BU_RET" "bu get-command"
    done
    unset COMP_LINE COMP_POINT
}

function test_pipeline_fields_comp_line_quoted_pipe_ignored { #@test
    # Pipes inside quotes are not segment boundaries
    local command_line_front_before_pipe= pipe_before=
    COMP_LINE='echo "a | b" | bu select '
    COMP_POINT=${#COMP_LINE}
    __bu_out_resolve_producer
    assert_equal "$BU_RET" 'echo "a | b"'
    unset COMP_LINE COMP_POINT
}

function test_pipeline_fields_comp_line_no_pipe { #@test
    local command_line_front_before_pipe= pipe_before=
    COMP_WORDS=(bu select "")
    COMP_CWORD=2
    COMP_LINE='bu select '
    COMP_POINT=${#COMP_LINE}
    run __bu_out_complete_pipeline_fields ""
    assert_failure
    unset COMP_LINE COMP_POINT
}

# ===========================================================================
# File schema inference (__bu_out_infer_file_fields / --from self-producer)
# ===========================================================================

__bt_write_data_files() {
    printf 'type,name,verb,version\nsource,get-command,get,1.0\nalias,query-object,query,2.1\n' > "$BATS_TEST_TMPDIR/data.csv"
    printf 'type\tname\tverb\tversion\nsource\tget-command\tget\t1.0\nalias\tquery-object\tquery\t2.1\n' > "$BATS_TEST_TMPDIR/data.tsv"
    printf '{"type":"source","name":"get-command","verb":"get","version":"1.0"}\n{"type":"alias","name":"query-object","verb":"query","version":"2.1"}\n' > "$BATS_TEST_TMPDIR/data.jsonl"
    printf '[{"type":"source","name":"get-command","verb":"get","version":"1.0"},{"type":"alias","name":"query-object","verb":"query","version":"2.1"}]\n' > "$BATS_TEST_TMPDIR/data.json"
}

function test_file_schema_infer_csv { #@test
    command -v jc >/dev/null || skip "jc not installed"
    __bt_write_data_files
    local -a fields=()
    __bu_out_infer_file_fields "$BATS_TEST_TMPDIR/data.csv" fields
    assert_equal "${fields[*]}" "type name verb version"
}

function test_file_schema_infer_tsv { #@test
    __bt_write_data_files
    local -a fields=()
    __bu_out_infer_file_fields "$BATS_TEST_TMPDIR/data.tsv" fields
    assert_equal "${fields[*]}" "type name verb version"
}

function test_file_schema_infer_jsonl { #@test
    __bt_write_data_files
    local -a fields=()
    __bu_out_infer_file_fields "$BATS_TEST_TMPDIR/data.jsonl" fields
    assert_equal "${fields[*]}" "type name verb version"
}

function test_file_schema_infer_json { #@test
    __bt_write_data_files
    local -a fields=()
    __bu_out_infer_file_fields "$BATS_TEST_TMPDIR/data.json" fields
    assert_equal "${fields[*]}" "type name verb version"
}

function test_file_schema_self_from_completion { #@test
    # query-object --from <file> completes fields with no upstream pipe
    __bt_write_data_files
    local command_line_front_before_pipe= pipe_before=
    COMP_LINE="bu query-object --from $BATS_TEST_TMPDIR/data.tsv select "
    COMP_POINT=${#COMP_LINE}
    __bu_out_complete_pipeline_fields ""
    assert_equal "${BU_RET[*]}" "type name verb version"
    unset COMP_LINE COMP_POINT
}

function test_file_schema_recordify_file_pipeline { #@test
    # import-* registers a recordify_file stage; a downstream pipe sees the schema
    __bt_write_data_files
    local pipe_before="bu import-tsv $BATS_TEST_TMPDIR/data.tsv | "
    __bu_out_complete_pipeline_fields ""
    assert_equal "${BU_RET[*]}" "type name verb version"
}

function test_file_schema_field_values { #@test
    # where type -eq <TAB> offers distinct values sampled from the --from file
    __bt_write_data_files
    COMP_LINE="bu query-object --from $BATS_TEST_TMPDIR/data.tsv where type -eq "
    COMP_POINT=${#COMP_LINE}
    __bu_out_complete_field_values type
    assert_equal "${BU_RET[*]}" "alias source"
    unset COMP_LINE COMP_POINT
}

function test_import_tsv_runtime { #@test
    __bt_write_data_files
    local out
    out=$(bu import-tsv "$BATS_TEST_TMPDIR/data.tsv" --format jsonl)
    assert_equal "$out" '{"type":"source","name":"get-command","verb":"get","version":"1.0"}
{"type":"alias","name":"query-object","verb":"query","version":"2.1"}'
}

function test_import_jsonl_runtime { #@test
    __bt_write_data_files
    local out
    out=$(bu import-jsonl "$BATS_TEST_TMPDIR/data.jsonl" --format jsonl)
    assert_equal "$out" '{"type":"source","name":"get-command","verb":"get","version":"1.0"}
{"type":"alias","name":"query-object","verb":"query","version":"2.1"}'
}

function test_query_object_from_tsv_runtime { #@test
    __bt_write_data_files
    local out
    out=$(bu query-object --from "$BATS_TEST_TMPDIR/data.tsv" where type -eq source select name,verb order-by name)
    assert_equal "$out" '{"name":"get-command","verb":"get"}'
}

function test_master_impl_hint_without_ansi_local { #@test
    # Regression: with the fzf binding disabled (plain bash completion),
    # BU_AUTOCOMPLETE_ACCEPT_ANSI_COLORS is unset; the hint path must not
    # execute an empty command name ("bash: : command not found")
    local command_line_front_before_pipe= pipe_before=
    COMP_WORDS=(bu select "")
    COMP_CWORD=2
    COMP_LINE='bu select '
    COMP_POINT=${#COMP_LINE}
    local errfile=$BATS_TEST_TMPDIR/master-impl-stderr
    __bu_autocomplete_completion_func_master_impl \
        "${BU_COMMANDS[query-object]}" "" --select 2 "" \
        "${BU_COMMANDS[query-object]}" --select "" 2>"$errfile"
    run grep -c "command not found" "$errfile"
    assert_failure # grep finds no match
    assert_equal "${COMPREPLY[0]}" "Hint: Fields, new=old renames"
    unset COMP_LINE COMP_POINT
}

function test_pipeline_fields_comma_excludes_used { #@test
    local command_line_front_before_pipe="bu get-command | "
    __bu_out_complete_pipeline_fields "name,ve"
    assert_equal "${BU_RET[*]}" "name,verb"
}

function test_pipeline_fields_dot_mode { #@test
    local command_line_front_before_pipe="bu get-command | "
    __bu_out_complete_pipeline_fields --dot ""
    assert_equal "${BU_RET[*]}" ".name .verb .noun .namespace .type .definition .synopsis .fields .stage .input .output .requires_all .requires_any .module .shadows .shadowed_by"
}

function test_pipeline_fields_register_custom_producer { #@test
    bu_register_output_fields "bu get-pokemon" name id type hp attack
    local command_line_front_before_pipe="bu get-pokemon --type fire | "
    __bu_out_complete_pipeline_fields ""
    assert_equal "${BU_RET[*]}" "name id type hp attack"
}

function test_pipeline_fields_probe_opt_in { #@test
    print_record() { printf '%s\n' '{"alpha":1,"beta":2}'; }
    local command_line_front_before_pipe="print_record | "
    BU_OUT_PROBE_PIPELINE=true
    BU_OUT_PROBE_COMMANDS[print_record]=1
    __bu_out_complete_pipeline_fields ""
    assert_equal "${BU_RET[*]}" "alpha beta"
}

function test_pipeline_fields_probe_disabled_by_default { #@test
    print_record() { printf '%s\n' '{"alpha":1,"beta":2}'; }
    local command_line_front_before_pipe="print_record | "
    BU_OUT_PROBE_PIPELINE=false
    BU_OUT_PROBE_COMMANDS[print_record]=1
    run __bu_out_complete_pipeline_fields ""
    assert_failure
}

function test_pipeline_fields_probe_requires_allowlist { #@test
    print_record() { printf '%s\n' '{"alpha":1,"beta":2}'; }
    local command_line_front_before_pipe="print_record | "
    BU_OUT_PROBE_PIPELINE=true
    run __bu_out_complete_pipeline_fields ""
    assert_failure
}

function test_e2e_select_pipeline_fields { #@test
    # Full completion driver: bu get-command | bu select <TAB>
    local command_line_front_before_pipe="bu get-command | "
    bu_autocomplete_get_autocompletions bu select ""
    assert_equal "${COMPREPLY[*]}" "name verb noun namespace type definition synopsis fields stage input output requires_all requires_any module shadows shadowed_by"
}

function test_e2e_select_comma_continuation { #@test
    local command_line_front_before_pipe="bu get-command | "
    bu_autocomplete_get_autocompletions bu select name,ve
    assert_equal "${COMPREPLY[*]}" "name,verb"
}

function test_e2e_where_dot_fields { #@test
    local command_line_front_before_pipe="bu get-command | "
    bu_autocomplete_get_autocompletions bu where ""
    assert_equal "${COMPREPLY[*]}" "name verb noun namespace type definition synopsis fields stage input output requires_all requires_any module shadows shadowed_by"
}

function test_e2e_sort_pipeline_fields { #@test
    local pipe_before="bu get-module | "
    bu_autocomplete_get_autocompletions bu sort ""
    assert_equal "${COMPREPLY[*]}" "name rank version path describe branch dirty"
}

function test_e2e_format_table_columns_pipeline_fields { #@test
    local command_line_front_before_pipe="bu get-command | "
    bu_autocomplete_get_autocompletions bu format-table --columns ""
    assert_equal "${COMPREPLY[*]}" "name verb noun namespace type definition synopsis fields stage input output requires_all requires_any module shadows shadowed_by"
}

function test_e2e_no_pipeline_shows_hint_only { #@test
    bu_autocomplete_get_autocompletions bu select na
    assert_equal "${COMPREPLY[0]}" "Hint: field"
}

function test_pipeline_fields_dsl_keyword_basic { #@test
    # The --pipeline-fields DSL keyword resolves pipeline producer fields
    local command_line_front_before_pipe="bu get-command | "
    bu_autocomplete_get_autocompletions bu select ""
    assert_equal "${COMPREPLY[*]}" "name verb noun namespace type definition synopsis fields stage input output requires_all requires_any module shadows shadowed_by"
}

function test_pipeline_fields_dsl_keyword_dot { #@test
    # --pipeline-fields --dot prefixes fields for jq expressions
    local command_line_front_before_pipe="bu get-command | "
    local pipe_before=
    # Test the underlying function directly for the dot variant
    __bu_out_complete_pipeline_fields --dot ""
    assert_equal "${BU_RET[*]}" ".name .verb .noun .namespace .type .definition .synopsis .fields .stage .input .output .requires_all .requires_any .module .shadows .shadowed_by"
}

function test_pipeline_fields_dsl_dynamic_hint { #@test
    # When pipeline is detected, hint updates to show available fields
    local command_line_front_before_pipe="bu get-command | "
    bu_autocomplete_get_autocompletions bu sort ""
    # The hint should now mention the available fields, not the static text
    assert_equal "${COMPREPLY[*]}" "name verb noun namespace type definition synopsis fields stage input output requires_all requires_any module shadows shadowed_by"
}

# ===========================================================================
# Command completion after a pipe: format + field compatibility
# ===========================================================================

function test_pipeline_command_filter_jsonl_upstream { #@test
    # After a jsonl producer, jsonl consumers are offered; known-incompatible
    # commands (producers, foreign-format codecs) are hidden.
    local command_line_front_before_pipe="bu get-command | "
    bu_autocomplete_get_autocompletions bu ""
    local joined=" ${COMPREPLY[*]} "
    assert_regex "$joined" ' select '
    assert_regex "$joined" ' where '
    assert_regex "$joined" ' format-table '
    refute_regex "$joined" ' convert-from-tsv '
    refute_regex "$joined" ' get-disk '
}

function test_pipeline_command_filter_tsv_upstream { #@test
    # After convert-to-tsv, jsonl consumers are hidden; tsv/text consumers stay.
    local command_line_front_before_pipe="bu get-command | bu convert-to-tsv | "
    bu_autocomplete_get_autocompletions bu ""
    local joined=" ${COMPREPLY[*]} "
    refute_regex "$joined" ' select '
    refute_regex "$joined" ' where '
    assert_regex "$joined" ' convert-from-tsv '
    assert_regex "$joined" ' convert-from-lines '
}

function test_pipeline_command_filter_no_pipe { #@test
    # Without a pipe, producers are still offered (no filtering).
    bu_autocomplete_get_autocompletions bu ""
    assert_regex " ${COMPREPLY[*]} " ' get-disk '
}

function test_pipeline_command_filter_requires_fields { #@test
    # A # Requires: command is only offered when the upstream producer
    # statically emits those fields.
    local tmpdir
    tmpdir=$(mktemp -d)
    cat > "$tmpdir/bu-needs-host.sh" <<'EOF'
#!/usr/bin/env bash
# Dispatch: source
# Pipeline: query
# Requires-All: host
function __bu_bu_needs_host_main() { :; }
EOF
    cat > "$tmpdir/bu-prod-host.sh" <<'EOF'
#!/usr/bin/env bash
# Dispatch: source
# Pipeline: producer
# Fields: host port name
function __bu_bu_prod_host_main() { :; }
EOF
    cat > "$tmpdir/bu-prod-nohost.sh" <<'EOF'
#!/usr/bin/env bash
# Dispatch: source
# Pipeline: producer
# Fields: name version
function __bu_bu_prod_nohost_main() { :; }
EOF
    bu_preinit_register_user_defined_subcommand_file "$tmpdir/bu-needs-host.sh" needs-host source
    bu_preinit_register_user_defined_subcommand_file "$tmpdir/bu-prod-host.sh" prod-host source
    bu_preinit_register_user_defined_subcommand_file "$tmpdir/bu-prod-nohost.sh" prod-nohost source

    local command_line_front_before_pipe="bu prod-host | "
    bu_autocomplete_get_autocompletions bu ""
    assert_regex " ${COMPREPLY[*]} " ' needs-host '

    command_line_front_before_pipe="bu prod-nohost | "
    bu_autocomplete_get_autocompletions bu ""
    refute_regex " ${COMPREPLY[*]} " ' needs-host '

    rm -rf "$tmpdir"
}

function test_consume_effect_io { #@test
    # A consume command reads jsonl and emits no stream.
    local in= out=
    __bu_out_effect_io consume remove-git-tag in out
    assert_equal "$in" jsonl
    assert_equal "$out" none
}

# ===========================================================================
# Static pipeline validation (backward field analysis)
# ===========================================================================

function test_validate_pipeline_flags_missing_field { #@test
    __bu_out_validate_pipeline "bu get-command | bu sort madeup"
    assert_equal "${BU_RET[*]}" "madeup"
}

function test_validate_pipeline_accepts_valid { #@test
    __bu_out_validate_pipeline "bu get-command | bu sort name"
    assert_equal "${BU_RET[*]}" ""
}

function test_validate_pipeline_select_reads_old_name { #@test
    # "new=old" reads the right-hand (old) name, not the output alias.
    __bu_out_validate_pipeline "bu get-command | bu select name,ver=version"
    assert_equal "${BU_RET[*]}" "version"
}

function test_validate_pipeline_where_structured { #@test
    __bu_out_validate_pipeline "bu get-command | bu where madeup -eq source"
    assert_equal "${BU_RET[*]}" "madeup"
}

function test_validate_pipeline_consume_requires { #@test
    # remove-git-stash reads .index, which get-git-tag does not emit.
    __bu_out_validate_pipeline "bu get-git-tag | bu remove-git-stash"
    assert_equal "${BU_RET[*]}" "index"
}

function test_validate_pipeline_requires_any { #@test
    # enable-service reads .unit // .name; get-process emits neither.
    __bu_out_validate_pipeline "bu get-process | bu enable-service"
    assert_equal "${BU_RET[*]}" "unit|name"
    # get-dpkg-package emits name, which satisfies the OR.
    __bu_out_validate_pipeline "bu get-dpkg-package | bu enable-service"
    assert_equal "${BU_RET[*]}" ""
}

function test_pipeline_command_filter_requires_any { #@test
    # enable-service reads .unit // .name (Requires-Any). After get-dpkg-package
    # (emits name) it's offered; after get-process (emits neither) it's hidden.
    local command_line_front_before_pipe="bu get-dpkg-package | "
    bu_autocomplete_get_autocompletions bu ""
    assert_regex " ${COMPREPLY[*]} " ' enable-service '

    command_line_front_before_pipe="bu get-process | "
    bu_autocomplete_get_autocompletions bu ""
    refute_regex " ${COMPREPLY[*]} " ' enable-service '
}

function test_validate_pipeline_command { #@test
    local out
    out=$(bu validate-pipeline 'bu get-command | bu sort madeup')
    assert_equal "$out" '{"field":"madeup"}'
}

# ===========================================================================
# bu get-shape (inferred output schema)
# ===========================================================================

function test_get_shape_infers_types { #@test
    local out
    out=$(bu get-shape get-module --format jsonl)
    assert_equal "$(printf '%s' "$out" | jq -r 'select(.name=="name") | .type')" "string"
    assert_equal "$(printf '%s' "$out" | jq -r 'select(.name=="rank") | .type')" "number"
    assert_equal "$(printf '%s' "$out" | jq -r 'select(.name=="name") | .required')" "true"
}

function test_get_shape_declared_fields_on_empty { #@test
    local tmpdir
    tmpdir=$(mktemp -d)
    cat > "$tmpdir/bu-empty-prod.sh" <<'EOF'
#!/usr/bin/env bash
# Dispatch: source
# Pipeline: producer
# Fields: alpha beta
function __bu_bu_empty_prod_main() { :; }
EOF
    bu_preinit_register_user_defined_subcommand_file "$tmpdir/bu-empty-prod.sh" empty-prod source
    local out
    out=$(bu get-shape empty-prod --format jsonl)
    assert_equal "$(printf '%s' "$out" | jq -r 'select(.name=="alpha") | .count')" "0"
    assert_equal "$(printf '%s' "$out" | jq -r 'select(.name=="alpha") | .required')" "false"
    rm -rf "$tmpdir"
}

function test_get_member_empty_input_silent { #@test
    local out
    out=$(printf '' | bu get-member 2>&1)
    assert_equal "$out" ""
}

# ===========================================================================
# BU_OUT_STRICT runtime validation
# ===========================================================================

function test_strict_guard_passthrough_and_warn { #@test
    local tmpdir out
    tmpdir=$(mktemp -d)
    cat > "$tmpdir/bu-needs-host.sh" <<'EOF'
#!/usr/bin/env bash
# Dispatch: source
# Pipeline: consume
# Requires-All: host
function __bu_bu_needs_host_main() { :; }
EOF
    bu_preinit_register_user_defined_subcommand_file "$tmpdir/bu-needs-host.sh" needs-host source

    # Strict off: pure passthrough, no warning.
    out=$(printf '{"name":"x"}\n' | __bu_out_strict_guard needs-host 2>/dev/null)
    assert_equal "$out" '{"name":"x"}'

    # Strict on: stdout still passes the record through; stderr warns.
    out=$(printf '{"name":"x"}\n' | BU_OUT_STRICT=true __bu_out_strict_guard needs-host 2>/dev/null)
    assert_equal "$out" '{"name":"x"}'
    out=$(printf '{"name":"x"}\n' | BU_OUT_STRICT=true __bu_out_strict_guard needs-host 2>&1 >/dev/null)
    assert_regex "$out" 'BU_OUT_STRICT'
    assert_regex "$out" 'needs-host'
    assert_regex "$out" 'host'

    rm -rf "$tmpdir"
}

# ===========================================================================
# Cmdlets end at Out-Default: table on a terminal, JSONL when piped
# ===========================================================================

function test_cmdlets_jsonl_when_piped { #@test
    # $( ) capture is not a terminal, so transforms stay JSONL (already covered
    # by the cmdlet tests above); assert explicitly for select
    local out
    out=$(BU_MODULE_LIST="a:1.0.0:/x" bu get-module | bu select name,version)
    assert_equal "$out" '{"name":"a","version":"1.0.0"}'
}

function test_cmdlets_table_when_terminal { #@test
    # script(1) allocates a pty, so the pipeline terminus sees a terminal and
    # Out-Default renders a table (bold header ANSI stripped).
    # NULs stripped: util-linux script(1) can inject spurious NUL bytes into
    # the pty stream (seen on ubuntu-24.04's 2.39 in GitHub CI)
    local helper=$BATS_TEST_TMPDIR/pty_select.sh
    cat > "$helper" <<EOF
source "$DIR/../bu_entrypoint.sh" >/dev/null 2>&1
BU_MODULE_LIST="a:1.0.0:/x" bu get-module | bu select name,version
EOF
    local out
    out=$(script -qec "bash $helper" /dev/null </dev/null | tr -d '\r\000\016\017' | sed 's/\x1b\[[0-9;]*m//g;s/\x1b(B//g')
    assert_equal "$out" 'name  version
----  -------
a     1.0.0'
}

function test_cmdlets_env_format_override { #@test
    # BU_OUTPUT_FORMAT flows through the transform's implicit bu_out
    local out
    out=$(BU_MODULE_LIST="a:1.0.0:/x" bu get-module | BU_OUTPUT_FORMAT=tsv bu select name)
    assert_equal "$out" 'a'
}

function test_cmdlets_intermediate_stays_jsonl { #@test
    # Even on a terminal, a non-terminus transform must emit JSONL: here
    # where is mid-pipeline, convert-to-tsv is the terminus
    local helper=$BATS_TEST_TMPDIR/pty_chain.sh
    cat > "$helper" <<EOF
source "$DIR/../bu_entrypoint.sh" >/dev/null 2>&1
BU_MODULE_LIST="a:1.0.0:/x;b:2.0.0:/y" bu get-module | bu where '.name == "b"' | bu convert-to-tsv --columns name
EOF
    local out
    out=$(script -qec "bash $helper" /dev/null </dev/null | tr -d '\r\000\016\017')
    assert_equal "$out" 'b'
}

# ===========================================================================
# bu query-object (SQL-style compositor)
# ===========================================================================

function test_bu_query_object_full_query { #@test
    local out
    # Deterministic BU_MODULE_LIST fixture (see test_bu_pipeline_where_select_sort_table)
    out=$(BU_MODULE_LIST="zeta:1.0.0:/z;alpha:2.0.0:/a" bu get-module | bu query-object --where '.version != ""' --select name,version --order-by name --first 2 --format tsv --columns name,version)
    assert_equal "$out" $'alpha\t2.0.0\nzeta\t1.0.0'
}

function test_bu_query_object_bare_keywords { #@test
    # SQL keywords without dashes
    local out
    # Deterministic BU_MODULE_LIST fixture (see test_bu_pipeline_where_select_sort_table)
    out=$(BU_MODULE_LIST="zeta:1.0.0:/z;alpha:2.0.0:/a" bu get-module | bu query-object where '.version != ""' select name,version order-by name first 2 --format tsv --columns name,version)
    assert_equal "$out" $'alpha\t2.0.0\nzeta\t1.0.0'
}

function test_bu_query_object_clause_order_invariance { #@test
    local a b
    a=$(bu get-command | bu query-object where '.namespace == "bu"' select name order-by name --format jsonl)
    b=$(bu get-command | bu query-object --order-by name --select name --where '.namespace == "bu"' --format jsonl)
    assert_equal "$a" "$b"
}

function test_bu_query_object_bare_dashed_equivalence { #@test
    local a b
    a=$(bu get-command | bu query-object where '.verb == "get" and (.name == "get-command" or .name == "get-module")' select name order-by name --format jsonl)
    b=$(bu get-command | bu query-object --where '.verb == "get" and (.name == "get-command" or .name == "get-module")' --select name --order-by name --format jsonl)
    assert_equal "$a" "$b"
    assert_equal "$a" '{"name":"get-command"}
{"name":"get-module"}'
}

function test_bu_query_object_rename_then_order_by_alias { #@test
    # SQL semantics: ORDER BY sees SELECT aliases
    local out
    out=$(BU_MODULE_LIST="b:2.0.0:/x;a:1.0.0:/y" bu get-module | bu query-object select name,ver=version order-by ver)
    assert_equal "$out" '{"name":"a","ver":"1.0.0"}
{"name":"b","ver":"2.0.0"}'
}

function test_bu_query_object_multiple_where_anded { #@test
    local out
    out=$(bu get-command | bu query-object where '.namespace == "bu"' where '.verb == "get"' where '(.name == "get-command" or .name == "get-module")' select name --format tsv --columns name)
    assert_equal "$out" $'get-command\nget-module'
}

function test_bu_query_object_desc { #@test
    local out
    out=$(BU_MODULE_LIST="alpha:1.0.0:/a;zeta:2.0.0:/z;beta:3.0.0:/b" bu get-module | bu query-object order-by name desc first 2 select name --format tsv --columns name)
    # descending: zeta, beta, alpha → first 2: zeta, beta
    assert_equal "$out" $'zeta\nbeta'
}

function test_bu_query_object_invalid_first { #@test
    run bu query-object first abc </dev/null
    assert_failure
}

function test_bu_query_object_no_clauses_passthrough { #@test
    local out
    out=$(BU_MODULE_LIST="a:1.0.0:/x" bu get-module | bu query-object)
    assert_equal "$out" '{"name":"a","rank":null,"version":"1.0.0","path":"/x","describe":"","branch":"","dirty":null}'
}

function test_bu_query_object_metadata { #@test
    local out def
    out=$(bu get-command | jq -c 'select(.name == "query-object")')
    def=$(printf '%s' "$out" | jq -r .definition)
    [[ -f "$def" ]]
    [[ "$def" == */bu-query-object.sh ]]
    assert_equal "$(printf '%s' "$out" | jq -c 'del(.definition, .shadows, .shadowed_by)')" '{"name":"query-object","verb":"query","noun":"object","namespace":"bu","type":"source","synopsis":"Apply SQL-style clauses (where, group-by, select, order-by) to a JSONL stream","fields":"","stage":"query","input":"jsonl","output":"jsonl","requires_all":"","requires_any":"","module":"bu"}'
}

function test_e2e_query_object_clause_completion { #@test
    # Bare keywords are suggested as options, and clause values get pipeline fields
    local command_line_front_before_pipe="bu get-command | "
    bu_autocomplete_get_autocompletions bu query-object se
    assert_equal "${COMPREPLY[*]}" "select"
    bu_autocomplete_get_autocompletions bu query-object select ""
    assert_equal "${COMPREPLY[*]}" "name verb noun namespace type definition synopsis fields stage input output requires_all requires_any module shadows shadowed_by"
}

function test_e2e_query_object_where_dot_completion { #@test
    local command_line_front_before_pipe="bu get-command | "
    bu_autocomplete_get_autocompletions bu query-object where ""
    assert_equal "${COMPREPLY[*]}" "name verb noun namespace type definition synopsis fields stage input output requires_all requires_any module shadows shadowed_by"
}

# ===========================================================================
# query-object select projections in multi-stage static analysis
# ===========================================================================

function test_query_object_analyze_select_projection { #@test
    # The query effect statically parses a select clause (like the project
    # effect parses a field spec), so projected columns are known without
    # running --debug.
    local -a qas_in=(aa bb cc)
    local -a qas_out=()
    __bu_out_analyze_stage "bu query-object select name,ver=version" qas_in qas_out
    assert_equal "${qas_out[*]}" "name ver"
}

function test_query_object_analyze_select_among_clauses { #@test
    # select may appear after where; the parser still finds it
    local -a qas_in=(aa bb cc)
    local -a qas_out=()
    __bu_out_analyze_stage "bu query-object where verb -eq get select name" qas_in qas_out
    assert_equal "${qas_out[*]}" "name"
}

function test_query_object_analyze_select_value_not_clause { #@test
    # A bare "select" used as a comparison VALUE must not be mistaken for a clause
    local -a qas_in=(aa bb cc)
    local -a qas_out=()
    __bu_out_analyze_stage "bu query-object where type -eq select" qas_in qas_out
    assert_equal "${qas_out[*]}" "aa bb cc"
}

function test_query_object_analyze_select_multi_word_projection { #@test
    # The static select parser accepts flexible comma placement across words.
    local -a qas_in=(aa bb cc)
    local -a qas_out=()
    __bu_out_analyze_stage "bu query-object select name, ver=version" qas_in qas_out
    assert_equal "${qas_out[*]}" "name ver"
    __bu_out_analyze_stage "bu query-object select name , ver=version" qas_in qas_out
    assert_equal "${qas_out[*]}" "name ver"
    __bu_out_analyze_stage "bu query-object select name ,ver=version" qas_in qas_out
    assert_equal "${qas_out[*]}" "name ver"
}

function test_query_object_analyze_select_multi_word_stops_at_clause { #@test
    # A following clause keyword terminates the multi-word select spec.
    local -a qas_in=(aa bb cc)
    local -a qas_out=()
    __bu_out_analyze_stage "bu query-object select name, ver where verb -eq get" qas_in qas_out
    assert_equal "${qas_out[*]}" "name ver"
}

function test_query_object_pipeline_select_multi_word_propagation { #@test
    # The projected fields from a multi-word select are what the next stage sees.
    local pipe_before="bu get-command | bu query-object select name, ver=version"
    local command_line_front_before_pipe=
    __bu_out_complete_pipeline_fields ""
    assert_equal "${BU_RET[*]}" "name ver"
}

function test_query_object_pipeline_select_propagation { #@test
    # Full completion path: the projected field is what the next stage sees
    local pipe_before="bu get-command | bu query-object select name"
    local command_line_front_before_pipe=
    __bu_out_complete_pipeline_fields ""
    assert_equal "${BU_RET[*]}" "name"
}

function test_query_object_pipeline_group_by_propagation { #@test
    # No select clause: --debug computes group keys + aggregate names even in
    # the completion context (BU_COMP_FAKE keeps it out of autocomplete mode).
    local pipe_before="bu get-command | bu query-object group-by verb agg count"
    local command_line_front_before_pipe=
    __bu_out_complete_pipeline_fields ""
    assert_equal "${BU_RET[*]}" "verb count"
}

# ===========================================================================
# Flexible comma placement across words (select/group-by/agg/columns/-in)
# ===========================================================================

function test_query_object_select_comma_multi_word_runtime { #@test
    local data single
    data=$(printf '%s\n' '{"name":"get-command","type":"source","verb":"get"}' '{"name":"set-module","type":"execute","verb":"set"}')
    single=$(printf '%s\n' "$data" | bu query-object select name,type)
    assert_equal "$(printf '%s\n' "$data" | bu query-object select name, type)" "$single"
    assert_equal "$(printf '%s\n' "$data" | bu query-object select name , type)" "$single"
    assert_equal "$(printf '%s\n' "$data" | bu query-object select name ,type)" "$single"
}

function test_query_object_group_by_comma_multi_word_runtime { #@test
    local data single
    data=$(printf '%s\n' '{"verb":"get","type":"source"}' '{"verb":"get","type":"execute"}' '{"verb":"set","type":"source"}')
    single=$(printf '%s\n' "$data" | bu query-object group-by verb,type --format jsonl)
    assert_equal "$(printf '%s\n' "$data" | bu query-object group-by verb, type --format jsonl)" "$single"
    assert_equal "$(printf '%s\n' "$data" | bu query-object group-by verb , type --format jsonl)" "$single"
    assert_equal "$(printf '%s\n' "$data" | bu query-object group-by verb ,type --format jsonl)" "$single"
}

function test_query_object_agg_comma_multi_word_runtime { #@test
    local data single
    data=$(printf '%s\n' '{"verb":"get","hp":100}' '{"verb":"get","hp":200}' '{"verb":"set","hp":300}')
    single=$(printf '%s\n' "$data" | bu query-object group-by verb agg count,avg:hp select verb,count,avg_hp order-by verb)
    assert_equal "$(printf '%s\n' "$data" | bu query-object group-by verb agg count, avg:hp select verb,count,avg_hp order-by verb)" "$single"
    assert_equal "$(printf '%s\n' "$data" | bu query-object group-by verb agg count , avg:hp select verb,count,avg_hp order-by verb)" "$single"
}

function test_query_object_columns_comma_multi_word_runtime { #@test
    local data single
    data=$(printf '%s\n' '{"name":"a","type":"source"}' '{"name":"b","type":"execute"}')
    single=$(printf '%s\n' "$data" | bu query-object select name,type --format tsv --columns name,type)
    assert_equal "$(printf '%s\n' "$data" | bu query-object select name,type --format tsv --columns name, type)" "$single"
    assert_equal "$(printf '%s\n' "$data" | bu query-object select name,type --format tsv --columns name , type)" "$single"
}

function test_query_object_where_in_comma_multi_word_runtime { #@test
    local data single
    data=$(printf '%s\n' '{"name":"get-command","type":"source","verb":"get"}' '{"name":"set-module","type":"execute","verb":"set"}' '{"name":"gc","type":"alias","verb":"get"}')
    single=$(printf '%s\n' "$data" | bu query-object where type -in source,execute select name)
    assert_equal "$(printf '%s\n' "$data" | bu query-object where type -in source, execute select name)" "$single"
    assert_equal "$(printf '%s\n' "$data" | bu query-object where type -in source , execute select name)" "$single"
    # -notin mirrors -in
    single=$(printf '%s\n' "$data" | bu query-object where type -notin source,execute select name)
    assert_equal "$(printf '%s\n' "$data" | bu query-object where type -notin source, execute select name)" "$single"
    # A connector still terminates a multi-word value list.
    single=$(printf '%s\n' "$data" | bu query-object where type -in source,execute and verb -eq get select name)
    assert_equal "$(printf '%s\n' "$data" | bu query-object where type -in source, execute and verb -eq get select name)" "$single"
}

function test_query_object_select_comma_multi_word_completion { #@test
    local command_line_front_before_pipe="bu get-command | "
    bu_autocomplete_get_autocompletions bu query-object select name, ""
    assert_equal "${COMPREPLY[*]}" "verb noun namespace type definition synopsis fields stage input output requires_all requires_any module shadows shadowed_by"
    bu_autocomplete_get_autocompletions bu query-object select name , ""
    assert_equal "${COMPREPLY[*]}" "verb noun namespace type definition synopsis fields stage input output requires_all requires_any module shadows shadowed_by"
    bu_autocomplete_get_autocompletions bu query-object select name, ve
    assert_equal "${COMPREPLY[*]}" "verb"
    bu_autocomplete_get_autocompletions bu query-object select name ,ve
    assert_equal "${COMPREPLY[*]}" ",verb"
}

function test_query_object_group_by_comma_multi_word_completion { #@test
    local command_line_front_before_pipe="bu get-command | "
    bu_autocomplete_get_autocompletions bu query-object group-by verb, ""
    assert_equal "${COMPREPLY[*]}" "name noun namespace type definition synopsis fields stage input output requires_all requires_any module shadows shadowed_by"
    bu_autocomplete_get_autocompletions bu query-object group-by verb, na
    assert_equal "${COMPREPLY[*]}" "name namespace"
}

function test_query_object_columns_comma_multi_word_completion { #@test
    local command_line_front_before_pipe="bu get-command | "
    bu_autocomplete_get_autocompletions bu query-object --columns name, ""
    assert_equal "${COMPREPLY[*]}" "verb noun namespace type definition synopsis fields stage input output requires_all requires_any module shadows shadowed_by"
    bu_autocomplete_get_autocompletions bu query-object --columns name, ve
    assert_equal "${COMPREPLY[*]}" "verb"
}

function test_query_object_agg_comma_multi_word_completion { #@test
    local command_line_front_before_pipe="bu get-command | "
    bu_autocomplete_get_autocompletions bu query-object group-by verb agg cou
    assert_equal "${COMPREPLY[*]}" "count"
    bu_autocomplete_get_autocompletions bu query-object group-by verb agg count, av
    assert_equal "${COMPREPLY[*]}" "avg"
    bu_autocomplete_get_autocompletions bu query-object group-by verb agg count , av
    assert_equal "${COMPREPLY[*]}" "avg"
}

function test_query_object_where_in_comma_multi_word_completion { #@test
    local command_line_front_before_pipe="qo_value_producer | "
    qo_value_producer() {
        printf '%s\n' '{"type":"source"}' '{"type":"execute"}' '{"type":"alias"}'
    }
    bu_register_tab_execute "qo_value_producer"

    bu_autocomplete_get_autocompletions bu query-object where type -in source, ""
    assert_equal "${COMPREPLY[*]}" "alias execute"
    bu_autocomplete_get_autocompletions bu query-object where type -in source, ex
    assert_equal "${COMPREPLY[*]}" "execute"
    bu_autocomplete_get_autocompletions bu query-object where type -in source , ""
    assert_equal "${COMPREPLY[*]}" "alias execute"
    bu_autocomplete_get_autocompletions bu query-object where type -notin source, ex
    assert_equal "${COMPREPLY[*]}" "execute"
    bu_autocomplete_get_autocompletions bu query-object group-by verb --having type -in source, ex
    assert_equal "${COMPREPLY[*]}" "execute"
}

# ===========================================================================
# -like / -notlike bare-pattern substring semantics
# ===========================================================================

function test_like_bare_pattern_is_substring { #@test
    local out
    out=$(printf '%s\n' '{"name":"get-command"}' '{"name":"set-module"}' \
        | bu query-object where name -like command select name)
    assert_equal "$out" '{"name":"get-command"}'
}

function test_where_like_bare_pattern_is_substring { #@test
    local out
    out=$(printf '%s\n' '{"name":"get-command"}' '{"name":"set-module"}' \
        | bu where name -like command)
    assert_equal "$out" '{"name":"get-command"}'
}

function test_notlike_bare_pattern_is_complement { #@test
    local out
    out=$(printf '%s\n' '{"name":"get-command"}' '{"name":"set-module"}' '{"name":"command"}' \
        | bu query-object where name -notlike command select name)
    assert_equal "$out" '{"name":"set-module"}'
}

function test_like_explicit_glob_stays_anchored { #@test
    # "comm*" still means "starts with comm"
    local out
    out=$(printf '%s\n' '{"name":"get-command"}' '{"name":"command"}' \
        | bu where name -like 'comm*')
    assert_equal "$out" '{"name":"command"}'
}

function test_like_question_mark_is_wildcard { #@test
    # "get-?" is anchored with a single-char wildcard
    local out
    out=$(printf '%s\n' '{"name":"get-command"}' '{"name":"get-x"}' \
        | bu where name -like 'get-?')
    assert_equal "$out" '{"name":"get-x"}'
}

function test_query_object_translate_op_like_substring { #@test
    local out
    out=$(__bu_query_object_translate_op name -like command)
    assert_equal "$out" '.name | test("^.*command.*$")'
    out=$(__bu_query_object_translate_op name -like 'get-*')
    assert_equal "$out" '.name | test("^get-.*$")'
    out=$(__bu_query_object_translate_op name -like 'get-?')
    assert_equal "$out" '.name | test("^get-.$")'
    out=$(__bu_query_object_translate_op name -notlike command)
    assert_equal "$out" '.name | test("^.*command.*$") | not'
}

# ===========================================================================
# -eq/-ne/-gt/-lt/-ge/-le (scalar comparisons with numeric coercion)
# ===========================================================================

function test_query_object_translate_op_scalar_coercion { #@test
    local out
    # Numeric RHS coerces the field through `tonumber? // .`
    out=$(__bu_query_object_translate_op channel -eq 1108)
    assert_equal "$out" '(.channel | tonumber? // .) == 1108'
    out=$(__bu_query_object_translate_op count -gt 3)
    assert_equal "$out" '(.count | tonumber? // .) > 3'
    # String RHS is unchanged — coercion keys off the RHS literal's type
    out=$(__bu_query_object_translate_op type -eq source)
    assert_equal "$out" '.type == "source"'
    out=$(__bu_query_object_translate_op type -ne source)
    assert_equal "$out" '.type != "source"'
}

function test_where_eq_matches_numeric_string_field { #@test
    local out
    out=$(printf '%s\n' '{"channel":"1108"}' '{"channel":1108}' \
        | bu query-object where channel -eq 1108)
    assert_equal "$out" '{"channel":"1108"}
{"channel":1108}'
}

function test_where_in_matches_numeric_string_field { #@test
    local out
    out=$(printf '%s\n' '{"channel":"1108"}' '{"channel":1108}' '{"channel":"9999"}' \
        | bu query-object where channel -in 1108)
    assert_equal "$out" '{"channel":"1108"}
{"channel":1108}'
}

function test_where_notin_excludes_numeric_string_field { #@test
    local out
    out=$(printf '%s\n' '{"channel":"1108"}' '{"channel":1108}' '{"channel":"9999"}' \
        | bu query-object where channel -notin 1108 select channel)
    assert_equal "$out" '{"channel":"9999"}'
}

function test_where_string_equality_and_ne_still_work { #@test
    local out
    out=$(printf '%s\n' '{"type":"source"}' '{"type":"alias"}' \
        | bu query-object where type -eq source select type)
    assert_equal "$out" '{"type":"source"}'
    out=$(printf '%s\n' '{"type":"source"}' '{"type":"alias"}' \
        | bu query-object where type -ne source select type)
    assert_equal "$out" '{"type":"alias"}'
}

function test_where_gt_matches_numeric_string_field { #@test
    local out
    out=$(printf '%s\n' '{"n":"5"}' '{"n":2}' \
        | bu query-object where n -gt 3 select n)
    assert_equal "$out" '{"n":"5"}'
}

# ===========================================================================
# -in / -notin (set membership against a comma-separated list)
# ===========================================================================

function test_query_object_translate_op_in_notin { #@test
    local out
    out=$(__bu_query_object_translate_op type -in source,alias)
    assert_equal "$out" '.type | IN("source","alias")'
    out=$(__bu_query_object_translate_op type -notin source,alias)
    assert_equal "$out" '.type | IN("source","alias") | not'
    out=$(__bu_query_object_translate_op type -in source)
    assert_equal "$out" '.type | IN("source")'
    out=$(__bu_query_object_translate_op count -in 1,2,null)
    assert_equal "$out" '(.count | tonumber? // .) | IN(1,2,null)'
    out=$(__bu_query_object_translate_op type -in 'source,,alias,')
    assert_equal "$out" '.type | IN("source","alias")'
    run __bu_query_object_translate_op type -in ''
    assert_failure
    run __bu_query_object_translate_op type -in ','
    assert_failure
}

function test_query_object_in_membership { #@test
    local out
    out=$(printf '%s\n' '{"name":"a","type":"source"}' '{"name":"b","type":"alias"}' '{"name":"c","type":"function"}' \
        | bu query-object where type -in source,alias select name)
    assert_equal "$out" '{"name":"a"}
{"name":"b"}'
}

function test_query_object_notin_complement { #@test
    local out
    out=$(printf '%s\n' '{"name":"a","type":"source"}' '{"name":"b","type":"alias"}' '{"name":"c","type":"function"}' \
        | bu query-object where type -notin source,alias select name)
    assert_equal "$out" '{"name":"c"}'
}

function test_where_in_membership { #@test
    local out
    out=$(printf '%s\n' '{"name":"a","type":"source"}' '{"name":"b","type":"alias"}' '{"name":"c","type":"function"}' \
        | bu where type -in source,alias)
    assert_equal "$out" '{"name":"a","type":"source"}
{"name":"b","type":"alias"}'
}

function test_in_numeric_membership_end_to_end { #@test
    local out
    out=$(printf '%s\n' '{"count":1}' '{"count":2}' '{"count":3}' '{"count":null}' \
        | bu query-object where count -in 1,2,null select count)
    assert_equal "$out" '{"count":1}
{"count":2}
{"count":null}'
}

function test_in_chains_with_and_or { #@test
    local out
    out=$(printf '%s\n' '{"name":"a","type":"source"}' '{"name":"b","type":"alias"}' '{"name":"c","type":"function"}' \
        | bu query-object where type -in source,alias and name -eq a select name)
    assert_equal "$out" '{"name":"a"}'
}

# ===========================================================================
# grep (search a pattern across any field value)
# ===========================================================================

function test_query_object_grep_regex_any_field { #@test
    local out
    out=$(printf '%s\n' '{"name":"get-command","verb":"get"}' '{"name":"set-module","verb":"set"}' \
        | bu query-object grep '^get' select name)
    assert_equal "$out" '{"name":"get-command"}'
}

function test_query_object_grep_like_substring { #@test
    # bare pattern is a substring, searched across every field value
    local out
    out=$(printf '%s\n' '{"name":"get-command","verb":"get"}' '{"name":"set-module","verb":"set"}' \
        | bu query-object grep -like command select name)
    assert_equal "$out" '{"name":"get-command"}'
}

function test_query_object_grep_ilike_case_insensitive { #@test
    local out
    out=$(printf '%s\n' '{"name":"get-command"}' '{"name":"GET-MODULE"}' '{"name":"set-thing"}' \
        | bu query-object grep -ilike 'get-*' select name)
    assert_equal "$out" '{"name":"get-command"}
{"name":"GET-MODULE"}'
}

function test_query_object_grep_i_regex_case_insensitive { #@test
    local out
    out=$(printf '%s\n' '{"name":"get-command"}' '{"name":"GET-MODULE"}' '{"name":"set-thing"}' \
        | bu query-object grep -i '^get' select name)
    assert_equal "$out" '{"name":"get-command"}
{"name":"GET-MODULE"}'
}

function test_query_object_grep_matches_nonstring_value { #@test
    # numbers are stringified, so grep 42 matches {"count":42}
    local out
    out=$(printf '%s\n' '{"name":"a","count":42}' '{"name":"b","count":7}' \
        | bu query-object grep 42 select name)
    assert_equal "$out" '{"name":"a"}'
}

function test_query_object_grep_anded_with_where { #@test
    local out
    out=$(printf '%s\n' '{"name":"get-command","verb":"get"}' '{"name":"set-module","verb":"set"}' \
        | bu query-object grep command where verb -eq get select name)
    assert_equal "$out" '{"name":"get-command"}'
}

function test_query_object_translate_grep { #@test
    local out
    out=$(__bu_query_object_translate_grep regex '^get-')
    assert_equal "$out" '[.[] | tostring] | any(test("^get-"))'
    out=$(__bu_query_object_translate_grep iregex '^get-')
    assert_equal "$out" '[.[] | tostring] | any(test("^get-"; "i"))'
    out=$(__bu_query_object_translate_grep glob command)
    assert_equal "$out" '[.[] | tostring] | any(test("^.*command.*$"))'
    out=$(__bu_query_object_translate_grep glob 'get-*')
    assert_equal "$out" '[.[] | tostring] | any(test("^get-.*$"))'
    out=$(__bu_query_object_translate_grep iglob 'get-*')
    assert_equal "$out" '[.[] | tostring] | any(test("^get-.*$"; "i"))'
}

function test_e2e_query_object_grep_completion { #@test
    local command_line_front_before_pipe="bu get-command | "
    bu_autocomplete_get_autocompletions bu query-object grep ""
    assert_equal "${COMPREPLY[0]}" "Hint: Regex pattern (matches any field value)"
    bu_autocomplete_get_autocompletions bu query-object grep "-"
    assert_equal "${COMPREPLY[*]}" "-like -ilike -i"
    bu_autocomplete_get_autocompletions bu query-object grep -like ""
    assert_equal "${COMPREPLY[0]}" "Hint: Glob pattern (matches any field value)"
}

# ===========================================================================
# Value completion at the where/query value position (tab-execute opt-in)
# ===========================================================================

function test_where_value_completion_eq { #@test
    local command_line_front_before_pipe="bu get-command | "
    bu_autocomplete_get_autocompletions bu where type -eq ""
    assert_equal "${COMPREPLY[*]}" "alias execute source"
}

function test_query_object_value_completion_eq { #@test
    local command_line_front_before_pipe="bu get-command | "
    bu_autocomplete_get_autocompletions bu query-object where type -eq ""
    assert_equal "${COMPREPLY[*]}" "alias execute source"
}

# ===========================================================================
# query-object where/having value-position connector-jump + delimited -in
# ===========================================================================

function test_query_object_value_completion_cursor_on_value { #@test
    # Regression: a partial value that parses as a complete condition must
    # still complete the VALUE, not jump ahead to the and/or connector.
    local command_line_front_before_pipe="qo_value_producer | "
    qo_value_producer() {
        printf '%s\n' \
            '{"name":"get-command","type":"source","namespace":"bu"}' \
            '{"name":"get-module","type":"source","namespace":"bu"}' \
            '{"name":"set-module","type":"execute","namespace":"bu"}' \
            '{"name":"query-object","type":"alias","namespace":"bu"}'
    }
    bu_register_tab_execute "qo_value_producer"

    bu_autocomplete_get_autocompletions bu query-object --where name -eq get-comm
    assert_equal "${COMPREPLY[*]}" "get-command"
}

function test_query_object_value_completion_cursor_past_value_connectors { #@test
    # Cursor moved onto a new empty word past a complete value: connectors.
    local command_line_front_before_pipe="qo_value_producer | "
    qo_value_producer() {
        printf '%s\n' '{"name":"get-command","type":"source"}'
    }
    bu_register_tab_execute "qo_value_producer"

    bu_autocomplete_get_autocompletions bu query-object --where name -eq get-command ""
    assert_equal "${COMPREPLY[*]}" "and or"
}

function test_query_object_where_partial_connector_prefix { #@test
    # Regression: after a complete condition, a non-empty prefix of and/or at
    # the cursor is a connector-in-progress, not a clause keyword (a<TAB> must
    # offer "and", not "agg"; o<TAB> must offer "or").
    local command_line_front_before_pipe="qo_value_producer | "
    qo_value_producer() {
        printf '%s\n' '{"name":"get-command","type":"source"}'
    }
    bu_register_tab_execute "qo_value_producer"

    bu_autocomplete_get_autocompletions bu query-object --where name -eq get-command a
    assert_equal "${COMPREPLY[*]}" "and"
    bu_autocomplete_get_autocompletions bu query-object --where name -eq get-command o
    assert_equal "${COMPREPLY[*]}" "or"
    bu_autocomplete_get_autocompletions bu query-object --where name -eq get-command an
    assert_equal "${COMPREPLY[*]}" "and"
}

function test_query_object_where_partial_connector_bare_alias { #@test
    # The bare `where` alias takes the same --where path.
    local command_line_front_before_pipe="qo_value_producer | "
    qo_value_producer() {
        printf '%s\n' '{"name":"get-command","type":"source"}'
    }
    bu_register_tab_execute "qo_value_producer"

    bu_autocomplete_get_autocompletions bu where name -eq get-command a
    assert_equal "${COMPREPLY[*]}" "and"
}

function test_query_object_having_partial_connector_prefix { #@test
    # --having mirrors --where.
    local command_line_front_before_pipe="qo_value_producer | "
    qo_value_producer() {
        printf '%s\n' '{"name":"get-command","type":"source"}'
    }
    bu_register_tab_execute "qo_value_producer"

    bu_autocomplete_get_autocompletions bu query-object group-by verb --having name -eq get-command a
    assert_equal "${COMPREPLY[*]}" "and"
}

function test_query_object_value_completion_in_delimited { #@test
    # -in values complete comma-segment by comma-segment via --delimited.
    local command_line_front_before_pipe="qo_value_producer | "
    qo_value_producer() {
        printf '%s\n' \
            '{"name":"get-command","type":"source"}' \
            '{"name":"get-module","type":"source"}' \
            '{"name":"set-module","type":"execute"}'
    }
    bu_register_tab_execute "qo_value_producer"

    bu_autocomplete_get_autocompletions bu query-object --where name -in get-command,get-mod
    assert_equal "${COMPREPLY[*]}" "get-command,get-module"
}

function test_query_object_value_completion_in_excludes_used { #@test
    # Already-selected list members are excluded from the next segment.
    local command_line_front_before_pipe="qo_value_producer | "
    qo_value_producer() {
        printf '%s\n' '{"type":"source"}' '{"type":"execute"}' '{"type":"alias"}'
    }
    bu_register_tab_execute "qo_value_producer"

    bu_autocomplete_get_autocompletions bu query-object --where type -in source,
    assert_equal "${COMPREPLY[*]}" "source,alias source,execute"
}

function test_query_object_value_completion_after_connector { #@test
    # Same behavior for a condition after and/or inside one --where.
    local command_line_front_before_pipe="qo_value_producer | "
    qo_value_producer() {
        printf '%s\n' \
            '{"name":"get-command","namespace":"bu"}' \
            '{"name":"get-module","namespace":"bu"}' \
            '{"name":"set-module","namespace":"bu"}'
    }
    bu_register_tab_execute "qo_value_producer"

    bu_autocomplete_get_autocompletions bu query-object --where namespace -eq bu and name -in get-command,get-mod
    assert_equal "${COMPREPLY[*]}" "get-command,get-module"
}

function test_query_object_having_value_completion_matches_where { #@test
    # --having mirrors --where: cursor-on-value completes the value; -notin
    # uses --delimited and excludes already-used members.
    local command_line_front_before_pipe="qo_value_producer | "
    qo_value_producer() {
        printf '%s\n' \
            '{"name":"get-command","type":"source"}' \
            '{"name":"get-module","type":"source"}' \
            '{"name":"set-module","type":"execute"}'
    }
    bu_register_tab_execute "qo_value_producer"

    bu_autocomplete_get_autocompletions bu query-object group-by verb --having name -eq get-comm
    assert_equal "${COMPREPLY[*]}" "get-command"
    bu_autocomplete_get_autocompletions bu query-object group-by verb --having type -notin source,
    assert_equal "${COMPREPLY[*]}" "source,execute"
}

function test_value_completion_get_alias_root { #@test
    local command_line_front_before_pipe="bu get-alias | "
    bu_autocomplete_get_autocompletions bu where root -eq ""
    assert_equal "${COMPREPLY[*]}" "get-command query-object"
}

function test_value_completion_like_and_gt_never_probe { #@test
    local command_line_front_before_pipe="bu get-command | "
    # Pattern and ordered operators keep the plain static hint.
    bu_autocomplete_get_autocompletions bu where type -like ""
    assert_equal "${COMPREPLY[0]}" "Hint: Value for type -like"
    bu_autocomplete_get_autocompletions bu where type -gt ""
    assert_equal "${COMPREPLY[0]}" "Hint: Value for type -gt"
}

function test_value_completion_unregistered_producer_no_execute { #@test
    local countfile=$BATS_TEST_TMPDIR/tab-exec-none
    local command_line_front_before_pipe="noexec_producer | "
    noexec_producer() {
        echo x >> "$countfile"
        printf '%s\n' '{"type":"source"}'
    }

    # Not registered: resolver refuses, producer never runs.
    run __bu_out_complete_field_values type
    assert_failure
    assert [ ! -s "$countfile" ]

    # e2e: the value position falls back to the static hint only.
    bu_autocomplete_get_autocompletions bu where type -eq ""
    assert_equal "${COMPREPLY[0]}" "Hint: Value for type -eq"
}

function test_value_completion_single_execution_memo { #@test
    local countfile=$BATS_TEST_TMPDIR/tab-exec-count
    local command_line_front_before_pipe="tab_count_producer | "
    tab_count_producer() {
        echo x >> "$countfile"
        printf '%s\n' '{"type":"source","verb":"get"}' '{"type":"execute","verb":"set"}'
    }
    bu_register_tab_execute "tab_count_producer"

    __bu_out_complete_field_values type
    assert_equal "${BU_RET[*]}" "execute source"
    __bu_out_complete_field_values verb
    assert_equal "${BU_RET[*]}" "get set"
    __bu_out_complete_field_values type
    # One execution total across two fields and repeated tabs.
    assert_equal "$(wc -l < "$countfile")" 1
}

function test_value_completion_record_and_distinct_caps { #@test
    local command_line_front_before_pipe="many_producer | "
    many_producer() {
        local i
        for ((i = 0; i < 5000; i++)); do
            printf '{"id":%d}\n' "$i"
        done
    }
    bu_register_tab_execute "many_producer"

    __bu_out_complete_field_values id
    # Distinct cap: at most 1000 candidates for a high-cardinality column
    # (bounded by the 1000-row record memo).
    assert_equal "${#BU_RET[@]}" 1000
    # Record cap: the memo captured at most 1000 rows.
    local memo_lines
    memo_lines=$(grep -c '' <<<"${__BU_OUT_TAB_ROWS[many_producer]}")
    assert_equal "$memo_lines" 1000
}

function test_value_completion_tab_execute_header_fixture { #@test
    local tmpdir
    tmpdir=$(mktemp -d)
    cat > "$tmpdir/fixture-producer.sh" <<'EOF'
#!/usr/bin/env bash
# Dispatch: source
# Tab-Execute: true
printf '%s\n' '{"type":"alpha"}' '{"type":"beta"}'
EOF
    chmod 644 "$tmpdir/fixture-producer.sh"

    BU_COMMANDS[fixture-producer]="$tmpdir/fixture-producer.sh"

    # The header registers the producer for tab-execute without any central edit.
    local command_line_front_before_pipe="bu fixture-producer | "
    __bu_out_complete_field_values type
    assert_equal "${BU_RET[*]}" "alpha beta"

    rm -rf "$tmpdir"
}

# ===========================================================================
# Field completion at the post-pipe position (tab-execute-field opt-in)
# ===========================================================================

function test_field_completion_tab_execute_field_registry { #@test
    # A producer with no # Fields: header and no registry entry discovers
    # its field names from the live first record.
    local command_line_front_before_pipe="dyn_field_producer | "
    dyn_field_producer() {
        printf '%s\n' '{"alpha":1,"beta":"x","gamma":true}'
    }
    bu_register_tab_execute_field "dyn_field_producer"

    __bu_out_complete_pipeline_fields ""
    assert_equal "${BU_RET[*]}" "alpha beta gamma"
}

function test_field_completion_shares_capture_with_value_gate { #@test
    local countfile=$BATS_TEST_TMPDIR/tab-exec-field-count
    local command_line_front_before_pipe="dual_gate_producer | "
    dual_gate_producer() {
        echo x >> "$countfile"
        printf '%s\n' '{"alpha":1,"beta":"z"}' '{"alpha":2,"beta":"y"}'
    }
    bu_register_tab_execute_field "dual_gate_producer"
    bu_register_tab_execute "dual_gate_producer"

    __bu_out_complete_pipeline_fields ""
    assert_equal "${BU_RET[*]}" "alpha beta"
    __bu_out_complete_field_values alpha
    assert_equal "${BU_RET[*]}" "1 2"
    __bu_out_complete_field_values beta
    assert_equal "${BU_RET[*]}" "y z"
    # One execution total across field-name and field-value positions.
    assert_equal "$(wc -l < "$countfile")" 1
}

function test_field_completion_value_gate_only_no_execute { #@test
    local countfile=$BATS_TEST_TMPDIR/tab-exec-valonly
    local command_line_front_before_pipe="value_only_producer | "
    value_only_producer() {
        echo x >> "$countfile"
        printf '%s\n' '{"alpha":1}'
    }
    bu_register_tab_execute "value_only_producer"

    # The value gate does not authorize the field position.
    run __bu_out_complete_pipeline_fields ""
    assert_failure
    assert [ ! -s "$countfile" ]
}

function test_field_completion_field_gate_only_no_value { #@test
    local countfile=$BATS_TEST_TMPDIR/tab-exec-fieldonly
    local command_line_front_before_pipe="field_only_producer | "
    field_only_producer() {
        echo x >> "$countfile"
        printf '%s\n' '{"alpha":1}'
    }
    bu_register_tab_execute_field "field_only_producer"

    # The field gate does not authorize the value position.
    run __bu_out_complete_field_values alpha
    assert_failure
    assert [ ! -s "$countfile" ]
}

function test_field_completion_unregistered_no_execute { #@test
    local countfile=$BATS_TEST_TMPDIR/tab-exec-field-none
    local command_line_front_before_pipe="nofield_producer | "
    nofield_producer() {
        echo x >> "$countfile"
        printf '%s\n' '{"alpha":1}'
    }

    run __bu_out_complete_pipeline_fields ""
    assert_failure
    assert [ ! -s "$countfile" ]
}

function test_field_completion_tab_execute_field_header_fixture { #@test
    local tmpdir
    tmpdir=$(mktemp -d)
    cat > "$tmpdir/fixture-field-producer.sh" <<'EOF'
#!/usr/bin/env bash
# Dispatch: source
# Tab-Execute-Field: true
printf '%s\n' '{"colA":"x","colB":"y"}'
EOF
    chmod 644 "$tmpdir/fixture-field-producer.sh"

    BU_COMMANDS[fixture-field-producer]="$tmpdir/fixture-field-producer.sh"

    # The header registers the producer for field discovery without any central edit.
    local command_line_front_before_pipe="bu fixture-field-producer | "
    __bu_out_complete_pipeline_fields ""
    assert_equal "${BU_RET[*]}" "colA colB"

    # The field gate alone must not enable value-position execution.
    run __bu_out_complete_field_values colA
    assert_failure

    rm -rf "$tmpdir"
}

# ===========================================================================
# Alias merging in option completion (--select, select, SELECT are one row)
# ===========================================================================

function test_alias_merged_single_row { #@test
    # --select/select merge into one row (the first form); no bare select row
    bu_autocomplete_get_autocompletions bu query-object ""
    local count=0 candidate
    for candidate in "${COMPREPLY[@]}"
    do
        [[ "$candidate" == "--select" || "$candidate" == "select" ]] && ((count++))
    done
    assert_equal "$count" 1
    assert_equal "${COMPREPLY[0]}" "--select"
}

function test_alias_merged_metadata_aka { #@test
    # The merged row's metadata lists the alternative forms
    bu_autocomplete_get_autocompletions bu query-object ""
    assert_regex "${BU_COMPREPLY_METADATA[*]}" 'aka select'
    assert_regex "${BU_COMPREPLY_METADATA[*]}" 'aka order-by'
}

function test_alias_display_follows_typed_prefix { #@test
    # Typing the bare keyword's prefix switches the row to that form so the
    # compgen prefix filter keeps it
    bu_autocomplete_get_autocompletions bu query-object se
    assert_equal "${COMPREPLY[*]}" "select"
}

function test_alias_excluded_after_any_form_used { #@test
    # Using the bare form excludes the whole alias group
    bu_autocomplete_get_autocompletions bu query-object select name ""
    local candidate
    for candidate in "${COMPREPLY[@]}"
    do
        refute_equal "$candidate" "--select"
        refute_equal "$candidate" "select"
    done
    # Other clauses are still offered
    local has_where=false
    for candidate in "${COMPREPLY[@]}"
    do
        [[ "$candidate" == "--where" ]] && has_where=true
    done
    assert_equal "$has_where" true
}

function test_alias_non_alias_pairs_not_merged { #@test
    # -v and --verb normalize differently: both rows remain
    bu_autocomplete_get_autocompletions bu get-command ""
    local has_short=false has_long=false candidate
    for candidate in "${COMPREPLY[@]}"
    do
        [[ "$candidate" == "-v" ]] && has_short=true
        [[ "$candidate" == "--verb" ]] && has_long=true
    done
    assert_equal "$has_short" true
    assert_equal "$has_long" true
}

# ===========================================================================
# bu_out_group_by / query-object group-by, agg, having
# ===========================================================================

function test_bu_out_group_by_basic_count { #@test
    local out
    out=$(printf '%s\n' '{"v":"a"}' '{"v":"b"}' '{"v":"a"}' | bu_out_group_by --keys v --agg count)
    assert_equal "$out" '{"v":"a","count":2}
{"v":"b","count":1}'
}

function test_bu_out_group_by_numeric_aggregates { #@test
    local out
    out=$(printf '%s\n' '{"t":"a","x":10}' '{"t":"a","x":20}' '{"t":"b","x":5}' \
        | bu_out_group_by --keys t --agg avg_x=avg:x,total=sum:x,min:x,max:x)
    assert_equal "$out" '{"t":"a","avg_x":15,"total":30,"min_x":10,"max_x":20}
{"t":"b","avg_x":5,"total":5,"min_x":5,"max_x":5}'
}

function test_bu_out_group_by_first_last_collect { #@test
    local out
    out=$(printf '%s\n' '{"t":"a","x":1}' '{"t":"a","x":2}' | bu_out_group_by --keys t --agg first:x,last:x,collect:x)
    assert_equal "$out" '{"t":"a","first_x":1,"last_x":2,"collect_x":[1,2]}'
}

function test_bu_out_group_by_multi_key { #@test
    local out
    out=$(printf '%s\n' '{"a":1,"b":1}' '{"a":1,"b":2}' '{"a":1,"b":1}' | bu_out_group_by --keys a,b --agg count)
    assert_equal "$out" '{"a":1,"b":1,"count":2}
{"a":1,"b":2,"count":1}'
}

function test_bu_out_group_by_distinct { #@test
    # No agg: emits distinct key combinations
    local out
    out=$(printf '%s\n' '{"v":"a"}' '{"v":"a"}' '{"v":"b"}' | bu_out_group_by --keys v)
    assert_equal "$out" '{"v":"a"}
{"v":"b"}'
}

function test_bu_out_group_by_missing_key_null_group { #@test
    # Records missing the key field group together under null
    local out
    out=$(printf '%s\n' '{"v":"a"}' '{"w":1}' | bu_out_group_by --keys v --agg count)
    assert_equal "$out" '{"v":null,"count":1}
{"v":"a","count":1}'
}

function test_bu_out_group_by_empty_input { #@test
    local out
    out=$(printf '' | bu_out_group_by --keys v --agg count)
    assert_equal "$out" ''
}

function test_bu_out_group_by_unknown_func { #@test
    run bu_out_group_by --keys v --agg bogus:x </dev/null
    assert_failure
}

function test_bu_out_group_by_missing_field { #@test
    run bu_out_group_by --keys v --agg avg </dev/null
    assert_failure
}

function test_bu_out_group_by_requires_keys { #@test
    run bu_out_group_by --agg count </dev/null
    assert_failure
}

function test_bu_query_object_group_by { #@test
    local out
    out=$(BU_MODULE_LIST="a:1.0.0:/x;b:2.0.0:/y;c:1.0.0:/z" bu get-module \
        | bu query-object group-by version agg count)
    assert_equal "$out" '{"version":"1.0.0","count":2}
{"version":"2.0.0","count":1}'
}

function test_bu_query_object_having { #@test
    local out
    out=$(BU_MODULE_LIST="a:1.0.0:/x;b:2.0.0:/y;c:1.0.0:/z" bu get-module \
        | bu query-object group-by version agg count having '.count > 1')
    assert_equal "$out" '{"version":"1.0.0","count":2}'
}

function test_bu_query_object_group_rename_order_alias { #@test
    # Full arc: group -> agg -> select renames -> order-by alias desc
    local out
    out=$(BU_MODULE_LIST="a:1.0.0:/x;b:2.0.0:/y;c:1.0.0:/z" bu get-module \
        | bu query-object group-by version agg count select ver=version,c=count order-by c desc)
    assert_equal "$out" '{"ver":"1.0.0","c":2}
{"ver":"2.0.0","c":1}'
}

function test_bu_query_object_agg_requires_group_by { #@test
    run bu query-object agg count </dev/null
    assert_failure
}

function test_bu_query_object_from_file { #@test
    # --from reads records from a file instead of stdin
    local input=$BATS_TEST_TMPDIR/query_input.jsonl
    printf '%s\n' '{"name":"b","n":2}' '{"name":"a","n":1}' '{"name":"c","n":3}' > "$input"
    local out
    out=$(bu query-object from "$input" select name order-by name --format tsv --columns name </dev/null)
    assert_equal "$out" $'a\nb\nc'
}

function test_bu_query_object_from_relative_path { #@test
    # Relative --from resolves against the invocation directory
    local input=$BATS_TEST_TMPDIR/query_input.jsonl
    printf '%s\n' '{"name":"a"}' > "$input"
    local out
    out=$(cd "$BATS_TEST_TMPDIR" && bu query-object from query_input.jsonl </dev/null)
    assert_equal "$out" '{"name":"a"}'
}

function test_bu_query_object_from_missing_file { #@test
    run bu query-object from "$BATS_TEST_TMPDIR"/nope.jsonl </dev/null
    assert_failure
}

function test_bu_query_object_from_directory { #@test
    run bu query-object from "$BATS_TEST_TMPDIR" </dev/null
    assert_failure
}

function test_bu_query_object_outfile { #@test
    # --outfile writes results to a file instead of stdout
    local output=$BATS_TEST_TMPDIR/query_output.jsonl
    local out
    out=$(bu get-command | bu query-object where '.name == "query-object" or .name == "get-command"' select name order-by name outfile "$output")
    assert_equal "$out" ''
    assert_equal "$(cat "$output")" '{"name":"get-command"}
{"name":"query-object"}'
}

function test_bu_query_object_from_and_outfile { #@test
    # File in, file out: stdin/stdout untouched
    local input=$BATS_TEST_TMPDIR/query_input.jsonl
    local output=$BATS_TEST_TMPDIR/query_output.jsonl
    printf '%s\n' '{"n":2}' '{"n":1}' > "$input"
    bu query-object from "$input" order-by n outfile "$output" </dev/null
    assert_equal "$(cat "$output")" '{"n":1}
{"n":2}'
}

function test_bu_query_object_outfile_bad_directory { #@test
    run bu query-object outfile "$BATS_TEST_TMPDIR"/no_such_dir/out.jsonl </dev/null
    assert_failure
}

function test_e2e_query_object_from_completion { #@test
    # from/outfile values complete filenames
    touch "$BATS_TEST_TMPDIR"/alpha.jsonl "$BATS_TEST_TMPDIR"/beta.jsonl
    cd "$BATS_TEST_TMPDIR"
    bu_autocomplete_get_autocompletions bu query-object from ""
    assert_equal "${COMPREPLY[*]}" "alpha.jsonl beta.jsonl"
    bu_autocomplete_get_autocompletions bu query-object outfile b
    assert_equal "${COMPREPLY[*]}" "beta.jsonl"
}

function test_e2e_query_object_group_by_completion { #@test
    local command_line_front_before_pipe="bu get-command | "
    bu_autocomplete_get_autocompletions bu query-object group-by ""
    assert_equal "${COMPREPLY[*]}" "name verb noun namespace type definition synopsis fields stage input output requires_all requires_any module shadows shadowed_by"
}

# ===========================================================================
# bu_out_distinct / query-object distinct / bu distinct-object
# ===========================================================================

function test_bu_out_distinct_order_preserved { #@test
    # First occurrence wins, original order kept (unlike group-by, which sorts)
    local out
    out=$(printf '%s\n' '{"a":3}' '{"a":1}' '{"a":3}' | bu_out_distinct)
    assert_equal "$out" '{"a":3}
{"a":1}'
}

function test_bu_out_distinct_key_order_canonicalized { #@test
    # {"a":1,"b":2} equals {"b":2,"a":1}
    local out
    out=$(printf '%s\n' '{"a":1,"b":2}' '{"b":2,"a":1}' '{"a":3}' | bu_out_distinct)
    assert_equal "$out" '{"a":1,"b":2}
{"a":3}'
}

function test_bu_out_distinct_empty_input { #@test
    local out
    out=$(printf '' | bu_out_distinct)
    assert_equal "$out" ''
}

function test_bu_query_object_select_distinct { #@test
    # SELECT DISTINCT: project then dedupe whole records
    local out
    out=$(BU_MODULE_LIST="a:1.0.0:/x;b:2.0.0:/y;c:1.0.0:/z" bu get-module \
        | bu query-object select version distinct)
    assert_equal "$out" '{"version":"1.0.0"}
{"version":"2.0.0"}'
}

function test_bu_query_object_distinct_order_by { #@test
    local out
    out=$(BU_MODULE_LIST="b:2.0.0:/y;a:1.0.0:/x;c:1.0.0:/z" bu get-module \
        | bu query-object select version distinct order-by version desc)
    assert_equal "$out" '{"version":"2.0.0"}
{"version":"1.0.0"}'
}

function test_bu_distinct_object_cmdlet { #@test
    local out
    out=$(BU_MODULE_LIST="a:1.0.0:/x;b:2.0.0:/y;c:1.0.0:/z" bu get-module \
        | bu select version | bu distinct-object)
    assert_equal "$out" '{"version":"1.0.0"}
{"version":"2.0.0"}'
}

function test_bu_distinct_object_metadata { #@test
    local out def
    out=$(bu get-command | jq -c 'select(.name == "distinct-object")')
    def=$(printf '%s' "$out" | jq -r .definition)
    [[ -f "$def" ]]
    [[ "$def" == */bu-distinct-object.sh ]]
    assert_equal "$(printf '%s' "$out" | jq -c 'del(.definition, .shadows, .shadowed_by)')" '{"name":"distinct-object","verb":"distinct","noun":"object","namespace":"bu","type":"source","synopsis":"Remove duplicate records from a JSONL stream","fields":"","stage":"passthrough","input":"jsonl","output":"jsonl","requires_all":"","requires_any":"","module":"bu"}'
}

# ===========================================================================
# BU_TABLE_PAGER
# ===========================================================================

function test_bu_table_pager_piped_noop { #@test
    # When stdout is a pipe (not a TTY), BU_TABLE_PAGER must be ignored.
    # We use a pager that would transform the output, and verify it didn't run.
    local out
    out=$(printf '{"key":"val"}\n' | BU_TABLE_PAGER="sed s/.*/PAGED/" bu_format_table)
    # Without paging: a table with header, separator, and the value row
    [[ "$out" == *key* ]]
    [[ "$out" == *val* ]]
    # The pager did NOT run
    [[ "$out" != *PAGED* ]]
}

function test_bu_table_pager_preset_piped_noop { #@test
    # preset:less with a piped stdout must still be ignored (same as above).
    local out
    out=$(printf '{"key":"val"}\n' | BU_TABLE_PAGER="preset:less" bu_format_table)
    [[ "$out" == *key* ]]
    [[ "$out" == *val* ]]
}

function test_bu_table_pager_cat_equivalent { #@test
    # Setting BU_TABLE_PAGER to cat produces the same output as no pager,
    # confirming the pipeline is constructed correctly.
    local out no_pager_out
    out=$(printf '{"name":"test"}\n' | BU_TABLE_PAGER=cat bu_format_table)
    no_pager_out=$(printf '{"name":"test"}\n' | BU_TABLE_PAGER= bu_format_table)
    assert_equal "$out" "$no_pager_out"
}

function test_bu_table_pager_preset_on_terminal { #@test
    # When stdout is a terminal and BU_TABLE_PAGER=preset:less, output must
    # pass through the resolved preset (less -R).  We use sed as a marker
    # pager via a custom preset registered at runtime.
    if ! command -v script &>/dev/null; then
        skip "script(1) not available"
    fi
    local helper=$BATS_TEST_TMPDIR/pager_preset_pty.sh
    cat > "$helper" <<'SCRIPT_EOF'
source "$HELPER_DIR/../bu_entrypoint.sh" >/dev/null 2>&1
bu_register_table_pager_preset "marker" "sed s/^/PAGED:/"
export BU_TABLE_PAGER="preset:marker"
printf '{"name":"test"}\n' | bu_format_table
SCRIPT_EOF
    local out
    out=$(HELPER_DIR="$DIR" script -qec "bash $helper" /dev/null </dev/null | tr -d '\r\000\016\017')
    # The sed pager should have prepended "PAGED:" to every line
    [[ "$out" == *PAGED:* ]]
}

function test_bu_table_pager_custom_on_terminal { #@test
    # A bare command (no preset: prefix) is used verbatim.
    if ! command -v script &>/dev/null; then
        skip "script(1) not available"
    fi
    local helper=$BATS_TEST_TMPDIR/pager_custom_pty.sh
    cat > "$helper" <<'SCRIPT_EOF'
source "$HELPER_DIR/../bu_entrypoint.sh" >/dev/null 2>&1
export BU_TABLE_PAGER="sed s/^/CUSTOM:/"
printf '{"name":"test"}\n' | bu_format_table
SCRIPT_EOF
    local out
    out=$(HELPER_DIR="$DIR" script -qec "bash $helper" /dev/null </dev/null | tr -d '\r\000\016\017')
    [[ "$out" == *CUSTOM:* ]]
}

function test_bu_table_pager_preset_never { #@test
    # preset:never maps to cat — no paging transformation even on a terminal.
    if ! command -v script &>/dev/null; then
        skip "script(1) not available"
    fi
    local helper=$BATS_TEST_TMPDIR/pager_never_pty.sh
    cat > "$helper" <<'SCRIPT_EOF'
source "$HELPER_DIR/../bu_entrypoint.sh" >/dev/null 2>&1
export BU_TABLE_PAGER="preset:never"
printf '{"name":"test"}\n' | bu_format_table
SCRIPT_EOF
    local out
    out=$(HELPER_DIR="$DIR" script -qec "bash $helper" /dev/null </dev/null | tr -d '\r\000\016\017')
    # Table should render normally (header, separator, data)
    [[ "$out" == *name* ]]
    [[ "$out" == *test* ]]
    # No pager marker
    [[ "$out" != *PAGED:* ]]
}

function test_bu_table_pager_register_preset { #@test
    # bu_register_table_pager_preset extends the presets at runtime.
    bu_register_table_pager_preset "my-pager" "my-custom-pager --flag"
    assert_equal "${__BU_TABLE_PAGER_PRESETS[my-pager]}" "my-custom-pager --flag"
}

# ===========================================================================
# transform / standalone stage effects
# ===========================================================================

function test_transform_effect_io { #@test
    local in= out=
    __bu_out_effect_io transform stop-thing in out
    assert_equal "$in" jsonl
    assert_equal "$out" jsonl
}

function test_standalone_effect_io { #@test
    local in= out=
    __bu_out_effect_io standalone some-cmd in out
    assert_equal "$in" none
    assert_equal "$out" none
}

function test_transform_multi_stage_fields { #@test
    # A transform's output schema is its own # Fields: header, replacing the
    # upstream fields; fallback is the input fields when undeclared.
    local tmpdir
    tmpdir=$(mktemp -d)
    cat > "$tmpdir/bu-prod-things.sh" <<'EOF'
#!/usr/bin/env bash
# Dispatch: source
# Pipeline: producer
# Fields: thing_id size owner
function __bu_bu_prod_things_main() { :; }
EOF
    cat > "$tmpdir/bu-stop-thing.sh" <<'EOF'
#!/usr/bin/env bash
# Dispatch: source
# Pipeline: transform
# Requires-All: thing_id
# Fields: thing_id action result
function __bu_bu_stop_thing_main() { :; }
EOF
    bu_preinit_register_user_defined_subcommand_file "$tmpdir/bu-prod-things.sh" prod-things source
    bu_preinit_register_user_defined_subcommand_file "$tmpdir/bu-stop-thing.sh" stop-thing source

    local -a fields=()
    __bu_out_analyze_pipeline "bu prod-things | bu stop-thing" fields
    assert_equal "${fields[*]}" "thing_id action result"

    # Downstream validation now runs against the transform's result schema.
    __bu_out_validate_pipeline "bu prod-things | bu stop-thing | bu sort size"
    assert_equal "${BU_RET[*]}" "size"
    __bu_out_validate_pipeline "bu prod-things | bu stop-thing | bu sort action"
    assert_equal "${BU_RET[*]}" ""

    rm -rf "$tmpdir"
}

function test_transform_post_pipe_completion { #@test
    # After a producer emitting thing_id, a transform requiring thing_id is
    # offered; after one that doesn't emit it, the transform is hidden.
    local tmpdir
    tmpdir=$(mktemp -d)
    cat > "$tmpdir/bu-prod-things.sh" <<'EOF'
#!/usr/bin/env bash
# Dispatch: source
# Pipeline: producer
# Fields: thing_id size owner
function __bu_bu_prod_things_main() { :; }
EOF
    cat > "$tmpdir/bu-prod-other.sh" <<'EOF'
#!/usr/bin/env bash
# Dispatch: source
# Pipeline: producer
# Fields: name version
function __bu_bu_prod_other_main() { :; }
EOF
    cat > "$tmpdir/bu-stop-thing.sh" <<'EOF'
#!/usr/bin/env bash
# Dispatch: source
# Pipeline: transform
# Requires-All: thing_id
# Fields: thing_id action result
function __bu_bu_stop_thing_main() { :; }
EOF
    bu_preinit_register_user_defined_subcommand_file "$tmpdir/bu-prod-things.sh" prod-things source
    bu_preinit_register_user_defined_subcommand_file "$tmpdir/bu-prod-other.sh" prod-other source
    bu_preinit_register_user_defined_subcommand_file "$tmpdir/bu-stop-thing.sh" stop-thing source

    local command_line_front_before_pipe="bu prod-things | "
    bu_autocomplete_get_autocompletions bu ""
    assert_regex " ${COMPREPLY[*]} " ' stop-thing '

    command_line_front_before_pipe="bu prod-other | "
    bu_autocomplete_get_autocompletions bu ""
    refute_regex " ${COMPREPLY[*]} " ' stop-thing '

    rm -rf "$tmpdir"
}

function test_standalone_completion_positions { #@test
    # A standalone command is offered at the bare command position but hidden
    # after a pipe (its none input is a positive mismatch with any upstream).
    local tmpdir
    tmpdir=$(mktemp -d)
    cat > "$tmpdir/bu-standalone-thing.sh" <<'EOF'
#!/usr/bin/env bash
# Dispatch: source
# Pipeline: standalone
function __bu_bu_standalone_thing_main() { :; }
EOF
    bu_preinit_register_user_defined_subcommand_file "$tmpdir/bu-standalone-thing.sh" standalone-thing source

    bu_autocomplete_get_autocompletions bu ""
    assert_regex " ${COMPREPLY[*]} " ' standalone-thing '

    local command_line_front_before_pipe="bu get-command | "
    bu_autocomplete_get_autocompletions bu ""
    refute_regex " ${COMPREPLY[*]} " ' standalone-thing '

    rm -rf "$tmpdir"
}

# ===========================================================================
# Satisfied contract fields in post-pipe completion metadata
# ===========================================================================

function test_pipe_match_fields_metadata { #@test
    local tmpdir
    tmpdir=$(mktemp -d)
    cat > "$tmpdir/bu-prod-gadgets.sh" <<'EOF'
#!/usr/bin/env bash
# Dispatch: source
# Pipeline: producer
# Fields: gadget_id owner
function __bu_bu_prod_gadgets_main() { :; }
EOF
    cat > "$tmpdir/bu-remove-gadget.sh" <<'EOF'
#!/usr/bin/env bash
# Dispatch: source
# Pipeline: transform
# Requires-All: gadget_id
# Fields: gadget_id action result
function __bu_bu_remove_gadget_main() { :; }
EOF
    bu_preinit_register_user_defined_subcommand_file "$tmpdir/bu-prod-gadgets.sh" prod-gadgets source
    bu_preinit_register_user_defined_subcommand_file "$tmpdir/bu-remove-gadget.sh" remove-gadget source

    local command_line_front_before_pipe="bu prod-gadgets | "
    bu_autocomplete_get_autocompletions --accept-ansi-colors bu ""

    local i meta=
    for (( i = 0; i < ${#COMPREPLY[@]}; i++ ))
    do
        if [[ "${COMPREPLY[i]}" == *remove-gadget* ]]
        then
            meta=${BU_COMPREPLY_METADATA[i]}
        fi
    done
    assert_regex "$meta" '\(gadget_id\)'

    # A contract-less survivor (format-table) shows no field tag.
    local ft_meta=
    for (( i = 0; i < ${#COMPREPLY[@]}; i++ ))
    do
        if [[ "${COMPREPLY[i]}" == *format-table* ]]
        then
            ft_meta=${BU_COMPREPLY_METADATA[i]}
        fi
    done
    refute_regex "$ft_meta" '\([a-z_]'

    rm -rf "$tmpdir"
}

# ===========================================================================
# Scan-time pipeline-contract warnings
# ===========================================================================

function test_scan_warns_uncontracted_aggregated { #@test
    local tmpdir
    tmpdir=$(mktemp -d)
    cat > "$tmpdir/uncontracted-a.sh" <<'EOF'
#!/usr/bin/env bash
# Dispatch: source
function __bu_uncontracted_a_main() { :; }
EOF
    cat > "$tmpdir/uncontracted-b.sh" <<'EOF'
#!/usr/bin/env bash
# Dispatch: source
function __bu_uncontracted_b_main() { :; }
EOF
    cat > "$tmpdir/contracted-c.sh" <<'EOF'
#!/usr/bin/env bash
# Dispatch: source
# Pipeline: producer
# Fields: a b
function __bu_contracted_c_main() { :; }
EOF
    bu_preinit_register_user_defined_subcommand_dir "$tmpdir"

    local out
    out=$(BU_COMMAND_COMPAT_DEFERRED=true BU_PIPELINE_CONTRACT_WARN=true __bu_init_env_commands 2>&1 >/dev/null)
    # Exactly one warning line names both uncontracted commands together.
    local count
    count=$(printf '%s' "$out" | grep -F 'have no pipeline contract' | grep -F 'uncontracted-a' | grep -F 'uncontracted-b' | wc -l)
    assert_equal "$count" "1"
    refute_regex "$out" 'contracted-c'

    rm -rf "$tmpdir"
}

function test_scan_stage_effect_registration_covers { #@test
    local tmpdir
    tmpdir=$(mktemp -d)
    cat > "$tmpdir/effect-cmd.sh" <<'EOF'
#!/usr/bin/env bash
# Dispatch: source
function __bu_effect_cmd_main() { :; }
EOF
    bu_preinit_register_user_defined_subcommand_dir "$tmpdir"
    bu_register_stage_effect "bu effect-cmd" producer

    local out
    out=$(BU_COMMAND_COMPAT_DEFERRED=true BU_PIPELINE_CONTRACT_WARN=true __bu_init_env_commands 2>&1 >/dev/null)
    refute_regex "$out" 'effect-cmd'

    rm -rf "$tmpdir"
}

function test_scan_warn_silenced_by_knob { #@test
    local tmpdir
    tmpdir=$(mktemp -d)
    cat > "$tmpdir/uncontracted-a.sh" <<'EOF'
#!/usr/bin/env bash
# Dispatch: source
function __bu_uncontracted_a_main() { :; }
EOF
    bu_preinit_register_user_defined_subcommand_dir "$tmpdir"

    local out
    out=$(BU_COMMAND_COMPAT_DEFERRED=true BU_PIPELINE_CONTRACT_WARN=false __bu_init_env_commands 2>&1 >/dev/null)
    refute_regex "$out" 'uncontracted-a'

    rm -rf "$tmpdir"
}

function test_scan_warns_missing_field_contract { #@test
    local tmpdir
    tmpdir=$(mktemp -d)
    cat > "$tmpdir/reqless-transform.sh" <<'EOF'
#!/usr/bin/env bash
# Dispatch: source
# Pipeline: transform
# Fields: a b
function __bu_reqless_transform_main() { :; }
EOF
    cat > "$tmpdir/reqless-consume.sh" <<'EOF'
#!/usr/bin/env bash
# Dispatch: source
# Pipeline: consume
function __bu_reqless_consume_main() { :; }
EOF
    cat > "$tmpdir/contracted-transform.sh" <<'EOF'
#!/usr/bin/env bash
# Dispatch: source
# Pipeline: transform
# Requires-All: x
# Fields: a b
function __bu_contracted_transform_main() { :; }
EOF
    cat > "$tmpdir/query-stage.sh" <<'EOF'
#!/usr/bin/env bash
# Dispatch: source
# Pipeline: query
function __bu_query_stage_main() { :; }
EOF
    bu_preinit_register_user_defined_subcommand_dir "$tmpdir"

    local out
    out=$(BU_COMMAND_COMPAT_DEFERRED=true BU_PIPELINE_CONTRACT_WARN=true __bu_init_env_commands 2>&1 >/dev/null)
    local count
    count=$(printf '%s' "$out" | grep -F 'missing a field contract' | grep -F 'reqless-transform' | grep -F 'reqless-consume' | wc -l)
    assert_equal "$count" "1"
    refute_regex "$out" 'contracted-transform'
    refute_regex "$out" 'query-stage'

    rm -rf "$tmpdir"
}
