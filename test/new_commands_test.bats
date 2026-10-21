#!/usr/bin/env -S bats --jobs 16

# Unit tests for the PowerShell-style commands added in the "expansion" batch:
# pipeline cmdlets (get-member, foreach-object, measure-object, group-object,
# tee-object, compare-object, convert-from-json/csv, convert-to-csv, out-file),
# convert-from-* parsers, base64, filesystem item commands, and the bash
# builtin wrappers (get/set-shell-option, get/set-shopt-option, get-variable,
# get-builtin, get-completion, get-resource-limit, get-umask, get-trap,
# get/push/pop-location, get-location-stack, get-shell-alias, get-alias, get-job).
#
# All tests are TTY-independent: stdout inside $( ) / run is a pipe, so
# `bu out` auto-dispatch deterministically resolves to jsonl.
#
# Mutating commands (set-shell-option, push-location, umask, trap, alias)
# are exercised inside $( ) command substitution — a forked subshell that
# inherits the bu functions but cannot leak state into the test runner.

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
# bu get-member
# ===========================================================================

function test_bu_get_member_basic { #@test
    local out
    out=$(printf '{"a":1,"b":"x"}\n{"a":2}\n' | bu get-member)
    assert_equal "$out" '{"name":"a","types":"number","count":2,"null_count":0}
{"name":"b","types":"string","count":1,"null_count":0}'
}

function test_bu_get_member_empty_stream { #@test
    local out
    out=$(printf '' | bu get-member)
    assert_equal "$out" ""
}

function test_bu_get_member_null_count { #@test
    local out
    out=$(printf '{"a":null}\n{"a":1}\n' | bu get-member)
    assert_equal "$out" '{"name":"a","types":"null|number","count":2,"null_count":1}'
}

# ===========================================================================
# bu foreach-object
# ===========================================================================

function test_bu_foreach_object_adds_field { #@test
    local out
    out=$(printf '{"n":2}\n' | bu foreach-object '. + {double: (.n * 2)}')
    assert_equal "$out" '{"n":2,"double":4}'
}

function test_bu_foreach_object_unnests { #@test
    local out
    out=$(printf '{"items":[1,2]}\n' | bu foreach-object '.items[]')
    assert_equal "$out" '1
2'
}

function test_bu_foreach_object_missing_expression_fails { #@test
    run bu foreach-object </dev/null
    assert_failure
}

# ===========================================================================
# bu measure-object
# ===========================================================================

function test_bu_measure_object_count_only { #@test
    local out
    out=$(printf '{"n":1}\n{"n":2}\n' | bu measure-object)
    assert_equal "$out" '{"count":2}'
}

function test_bu_measure_object_field_defaults_all_stats { #@test
    local out
    out=$(printf '{"n":1}\n{"n":2}\n{"n":3}\n' | bu measure-object n)
    assert_equal "$out" '{"count":3,"property":"n","sum":6,"avg":2,"min":1,"max":3}'
}

function test_bu_measure_object_single_stat_flag { #@test
    local out
    out=$(printf '{"n":1}\n{"n":2}\n' | bu measure-object n --sum)
    assert_equal "$out" '{"count":2,"property":"n","sum":3}'
}

function test_bu_measure_object_skips_non_numeric { #@test
    local out
    out=$(printf '{"n":1}\n{"n":"x"}\n{}\n' | bu measure-object n --sum)
    assert_equal "$out" '{"count":3,"property":"n","sum":1}'
}

# ===========================================================================
# bu group-object
# ===========================================================================

function test_bu_group_object_no_items { #@test
    local out
    out=$(printf '{"v":"a","n":1}\n{"v":"b","n":2}\n{"v":"a","n":3}\n' | bu group-object v --no-items)
    assert_equal "$out" '{"v":"a","count":2}
{"v":"b","count":1}'
}

function test_bu_group_object_with_items { #@test
    local out
    out=$(printf '{"v":"a","n":1}\n{"v":"a","n":3}\n' | bu group-object v)
    assert_equal "$out" '{"v":"a","count":2,"items":[{"v":"a","n":1},{"v":"a","n":3}]}'
}

function test_bu_group_object_multi_key { #@test
    local out
    out=$(printf '{"v":"a","w":"x"}\n{"v":"a","w":"y"}\n' | bu group-object v,w --no-items)
    assert_equal "$out" '{"v":"a","w":"x","count":1}
{"v":"a","w":"y","count":1}'
}

function test_bu_group_object_missing_key_fails { #@test
    run bu group-object </dev/null
    assert_failure
}

# ===========================================================================
# bu tee-object
# ===========================================================================

function test_bu_tee_object_writes_and_passes_through { #@test
    local f=$BATS_TEST_TMPDIR/tee.jsonl
    local out
    out=$(printf '{"n":1}\n' | bu tee-object "$f")
    assert_equal "$out" '{"n":1}'
    assert_equal "$(cat "$f")" '{"n":1}'
}

function test_bu_tee_object_append { #@test
    local f=$BATS_TEST_TMPDIR/tee.jsonl
    printf '{"n":1}\n' > "$f"
    printf '{"n":2}\n' | bu tee-object --append "$f" >/dev/null
    assert_equal "$(cat "$f")" '{"n":1}
{"n":2}'
}

function test_bu_tee_object_missing_file_fails { #@test
    run bu tee-object </dev/null
    assert_failure
}

# ===========================================================================
# bu compare-object
# ===========================================================================

function test_bu_compare_object_whole_record { #@test
    local ref=$BATS_TEST_TMPDIR/ref.jsonl
    printf '{"n":1}\n{"n":2}\n' > "$ref"
    local out
    out=$(printf '{"n":2}\n{"n":3}\n' | bu compare-object "$ref")
    assert_equal "$out" '{"n":1,"side":"<="}
{"n":3,"side":"=>"}'
}

function test_bu_compare_object_by_key { #@test
    local ref=$BATS_TEST_TMPDIR/ref.jsonl
    printf '{"pid":1,"c":"a"}\n{"pid":2,"c":"b"}\n' > "$ref"
    local out
    out=$(printf '{"pid":2,"c":"b2"}\n{"pid":3,"c":"c"}\n' | bu compare-object "$ref" --key pid)
    assert_equal "$out" '{"pid":1,"c":"a","side":"<="}
{"pid":3,"c":"c","side":"=>"}'
}

function test_bu_compare_object_include_equal { #@test
    local ref=$BATS_TEST_TMPDIR/ref.jsonl
    printf '{"n":1}\n{"n":2}\n' > "$ref"
    local out
    out=$(printf '{"n":2}\n' | bu compare-object "$ref" --include-equal)
    assert_equal "$out" '{"n":1,"side":"<="}
{"n":2,"side":"=="}'
}

function test_bu_compare_object_missing_reference_fails { #@test
    run bu compare-object </dev/null
    assert_failure
}

# ===========================================================================
# bu convert-from-json
# ===========================================================================

function test_bu_convert_from_json_array { #@test
    local out
    out=$(echo '[{"a":1},{"a":2}]' | bu convert-from-json)
    assert_equal "$out" '{"a":1}
{"a":2}'
}

function test_bu_convert_from_json_single_object { #@test
    local out
    out=$(echo '{"a":1}' | bu convert-from-json)
    assert_equal "$out" '{"a":1}'
}

function test_bu_convert_from_json_jsonl_passthrough { #@test
    local out
    out=$(printf '{"a":1}\n{"a":2}\n' | bu convert-from-json)
    assert_equal "$out" '{"a":1}
{"a":2}'
}

# ===========================================================================
# bu convert-from-csv / convert-to-csv
# ===========================================================================

function test_bu_convert_from_csv { #@test
    command -v jc >/dev/null || skip "jc not installed"
    local out
    out=$(printf 'name,age\nalice,30\nbob,25\n' | bu convert-from-csv)
    assert_equal "$out" '{"name":"alice","age":"30"}
{"name":"bob","age":"25"}'
}

function test_bu_convert_to_csv_all_fields { #@test
    local out
    out=$(printf '{"a":1,"b":"x,y"}\n{"a":2,"b":"z"}\n' | bu convert-to-csv)
    assert_equal "$out" '"a","b"
1,"x,y"
2,"z"'
}

function test_bu_convert_to_csv_columns_no_header { #@test
    local out
    out=$(printf '{"a":1,"b":2}\n' | bu convert-to-csv --columns a,b --no-header)
    assert_equal "$out" '1,2'
}

function test_bu_convert_csv_round_trip { #@test
    command -v jc >/dev/null || skip "jc not installed"
    local out
    out=$(printf '{"a":"1","b":"2"}\n' | bu convert-to-csv | bu convert-from-csv)
    assert_equal "$out" '{"a":"1","b":"2"}'
}

# ===========================================================================
# bu convert-from-* (jc parsers) and base64
# ===========================================================================

function test_bu_convert_from_kv { #@test
    command -v jc >/dev/null || skip "jc not installed"
    local out
    out=$(printf 'a=1\nb=2\n' | bu convert-from-kv)
    assert_equal "$out" '{"a":"1","b":"2"}'
}

function test_bu_convert_from_semver { #@test
    command -v jc >/dev/null || skip "jc not installed"
    local out
    out=$(echo '1.2.3-rc.1+build5' | bu convert-from-semver)
    assert_equal "$out" '{"major":1,"minor":2,"patch":3,"prerelease":"rc.1","build":"build5"}'
}

function test_bu_convert_from_ini { #@test
    command -v jc >/dev/null || skip "jc not installed"
    local out
    out=$(printf '[s]\nk=v\n' | bu convert-from-ini)
    assert_equal "$out" '{"s":{"k":"v"}}'
}

function test_bu_convert_to_base64_single_line { #@test
    local out
    out=$(printf 'hello world' | bu convert-to-base64)
    assert_equal "$out" 'aGVsbG8gd29ybGQ='
}

function test_bu_convert_from_base64 { #@test
    local out
    out=$(printf 'aGVsbG8gd29ybGQ=' | bu convert-from-base64)
    assert_equal "$out" 'hello world'
}

function test_bu_base64_round_trip { #@test
    local out
    out=$(printf 'pipes & "quotes"' | bu convert-to-base64 | bu convert-from-base64)
    assert_equal "$out" 'pipes & "quotes"'
}

# ===========================================================================
# bu out-file
# ===========================================================================

function test_bu_out_file_writes_jsonl { #@test
    local f=$BATS_TEST_TMPDIR/out.jsonl
    printf '{"n":1}\n' | bu out-file "$f" 2>/dev/null
    assert_equal "$(cat "$f")" '{"n":1}'
}

function test_bu_out_file_append { #@test
    local f=$BATS_TEST_TMPDIR/out.jsonl
    printf '{"n":1}\n' > "$f"
    printf '{"n":2}\n' | bu out-file --append "$f" 2>/dev/null
    assert_equal "$(cat "$f")" '{"n":1}
{"n":2}'
}

function test_bu_out_file_missing_path_fails { #@test
    run bu out-file </dev/null
    assert_failure
}

# ===========================================================================
# Filesystem: test-path / split-path / resolve-path
# ===========================================================================

function test_bu_test_path_kinds { #@test
    local d=$BATS_TEST_TMPDIR
    touch "$d/f.txt"
    local out
    out=$(bu test-path "$d/f.txt" "$d" "$d/nope")
    assert_equal "$out" "{\"path\":\"$d/f.txt\",\"exists\":true,\"type\":\"file\"}
{\"path\":\"$d\",\"exists\":true,\"type\":\"directory\"}
{\"path\":\"$d/nope\",\"exists\":false,\"type\":\"missing\"}"
}

function test_bu_split_path_full { #@test
    local out
    out=$(bu split-path /usr/local/bin/tool.sh)
    assert_equal "$out" '{"path":"/usr/local/bin/tool.sh","parent":"/usr/local/bin","leaf":"tool.sh","extension":".sh","stem":"tool"}'
}

function test_bu_split_path_hidden_file_no_extension { #@test
    local out
    out=$(bu split-path .bashrc)
    assert_equal "$out" '{"path":".bashrc","parent":".","leaf":".bashrc","extension":null,"stem":".bashrc"}'
}

function test_bu_resolve_path_dotdot { #@test
    local out
    out=$(bu resolve-path /usr/bin/../bin)
    assert_equal "$out" '{"path":"/usr/bin/../bin","resolved":"/usr/bin","exists":true}'
}

# ===========================================================================
# Filesystem: new/copy/move/rename/remove-item
# ===========================================================================

function test_bu_new_item_file_and_dir { #@test
    local d=$BATS_TEST_TMPDIR
    local out
    out=$(bu new-item "$d/sub/deep" --type directory --force)
    assert_equal "$out" "{\"path\":\"$d/sub/deep\",\"type\":\"directory\",\"created\":true}"
    out=$(bu new-item "$d/sub/deep/f.txt")
    assert_equal "$out" "{\"path\":\"$d/sub/deep/f.txt\",\"type\":\"file\",\"created\":true}"
}

function test_bu_new_item_existing_fails { #@test
    local d=$BATS_TEST_TMPDIR
    touch "$d/f.txt"
    run bu new-item "$d/f.txt"
    assert_failure
}

function test_bu_new_item_symlink_requires_target { #@test
    run bu new-item /tmp/link -t symlink
    assert_failure
}

function test_bu_copy_move_rename_remove_round_trip { #@test
    local d=$BATS_TEST_TMPDIR
    echo hi > "$d/a.txt"
    local out
    out=$(bu copy-item "$d/a.txt" "$d/b.txt")
    assert_equal "$out" "{\"source\":\"$d/a.txt\",\"destination\":\"$d/b.txt\",\"copied\":true}"
    run bu move-item "$d/b.txt" "$d/c.txt"
    assert_success
    run bu rename-item "$d/c.txt" d.txt
    assert_success
    [[ -f "$d/d.txt" ]]
    run bu remove-item "$d/d.txt"
    assert_success
    [[ ! -e "$d/d.txt" ]]
}

function test_bu_remove_item_dir_without_recursive_fails { #@test
    local d=$BATS_TEST_TMPDIR
    mkdir -p "$d/dir"
    run bu remove-item "$d/dir"
    assert_failure
    [[ -d "$d/dir" ]]
}

function test_bu_copy_item_multi_source_requires_dir { #@test
    local d=$BATS_TEST_TMPDIR
    touch "$d/a" "$d/b"
    run bu copy-item "$d/a" "$d/b" "$d/notadir"
    assert_failure
}

# ===========================================================================
# Filesystem: get-content / select-string
# ===========================================================================

function test_bu_get_content_whole_file { #@test
    local f=$BATS_TEST_TMPDIR/f.txt
    printf 'alpha\nbeta\n' > "$f"
    local out
    out=$(bu get-content "$f")
    assert_equal "$out" "{\"path\":\"$f\",\"line_number\":1,\"line\":\"alpha\"}
{\"path\":\"$f\",\"line_number\":2,\"line\":\"beta\"}"
}

function test_bu_get_content_head { #@test
    local f=$BATS_TEST_TMPDIR/f.txt
    printf 'a\nb\nc\n' > "$f"
    local out
    out=$(bu get-content "$f" --head 2)
    assert_equal "$out" "{\"path\":\"$f\",\"line_number\":1,\"line\":\"a\"}
{\"path\":\"$f\",\"line_number\":2,\"line\":\"b\"}"
}

function test_bu_get_content_tail { #@test
    local f=$BATS_TEST_TMPDIR/f.txt
    printf 'a\nb\nc\n' > "$f"
    local out
    out=$(bu get-content "$f" --tail 1)
    assert_equal "$out" "{\"path\":\"$f\",\"line_number\":1,\"line\":\"c\"}"
}

function test_bu_get_content_head_tail_exclusive { #@test
    run bu get-content /etc/hosts --head 1 --tail 1
    assert_failure
}

function test_bu_get_content_stdin { #@test
    local out
    out=$(printf 'x\n' | bu get-content)
    assert_equal "$out" '{"path":"<stdin>","line_number":1,"line":"x"}'
}

function test_bu_select_string_file { #@test
    local f=$BATS_TEST_TMPDIR/f.txt
    printf 'foo\nbar\nbaz\n' > "$f"
    local out
    out=$(bu select-string 'ba' "$f")
    assert_equal "$out" "{\"path\":\"$f\",\"line_number\":2,\"line\":\"bar\"}
{\"path\":\"$f\",\"line_number\":3,\"line\":\"baz\"}"
}

function test_bu_select_string_invert_and_case { #@test
    local f=$BATS_TEST_TMPDIR/f.txt
    printf 'FOO\nbar\n' > "$f"
    local out
    out=$(bu select-string -i -v 'foo' "$f")
    assert_equal "$out" "{\"path\":\"$f\",\"line_number\":2,\"line\":\"bar\"}"
}

function test_bu_select_string_no_match_empty { #@test
    local f=$BATS_TEST_TMPDIR/f.txt
    printf 'foo\n' > "$f"
    local out
    out=$(bu select-string 'zzz' "$f")
    assert_equal "$out" ""
}

function test_bu_select_string_stdin { #@test
    local out
    out=$(printf 'abc\n' | bu select-string 'b')
    assert_equal "$out" '{"path":"<stdin>","line_number":1,"line":"abc"}'
}

# ===========================================================================
# Builtin wrappers: set/shopt quartet
# ===========================================================================

function test_bu_get_shell_option_single { #@test
    local out
    # name/value contract is unchanged; synopsis is asserted separately
    out=$(bu get-shell-option pipefail | jq -c 'del(.synopsis)')
    assert_equal "$out" '{"name":"pipefail","value":false}'
}

function test_bu_get_shell_option_synopsis { #@test
    local out
    # (a) a known option's synopsis is non-empty and mentions its behavior
    out=$(bu get-shell-option pipefail | jq -r .synopsis)
    [[ -n "$out" ]]
    [[ "$out" == *"exit status"* ]]
    # (b) full coverage: every option on the running bash has a synopsis
    out=$(bu get-shell-option | jq -r 'select(.synopsis == "") | .name')
    assert_equal "$out" ""
}

function test_bu_set_shell_option_toggles { #@test
    # $( ) subshell isolation: the setting must not leak into the test runner
    local out
    out=$(bu set-shell-option pipefail >/dev/null; bu get-shell-option pipefail | jq -c 'del(.synopsis)')
    assert_equal "$out" '{"name":"pipefail","value":true}'
    out=$(bu set-shell-option pipefail --off >/dev/null; bu get-shell-option pipefail | jq -c 'del(.synopsis)')
    assert_equal "$out" '{"name":"pipefail","value":false}'
    # Confirm no leak: still off in the test shell
    out=$(bu get-shell-option pipefail | jq -c 'del(.synopsis)')
    assert_equal "$out" '{"name":"pipefail","value":false}'
}

function test_bu_set_shell_option_invalid_name_fails { #@test
    run bu set-shell-option definitely-not-an-option
    assert_failure
}

function test_bu_get_shopt_option_single { #@test
    local out
    # name/value contract is unchanged; synopsis is asserted separately
    out=$(bu get-shopt-option nullglob | jq -c 'del(.synopsis)')
    assert_equal "$out" '{"name":"nullglob","value":false}'
}

function test_bu_get_shopt_option_synopsis { #@test
    local out
    # (a) a known option's synopsis is non-empty and mentions its behavior
    out=$(bu get-shopt-option nullglob | jq -r .synopsis)
    [[ -n "$out" ]]
    [[ "$out" == *"empty string"* ]]
    # (b) full coverage: every option on the running bash has a synopsis
    out=$(bu get-shopt-option | jq -r 'select(.synopsis == "") | .name')
    assert_equal "$out" ""
}

function test_bu_set_shopt_option_toggles { #@test
    local out
    out=$(bu set-shopt-option nullglob >/dev/null; bu get-shopt-option nullglob | jq -c 'del(.synopsis)')
    assert_equal "$out" '{"name":"nullglob","value":true}'
    out=$(bu set-shopt-option nullglob --unset >/dev/null; bu get-shopt-option nullglob | jq -c 'del(.synopsis)')
    assert_equal "$out" '{"name":"nullglob","value":false}'
    # Confirm no leak
    out=$(bu get-shopt-option nullglob | jq -c 'del(.synopsis)')
    assert_equal "$out" '{"name":"nullglob","value":false}'
}

function test_bu_set_shopt_option_invalid_name_fails { #@test
    run bu set-shopt-option definitely-not-an-option
    assert_failure
}

function test_bu_get_shopt_option_covers_known_options { #@test
    local out
    out=$(bu get-shopt-option | jq -r .name | tr '\n' ' ')
    [[ "$out" == *globstar* ]]
    [[ "$out" == *nullglob* ]]
    [[ "$out" == *dotglob* ]]
}

function test_bu_get_shopt_option_site_overrides { #@test
    # Site extension point: BU_SHOPT_SYNOPSIS_OVERRIDES entries merge OVER
    # the static table — distro-patched options gain a synopsis, and a
    # vanilla description can be reworded. Absent map = vanilla behavior.
    local -A BU_SHOPT_SYNOPSIS_OVERRIDES=(
        [nullglob]="site-reworded description"
    )
    local out
    out=$(bu get-shopt-option nullglob | jq -r .synopsis)
    assert_equal "$out" "site-reworded description"
}

# ===========================================================================
# Builtin wrappers: variable / builtin / completion / ulimit / umask / trap
# ===========================================================================

function test_bu_get_variable_scalar { #@test
    local out
    out=$(MY_TEST_VAR=hello; bu get-variable MY_TEST_VAR)
    assert_equal "$out" '{"name":"MY_TEST_VAR","type":"string","attributes":"","value":"hello"}'
}

function test_bu_get_variable_array { #@test
    local out
    out=$(MY_TEST_ARR=(a b c); bu get-variable MY_TEST_ARR)
    assert_equal "$out" '{"name":"MY_TEST_ARR","type":"array","attributes":"a","value":null,"length":3}'
}

function test_bu_get_variable_glob_filter { #@test
    local out
    out=$(ZZ_A=1 ZZ_B=2 OTHER=3; bu get-variable 'ZZ_*' | jq -r .name)
    assert_equal "$out" 'ZZ_A
ZZ_B'
}

function test_bu_get_builtin_lists_printf { #@test
    local out
    out=$(bu get-builtin printf)
    assert_equal "$out" '{"name":"printf","enabled":true,"overridden":false,"override_type":null}'
}

function test_bu_get_completion_has_bu { #@test
    local out
    out=$(bu get-completion bu)
    [[ "$out" == *'"command":"bu"'* ]]
}

function test_bu_get_resource_limit_structure { #@test
    local out
    out=$(bu get-resource-limit | bu where '.flag == "-n"')
    [[ "$out" == *'"resource":"open files"'* ]]
    [[ "$out" == *'"soft":'* ]]
    [[ "$out" == *'"hard":'* ]]
}

function test_bu_get_umask { #@test
    local out
    out=$(umask 0022; bu get-umask)
    assert_equal "$out" '{"symbolic":"u=rwx,g=rx,o=rx","octal":"0022"}'
}

function test_bu_get_trap_lists_handler { #@test
    local out
    # bats installs its own DEBUG/ERR traps; filter down to ours
    out=$(trap 'echo hi' USR1; bu get-trap | bu where '.signal == "SIGUSR1"')
    assert_equal "$out" '{"signal":"SIGUSR1","handler":"echo hi"}'
}

# ===========================================================================
# Builtin wrappers: location quartet
# ===========================================================================

function test_bu_get_location { #@test
    local out
    out=$(cd /tmp && bu get-location)
    assert_equal "$out" '{"path":"/tmp"}'
}

function test_bu_push_pop_location_round_trip { #@test
    local out
    out=$(cd /tmp && bu push-location /etc >/dev/null && bu get-location && bu pop-location >/dev/null && bu get-location)
    assert_equal "$out" '{"path":"/etc"}
{"path":"/tmp"}'
}

function test_bu_pop_location_empty_stack_fails { #@test
    run bu pop-location
    assert_failure
}

function test_bu_get_location_stack { #@test
    local out
    out=$(cd /tmp && bu push-location /etc >/dev/null && bu get-location-stack)
    assert_equal "$out" '{"index":0,"path":"/etc"}
{"index":1,"path":"/tmp"}'
}

# ===========================================================================
# Shell utilities: alias / job / guid / sleep / measure-command / history
# ===========================================================================

function test_bu_get_shell_alias { #@test
    local out
    out=$(shopt -s expand_aliases; alias zztest='echo hi'; bu get-shell-alias zztest)
    assert_equal "$out" '{"name":"zztest","definition":"echo hi"}'
}

function test_bu_get_shell_alias_escaped_quotes { #@test
    local out
    out=$(shopt -s expand_aliases; alias zzq='echo '\''a b'\'''; bu get-shell-alias zzq)
    assert_equal "$out" '{"name":"zzq","definition":"echo '\''a b'\''"}'
}

function test_bu_get_alias_gc_record { #@test
    local out
    out=$(bu get-alias gc)
    assert_equal "$out" '{"name":"gc","root":"get-command","definition":"get-command --namespace {} {?} --verb {} {?} --noun {} {...}","synopsis":""}'
}

function test_bu_get_alias_root_filter { #@test
    # Register two throwaway aliases with different roots, then filter each way
    bu_preinit_register_new_alias alias-root-a query-object --select {...}
    bu_preinit_register_new_alias alias-root-b get-command --format {...}
    local out
    out=$(bu get-alias --root query-object | jq -r .name)
    [[ "$out" == *"alias-root-a"* ]]
    [[ "$out" != *"alias-root-b"* ]]
    # Glob filter matches the whole get-* root family
    out=$(bu get-alias --root 'get-*' | jq -r .name)
    [[ "$out" == *"alias-root-b"* ]]
    [[ "$out" == *"gc"* ]]
    [[ "$out" != *"alias-root-a"* ]]
}

function test_bu_get_alias_excludes_bash_aliases { #@test
    # A bash alias must never appear in get-alias output: asking for it by
    # name is a missing CLI alias (No alias named 'zz', status 1)
    local out
    local rc=0
    out=$(shopt -s expand_aliases; alias zz='echo hi'; bu get-alias zz 2>/dev/null) || rc=$?
    assert_equal "$out" ""
    assert_equal "$rc" 1
}

function test_bu_get_alias_synopsis { #@test
    bu_preinit_register_new_alias alias-syn query-object --where {...} --synopsis "Synopsis wins"
    local out
    out=$(bu get-alias alias-syn | jq -r .synopsis)
    assert_equal "$out" "Synopsis wins"
}

function test_bu_new_guid_shape { #@test
    local out
    out=$(bu new-guid | jq -r .guid)
    [[ "$out" =~ ^[0-9a-f-]{36}$ ]]
}

function test_bu_new_guid_count { #@test
    local out
    out=$(bu new-guid --count 3 | jq -s length)
    assert_equal "$out" '3'
}

function test_bu_start_sleep { #@test
    local start=$EPOCHREALTIME
    bu start-sleep 0.1
    local end=$EPOCHREALTIME
    awk -v s="$start" -v e="$end" 'BEGIN { exit !((e - s) >= 0.09) }'
}

function test_bu_start_sleep_rejects_garbage { #@test
    run bu start-sleep abc
    assert_failure
}

function test_bu_measure_command { #@test
    local out
    out=$(bu measure-command true)
    [[ "$out" == '{"command":"true","duration_ms":'*'"exit_code":0}' ]]
}

function test_bu_measure_command_propagates_exit_code { #@test
    run bu measure-command false
    assert_failure
}

function test_bu_get_history { #@test
    command -v jc >/dev/null || skip "jc not installed"
    local out
    out=$(history -s 'echo marker-cmd'; bu get-history | bu select command | bu where '.command == "echo marker-cmd"')
    assert_equal "$out" '{"command":"echo marker-cmd"}'
}

function test_bu_get_job { #@test
    command -v jc >/dev/null || skip "jc not installed"
    local out
    out=$(sleep 30 & bu get-job; kill %1 2>/dev/null)
    [[ "$out" == *'"status":"Running"'* ]]
    [[ "$out" == *sleep* ]]
}

# ===========================================================================
# jc Get-* wrappers (environment-dependent, guarded)
# ===========================================================================

function test_bu_get_date_structure { #@test
    local out
    out=$(bu get-date)
    [[ "$out" == *'"iso":"'* ]]
    [[ "$out" == *'"epoch":'* ]]
    [[ "$out" == *'"day_of_week":"'* ]]
}

function test_bu_get_date_utc { #@test
    local out
    out=$(bu get-date --utc)
    [[ "$out" == *'"timezone_offset":"+0000"'* ]]
}

function test_bu_get_os_release { #@test
    command -v jc >/dev/null || skip "jc not installed"
    [[ -r /etc/os-release ]] || skip "no /etc/os-release"
    local out
    out=$(bu get-os-release)
    [[ "$out" == *'"NAME":"'* ]]
}

function test_bu_get_local_user_root { #@test
    command -v jc >/dev/null || skip "jc not installed"
    command -v getent >/dev/null || skip "no getent"
    local out
    out=$(bu get-local-user | bu where '.username == "root"')
    [[ "$out" == *'"uid":0'* ]]
}

function test_bu_get_local_group_root { #@test
    command -v jc >/dev/null || skip "jc not installed"
    command -v getent >/dev/null || skip "no getent"
    local out
    out=$(bu get-local-group | bu where '.group_name == "root"')
    [[ "$out" == *'"gid":0'* ]]
}

function test_bu_get_file_hash { #@test
    command -v jc >/dev/null || skip "jc not installed"
    local f=$BATS_TEST_TMPDIR/f.txt
    printf 'abc' > "$f"
    local expected
    expected=$(sha256sum "$f" | awk '{print $1}')
    local out
    out=$(bu get-file-hash "$f")
    # jc hashsum parser may or may not include "mode" depending on version.
    # Verify the essential fields only.
    local hash
    hash=$(echo "$out" | jq -r '.hash')
    assert_equal "$hash" "$expected"
    local filename
    filename=$(echo "$out" | jq -r '.filename')
    assert_equal "$filename" "$f"
}

function test_bu_get_file_hash_md5 { #@test
    command -v jc >/dev/null || skip "jc not installed"
    local f=$BATS_TEST_TMPDIR/f.txt
    printf 'abc' > "$f"
    local expected
    expected=$(md5sum "$f" | awk '{print $1}')
    local out
    out=$(bu get-file-hash --algorithm md5 "$f")
    # jc hashsum parser may or may not include "mode" depending on version.
    # Verify the essential fields only.
    local hash
    hash=$(echo "$out" | jq -r '.hash')
    assert_equal "$hash" "$expected"
    local filename
    filename=$(echo "$out" | jq -r '.filename')
    assert_equal "$filename" "$f"
}

function test_bu_get_file_hash_requires_file { #@test
    run bu get-file-hash
    assert_failure
}

function test_bu_get_host_file_entry { #@test
    command -v jc >/dev/null || skip "jc not installed"
    [[ -r /etc/hosts ]] || skip "no /etc/hosts"
    local out
    out=$(bu get-host-file-entry)
    [[ "$out" == *localhost* ]]
}

function test_bu_get_git_branch { #@test
    command -v git >/dev/null || skip "git not installed"
    # A fixture repo: the BashTab checkout itself may be on a detached HEAD
    # (CI checks out pull requests that way), which has no current branch.
    local repo="$BATS_TEST_TMPDIR"/repo
    git init -q -b work "$repo"
    git -C "$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
    local out
    out=$(cd "$repo" && bu get-git-branch | bu where '.current')
    [[ "$out" == *'"name":"work"'* ]]
    [[ "$out" == *'"current":true'* ]]
}

function test_bu_get_git_log { #@test
    command -v jc >/dev/null || skip "jc not installed"
    command -v git >/dev/null || skip "git not installed"
    local out
    out=$(bu get-git-log -- -n 1 | jq -r .commit)
    [[ "$out" =~ ^[0-9a-f]{40}$ ]]
}

# ===========================================================================
# Cross-cutting: pipeline composition of the new cmdlets
# ===========================================================================

function test_bu_pipeline_get_member_after_select { #@test
    local out
    out=$(BU_MODULE_LIST='alpha:1.0.0:/a' bu get-module | bu select name | bu get-member)
    assert_equal "$out" '{"name":"name","types":"string","count":1,"null_count":0}'
}

function test_bu_pipeline_group_measure_combo { #@test
    local out
    out=$(printf '{"v":"a","n":1}\n{"v":"a","n":2}\n{"v":"b","n":3}\n' | bu group-object v --no-items | bu measure-object count --sum)
    assert_equal "$out" '{"count":2,"property":"count","sum":3}'
}

# ===========================================================================
# Pipeline input (structural typing): commands act on piped records
# ===========================================================================

function test_bu_pipeline_stop_process_from_records { #@test
    local out
    out=$(printf '{"pid":999999}\n' | bu stop-process --what-if 2>/dev/null)
    # --what-if logs to stderr only; the record stream should be empty (no actual action)
    assert_equal "$out" ""
}

function test_bu_pipeline_remove_item_from_records_what_if { #@test
    local d=$BATS_TEST_TMPDIR/pi_rm_wi
    mkdir -p "$d"
    touch "$d/a" "$d/b"
    local out
    out=$(printf '{"path":"%s/a"}\n{"filename":"%s/b"}\n' "$d" "$d" | bu remove-item --what-if 2>/dev/null)
    # --what-if only logs to stderr, emits no records for existing paths
    assert_equal "$out" ""
    # Files should still exist
    [[ -f "$d/a" && -f "$d/b" ]]
}

function test_bu_pipeline_remove_item_filename_alias { #@test
    local d=$BATS_TEST_TMPDIR/pi_rm
    mkdir -p "$d"
    touch "$d/f.txt"
    local out
    out=$(bu get-file "$d" --file | bu remove-item)
    assert_equal "$out" "{\"path\":\"$d/f.txt\",\"removed\":true}"
    [[ ! -e "$d/f.txt" ]]
}

function test_bu_pipeline_copy_item_from_records { #@test
    local d=$BATS_TEST_TMPDIR/pi_cp
    mkdir -p "$d/src" "$d/dst"
    touch "$d/src/a.txt"
    local out
    out=$(bu test-path "$d/src/a.txt" | bu copy-item "$d/dst/")
    assert_equal "$out" "{\"source\":\"$d/src/a.txt\",\"destination\":\"$d/dst/\",\"copied\":true}"
    [[ -f "$d/dst/a.txt" ]]
}

function test_bu_pipeline_set_shell_option_from_records { #@test
    local out
    out=$(printf '{"name":"pipefail","value":true}\n' | bu set-shell-option)
    assert_equal "$out" '{"name":"pipefail","value":true}'
    # Confirm it took effect (we're in a subshell from $( ), doesn't leak)
}

function test_bu_pipeline_set_shopt_option_from_records { #@test
    local out
    out=$(printf '{"name":"nullglob","value":false}\n' | bu set-shopt-option)
    assert_equal "$out" '{"name":"nullglob","value":false}'
}

function test_bu_pipeline_service_from_records_what_if { #@test
    local out
    out=$(printf '{"unit":"sshd"}\n' | bu start-service --what-if 2>/dev/null)
    assert_equal "$out" ""
}

function test_bu_pipeline_web_request_from_url_record { #@test
    local out
    out=$(printf '{"url":"https://example.com"}\n' | bu invoke-web-request -o /dev/null 2>/dev/null | jq -r .response_code)
    assert_equal "$out" "200"
}
