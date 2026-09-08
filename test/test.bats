#!/usr/bin/env -S bats --jobs 16 

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

function test_bu_basename { #@test
    bu_basename /a/ab/abc/d.txt
    assert_equal "$BU_RET" d.txt

    bu_basename a/ab/abc/d.txt.log
    assert_equal "$BU_RET" d.txt.log

    bu_basename ./.././d.txt
    assert_equal "$BU_RET" d.txt

    bu_basename ../d.txt
    assert_equal "$BU_RET" d.txt

    bu_basename d.txt
    assert_equal "$BU_RET" d.txt
}

function test_bu_dirname { #@test
    bu_dirname /a/ab/abc/d.txt
    assert_equal "$BU_RET" /a/ab/abc

    bu_dirname a/ab/abc/d.txt.log
    assert_equal "$BU_RET" a/ab/abc

    bu_dirname ./d.txt
    assert_equal "$BU_RET" .

    bu_dirname ../d.txt
    assert_equal "$BU_RET" ..

    bu_dirname d.txt
    assert_equal "$BU_RET" .
}

function test_bu_realpath { #@test
    bu_realpath /a/ab/abc/d.txt
    assert_equal "$BU_RET" /a/ab/abc/d.txt

    bu_realpath d.txt
    assert_equal "$BU_RET" "$PWD/d.txt"

    bu_realpath ./d.txt
    assert_equal "$BU_RET" "$PWD/d.txt"

    bu_realpath d.txt "$DIR"
    assert_equal "$BU_RET" "$DIR/d.txt"
}

# Helper functions for bu_ret_to_stdout tests
__test_cmd_hello() { BU_RET="hello"; }
__test_cmd_world() { BU_RET="world"; }
__test_cmd_array() { BU_RET=(one two three); }
__test_cmd_lines() { BU_RET=(line1 line2 line3); }
__test_cmd_array_first() { BU_RET=(first second); }
__test_cmd_empty() { BU_RET=""; }
__test_cmd_failing() { BU_RET="test"; return 42; }

# Helper functions for bu_stdout_to_ret tests
__test_stdout_hello() { echo "hello"; }
__test_stdout_world() { echo "world"; }
__test_stdout_words() { echo "one two three"; }
__test_stdout_lines() { printf "line1\nline2\nline3\n"; }
__test_stdout_multiline() { printf "line1\nline2\nline3"; }
__test_stdout_failing() { echo "output"; return 7; }

# Tests for bu_ret_to_stdout
function test_bu_ret_to_stdout { #@test
    local output
    
    # Test --str mode
    output=$(bu_ret_to_stdout --str __test_cmd_hello)
    assert_equal "$output" "hello"
    
    # Test default mode (same as --spaces)
    output=$(bu_ret_to_stdout __test_cmd_world)
    assert_equal "$output" "world"
    
    # Test --spaces with array
    output=$(bu_ret_to_stdout --spaces __test_cmd_array)
    assert_equal "$output" "one two three "
    
    # Test --lines with array
    output=$(bu_ret_to_stdout --lines __test_cmd_lines)
    # Note that Bash will strip any trailing whitespace produced from a subshell
    assert_equal "$output" $'line1\nline2\nline3'
    
    # Test --str with array (only outputs first element)
    output=$(bu_ret_to_stdout --str __test_cmd_array_first)
    assert_equal "$output" "first"
    
    # Test with empty string
    output=$(bu_ret_to_stdout --str __test_cmd_empty)
    assert_equal "$output" ""
    
    # Test that exit code is preserved
    run bu_ret_to_stdout --str __test_cmd_failing
    assert_failure 42
    
    # Test invalid option
    run bu_ret_to_stdout --invalid __test_cmd_hello
    assert_failure 1
}

# Tests for bu_stdout_to_ret
function test_bu_stdout_to_ret_str { #@test
    # Test --str mode
    bu_stdout_to_ret --str __test_stdout_hello
    assert_equal "$BU_RET" "hello"
}

function test_bu_stdout_to_ret_spaces { #@test
    # Test default mode (same as --spaces)
    bu_stdout_to_ret __test_stdout_world
    assert_equal "$BU_RET" "world"

    # Test --spaces with multiple words
    bu_stdout_to_ret --spaces __test_stdout_words
    assert_equal "${BU_RET[0]}" "one"
    assert_equal "${BU_RET[1]}" "two"
    assert_equal "${BU_RET[2]}" "three"
}

function test_bu_stdout_to_ret_lines { #@test
    # Test --lines mode
    bu_stdout_to_ret --lines __test_stdout_lines
    assert_equal "${BU_RET[0]}" "line1"
    assert_equal "${BU_RET[1]}" "line2"
    assert_equal "${BU_RET[2]}" "line3"
}

function test_bu_stdout_to_ret { #@test
    # Test custom outparam with short form
    bu_stdout_to_ret --str -o MY_VAR __test_stdout_hello
    assert_equal "$MY_VAR" "hello"
    
    # Test custom outparam with long form
    bu_stdout_to_ret --str --outparam MY_VAR2 __test_stdout_hello
    assert_equal "$MY_VAR2" "hello"
    
    # Test exit code preservation
    run bu_stdout_to_ret --str __test_stdout_failing
    assert_failure 7
    
    # Test multiline output is preserved
    bu_stdout_to_ret --lines __test_stdout_multiline
    assert_equal ${#BU_RET[@]} 3
    assert_equal "${BU_RET[0]}" "line1"
    assert_equal "${BU_RET[1]}" "line2"
    assert_equal "${BU_RET[2]}" "line3"
    
    # Test invalid option
    run bu_stdout_to_ret --invalid __test_stdout_hello
    assert_failure 1
}

# Tests for bu_symbol_is_function
function test_bu_symbol_is_function { #@test
    # Test with an existing function
    run bu_symbol_is_function bu_realpath
    assert_success
    
    # Test with builtin command (not a function)
    run bu_symbol_is_function echo
    assert_failure
    
    # Test with another builtin
    run bu_symbol_is_function cd
    assert_failure
    
    # Test with nonexistent symbol
    run bu_symbol_is_function nonexistent_function_xyz
    assert_failure
}

# Tests for bu_symbol_is_file
function test_bu_symbol_is_file { #@test
    # Test with absolute path to existing file
    run bu_symbol_is_file /bin/bash
    assert_success
    
    # Test with nonexistent path
    run bu_symbol_is_file /nonexistent/path/to/file
    assert_failure
    
    # Test with function (not a file)
    run bu_symbol_is_file bu_realpath
    assert_failure
    
    # Test with builtin (not a file)
    run bu_symbol_is_file echo
    assert_failure
    
    # Test with executable in PATH
    run bu_symbol_is_file bash
    assert_success
}

# Tests for bu_list_join
function test_bu_list_join { #@test
    # Test with comma separator
    bu_list_join , a b c
    assert_equal "$BU_RET" "a,b,c"
    
    # Test with space separator
    bu_list_join " " one two three
    assert_equal "$BU_RET" "one two three"
    
    # Test with pipe separator
    bu_list_join "|" x y z
    assert_equal "$BU_RET" "x|y|z"
    
    # Test with single element
    bu_list_join , single
    assert_equal "$BU_RET" "single"
    
    # Test with empty list
    bu_list_join ,
    assert_equal "$BU_RET" ""
    
    # Test with two elements
    bu_list_join "-" first second
    assert_equal "$BU_RET" "first-second"
}

# Tests for bu_list_reverse
function test_bu_list_reverse { #@test
    # Test with three elements
    bu_list_reverse a b c
    assert_equal "${BU_RET[0]}" "c"
    assert_equal "${BU_RET[1]}" "b"
    assert_equal "${BU_RET[2]}" "a"
    
    # Test with single element
    bu_list_reverse single
    assert_equal "${BU_RET[0]}" "single"
    
    # Test with two elements
    bu_list_reverse first second
    assert_equal "${BU_RET[0]}" "second"
    assert_equal "${BU_RET[1]}" "first"
    
    # Test with many elements
    bu_list_reverse 1 2 3 4 5
    assert_equal "${BU_RET[0]}" "5"
    assert_equal "${BU_RET[1]}" "4"
    assert_equal "${BU_RET[2]}" "3"
    assert_equal "${BU_RET[3]}" "2"
    assert_equal "${BU_RET[4]}" "1"
}

# Tests for bu_list_filter_out_empty
function test_bu_list_filter_out_empty { #@test
    # Test with mixed empty and non-empty elements
    bu_list_filter_out_empty a "" b "" c
    assert_equal "${BU_RET[0]}" "a"
    assert_equal "${BU_RET[1]}" "b"
    assert_equal "${BU_RET[2]}" "c"
    assert_equal ${#BU_RET[@]} 3
    
    # Test with no empty elements
    bu_list_filter_out_empty x y z
    assert_equal "${BU_RET[0]}" "x"
    assert_equal "${BU_RET[1]}" "y"
    assert_equal "${BU_RET[2]}" "z"
    assert_equal ${#BU_RET[@]} 3
    
    # Test with all empty elements
    bu_list_filter_out_empty "" "" ""
    assert_equal ${#BU_RET[@]} 0
    
    # Test with leading/trailing empty
    bu_list_filter_out_empty "" one two ""
    assert_equal "${BU_RET[0]}" "one"
    assert_equal "${BU_RET[1]}" "two"
    assert_equal ${#BU_RET[@]} 2
}

# Tests for bu_list_sort
function test_bu_list_sort { #@test
    # Test basic sorting
    bu_list_sort c a b
    assert_equal "${BU_RET[0]}" "a"
    assert_equal "${BU_RET[1]}" "b"
    assert_equal "${BU_RET[2]}" "c"
    
    # Test with numbers (lexicographic order)
    bu_list_sort 30 1 20 10
    assert_equal "${BU_RET[0]}" "1"
    assert_equal "${BU_RET[1]}" "10"
    assert_equal "${BU_RET[2]}" "20"
    assert_equal "${BU_RET[3]}" "30"
    
    # Test with single element
    bu_list_sort single
    assert_equal "${BU_RET[0]}" "single"
    
    # Test with duplicate elements
    bu_list_sort b a b c a
    assert_equal "${BU_RET[0]}" "a"
    assert_equal "${BU_RET[1]}" "a"
    assert_equal "${BU_RET[2]}" "b"
    assert_equal "${BU_RET[3]}" "b"
    assert_equal "${BU_RET[4]}" "c"
}

# Tests for bu_list_exists_str
function test_bu_list_exists_str { #@test
    local haystack=(apple banana cherry)
    
    # Test element exists
    run bu_list_exists_str banana "${haystack[@]}"
    assert_success
    
    # Test first element
    run bu_list_exists_str apple "${haystack[@]}"
    assert_success
    
    # Test last element
    run bu_list_exists_str cherry "${haystack[@]}"
    assert_success
    
    # Test element not in list
    run bu_list_exists_str orange "${haystack[@]}"
    assert_failure 1
    
    # Test with single element list (match)
    run bu_list_exists_str single single
    assert_success
    
    # Test with single element list (no match)
    run bu_list_exists_str needle haystack
    assert_failure 1
    
    # Test with empty list
    run bu_list_exists_str something
    assert_failure 1
}

# Tests for bu_str_split
function test_bu_str_split { #@test
    # Test basic comma split
    bu_str_split , "a,b,c"
    assert_equal "${BU_RET[0]}" "a"
    assert_equal "${BU_RET[1]}" "b"
    assert_equal "${BU_RET[2]}" "c"
    
    # Test space separator
    bu_str_split " " "one two three"
    assert_equal "${BU_RET[0]}" "one"
    assert_equal "${BU_RET[1]}" "two"
    assert_equal "${BU_RET[2]}" "three"
    
    # Test with custom separator
    bu_str_split "|" "x|y|z"
    assert_equal "${BU_RET[0]}" "x"
    assert_equal "${BU_RET[1]}" "y"
    assert_equal "${BU_RET[2]}" "z"
    
    # Test with single element (no separator in string)
    bu_str_split , "single"
    assert_equal "${BU_RET[0]}" "single"
    
    # Test with custom output variable
    bu_str_split , "a,b,c" MY_ARRAY
    assert_equal "${MY_ARRAY[0]}" "a"
    assert_equal "${MY_ARRAY[1]}" "b"
    assert_equal "${MY_ARRAY[2]}" "c"
    
    # Test empty string results in single empty element
    bu_str_split , ""
    assert_equal ${#BU_RET[@]} 1
    assert_equal "${BU_RET[0]}" ""
}

# Tests for __bu_env_append_generic_path
function test_bu_env_append_generic_path { #@test
    # Test appending to empty path variable
    local TEST_PATH=""
    __bu_env_append_generic_path TEST_PATH "/usr/bin"
    assert_equal "$TEST_PATH" "/usr/bin"
    
    # Test appending to existing path
    TEST_PATH="/usr/bin"
    __bu_env_append_generic_path TEST_PATH "/usr/local/bin"
    assert_equal "$TEST_PATH" "/usr/bin:/usr/local/bin"
    
    # Test appending when path already exists (should not duplicate)
    TEST_PATH="/usr/bin:/usr/local/bin"
    __bu_env_append_generic_path TEST_PATH "/usr/bin"
    assert_equal "$TEST_PATH" "/usr/bin:/usr/local/bin"
    
    # Test appending another new path
    TEST_PATH="/usr/bin:/usr/local/bin"
    __bu_env_append_generic_path TEST_PATH "/opt/bin"
    assert_equal "$TEST_PATH" "/usr/bin:/usr/local/bin:/opt/bin"

    TEST_PATH="/usr/local/bin"
    __bu_env_append_generic_path TEST_PATH "/usr/bin"
    assert_equal "$TEST_PATH" "/usr/local/bin:/usr/bin"
    
    # Test appending to path with multiple entries
    TEST_PATH="/a:/b:/c"
    __bu_env_append_generic_path TEST_PATH "/d"
    assert_equal "$TEST_PATH" "/a:/b:/c:/d"

    TEST_PATH="/a:/b:/c"
    __bu_env_append_generic_path TEST_PATH "/d:/a:/b:/c"
    assert_equal "$TEST_PATH" "/a:/b:/c:/d:/a:/b:/c"
}

# Tests for __bu_env_prepend_generic_path
function test_bu_env_prepend_generic_path { #@test
    # Test prepending to empty path variable
    local TEST_PATH=""
    __bu_env_prepend_generic_path TEST_PATH "/usr/bin"
    assert_equal "$TEST_PATH" "/usr/bin"
    
    # Test prepending to existing path
    TEST_PATH="/usr/local/bin"
    __bu_env_prepend_generic_path TEST_PATH "/usr/bin"
    assert_equal "$TEST_PATH" "/usr/bin:/usr/local/bin"
    
    # Test prepending when path already exists (should not duplicate)
    TEST_PATH="/usr/bin:/usr/local/bin"
    __bu_env_prepend_generic_path TEST_PATH "/usr/bin"
    assert_equal "$TEST_PATH" "/usr/bin:/usr/local/bin"
    
    # Test prepending another new path (goes to front)
    TEST_PATH="/usr/bin:/usr/local/bin"
    __bu_env_prepend_generic_path TEST_PATH "/opt/bin"
    assert_equal "$TEST_PATH" "/opt/bin:/usr/bin:/usr/local/bin"
    
    # Test prepending to path with multiple entries
    TEST_PATH="/a:/b:/c"
    __bu_env_prepend_generic_path TEST_PATH "/z"
    assert_equal "$TEST_PATH" "/z:/a:/b:/c"
    
    # Test that prepend checks for exact match (with colons)
    TEST_PATH="/usr/local/bin"
    __bu_env_prepend_generic_path TEST_PATH "/usr/bin"
    assert_equal "$TEST_PATH" "/usr/bin:/usr/local/bin"
}



# Tests for __bu_env_remove_from_generic_path
function test_bu_env_remove_from_generic_path { #@test
    # Remove from empty path (no-op)
    local TEST_PATH=""
    __bu_env_remove_from_generic_path TEST_PATH "/usr/bin"
    assert_equal "$TEST_PATH" ""

    # Remove middle element
    TEST_PATH="/a:/b:/c"
    __bu_env_remove_from_generic_path TEST_PATH "/b"
    assert_equal "$TEST_PATH" "/a:/c"

    # Remove first element
    TEST_PATH="/b:/a:/c"
    __bu_env_remove_from_generic_path TEST_PATH "/b"
    assert_equal "$TEST_PATH" "/a:/c"

    # Remove last element
    TEST_PATH="/a:/b:/c"
    __bu_env_remove_from_generic_path TEST_PATH "/c"
    assert_equal "$TEST_PATH" "/a:/b"

    # Remove duplicate elements
    TEST_PATH="/a:/b:/a:/c"
    __bu_env_remove_from_generic_path TEST_PATH "/a"
    # both /a occurrences should be removed
    assert_equal "$TEST_PATH" "/b:/c"

    # Remove non-existent element (no-op)
    TEST_PATH="/x:/y:/z"
    __bu_env_remove_from_generic_path TEST_PATH "/notfound"
    assert_equal "$TEST_PATH" "/x:/y:/z"

    # Ensure substrings are not removed (exact match required)
    TEST_PATH="/usr/local/bin:/usr/bin"
    __bu_env_remove_from_generic_path TEST_PATH "/usr"
    assert_equal "$TEST_PATH" "/usr/local/bin:/usr/bin"

    # It is allowed to remove multiple consecutive paths at once
    TEST_PATH="/a:/b:/c"
    __bu_env_remove_from_generic_path TEST_PATH "/b:/c"
    assert_equal "$TEST_PATH" "/a"

    TEST_PATH="/a:/b:/c"
    __bu_env_remove_from_generic_path TEST_PATH "/a:/b"
    assert_equal "$TEST_PATH" "/c"

    TEST_PATH="/a"
    __bu_env_remove_from_generic_path TEST_PATH "/a"
    assert_equal "$TEST_PATH" ""
}

function test_bu_convert_file_to_command_namespace { #@test
    bu_convert_file_to_command_namespace none /a/b/c/namespace-verb-noun1-noun2-noun3.sh
    assert_equal "$BU_RET" namespace-verb-noun1-noun2-noun3

    bu_convert_file_to_command_namespace prefix /a/b/c/namespace-verb-noun1-noun2-noun3.sh
    assert_equal "$BU_RET" verb-noun1-noun2-noun3

    bu_convert_file_to_command_namespace powershell /a/b/c/verb-namespace-noun1-noun2-noun3.sh
    assert_equal "$BU_RET" verb-noun1-noun2-noun3
}

# Tests for bu_tolower
function test_bu_tolower { #@test
    local output

    # Test basic lowercase conversion
    output=$(bu_tolower "HELLO")
    assert_equal "$output" "hello"

    # Test mixed case
    output=$(bu_tolower "HeLLo WoRLd")
    assert_equal "$output" "hello world"

    # Test already lowercase
    output=$(bu_tolower "already lowercase")
    assert_equal "$output" "already lowercase"

    # Test with numbers and symbols
    output=$(bu_tolower "Test123!@#")
    assert_equal "$output" "test123!@#"

    # Test empty string
    output=$(bu_tolower "")
    assert_equal "$output" ""

    # Test multiple arguments (should join with spaces)
    output=$(bu_tolower "ABC" "DEF" "GHI")
    assert_equal "$output" "abc def ghi"
}

# Tests for bu_toupper
function test_bu_toupper { #@test
    local output

    # Test basic uppercase conversion
    output=$(bu_toupper "hello")
    assert_equal "$output" "HELLO"

    # Test mixed case
    output=$(bu_toupper "HeLLo WoRLd")
    assert_equal "$output" "HELLO WORLD"

    # Test already uppercase
    output=$(bu_toupper "ALREADY UPPERCASE")
    assert_equal "$output" "ALREADY UPPERCASE"

    # Test with numbers and symbols
    output=$(bu_toupper "test123!@#")
    assert_equal "$output" "TEST123!@#"

    # Test empty string
    output=$(bu_toupper "")
    assert_equal "$output" ""

    # Test multiple arguments (should join with spaces)
    output=$(bu_toupper "abc" "def" "ghi")
    assert_equal "$output" "ABC DEF GHI"
}

# Tests for bu_gen_trim
function test_bu_gen_trim { #@test
    local output

    # Test trimming leading and trailing spaces
    output=$(echo "  hello  " | bu_gen_trim)
    assert_equal "$output" "hello"

    # Test trimming tabs
    output=$(printf "\t\thello\t\t" | bu_gen_trim)
    assert_equal "$output" "hello"

    # Test trimming mixed whitespace
    output=$(echo "  hello   world  " | bu_gen_trim)
    assert_equal "$output" "hello world"

    # Test already trimmed
    output=$(echo "hello" | bu_gen_trim)
    assert_equal "$output" "hello"

    # Test empty string
    output=$(echo "" | bu_gen_trim)
    assert_equal "$output" ""

    # Test only whitespace
    output=$(echo "   " | bu_gen_trim)
    assert_equal "$output" ""
}

# Tests for bu_list_version_sort
function test_bu_list_version_sort { #@test
    # Test basic version sorting
    bu_list_version_sort 1.10.0 1.2.0 1.1.0
    assert_equal "${BU_RET[0]}" "1.1.0"
    assert_equal "${BU_RET[1]}" "1.2.0"
    assert_equal "${BU_RET[2]}" "1.10.0"

    # Test with single element
    bu_list_version_sort 1.0.0
    assert_equal "${BU_RET[0]}" "1.0.0"

    # Test with complex version numbers
    bu_list_version_sort 2.0.0 1.0.0 1.10.0 1.2.0
    assert_equal "${BU_RET[0]}" "1.0.0"
    assert_equal "${BU_RET[1]}" "1.2.0"
    assert_equal "${BU_RET[2]}" "1.10.0"
    assert_equal "${BU_RET[3]}" "2.0.0"

    # Test with patch versions
    bu_list_version_sort 1.0.10 1.0.2 1.0.1
    assert_equal "${BU_RET[0]}" "1.0.1"
    assert_equal "${BU_RET[1]}" "1.0.2"
    assert_equal "${BU_RET[2]}" "1.0.10"
}

# Tests for bu_env_is_in_tmux
function test_bu_env_is_in_tmux { #@test
    # Save current environment
    local saved_tmux=$TMUX
    local saved_term=$TERM

    # Test when not in tmux (empty TMUX variable)
    TMUX=""
    TERM="xterm"
    run bu_env_is_in_tmux
    assert_failure

    # Test when in tmux (both TMUX set and TERM is screen*)
    TMUX="/tmp/tmux-1000/default,12345,0"
    TERM="screen-256color"
    run bu_env_is_in_tmux
    assert_success

    # Test when in tmux (both TMUX set and TERM is tmux*)
    TMUX="/tmp/tmux-1000/default,12345,0"
    TERM="tmux-256color"
    run bu_env_is_in_tmux
    assert_success

    # Test when TMUX is set but TERM is wrong
    TMUX="/tmp/tmux-1000/default,12345,0"
    TERM="xterm"
    run bu_env_is_in_tmux
    assert_failure

    # Test when TERM is right but TMUX is not set
    TMUX=""
    TERM="screen-256color"
    run bu_env_is_in_tmux
    assert_failure

    # Restore environment
    TMUX=$saved_tmux
    TERM=$saved_term
}

# ===========================================================================
# bash 4.4 readonly array local regression tests
#
# bash 4.4 has a bug where `local -r arr=(...)` (readonly array local)
# aborts with "readonly variable" when the same name is re-declared in a
# sourced script or recursive call.  Scalar `local -r` is not affected.
# These tests verify the fix: dropping -r from array locals at the
# three known crash sites (bu_impl.sh, bu_core_autocomplete.sh).
# ===========================================================================

function test_bash44_source_type_command_no_readonly_abort { #@test
    # Source-type commands are sourced from __bu_impl's scope.
    # The standard command template declares `local remaining_options=("$@")`.
    # Before the fix, __bu_impl's `local -r remaining_options` caused
    # "readonly variable" abort on bash 4.4.
    # `get-module` is a source-type (not executable, not a function) command.
    run bu get-module
    assert_success
}

function test_bash44_alias_chain_dispatch { #@test
    # Two-hop alias chain: A -> B -> real command.
    # Both __bu_impl_process_alias and __bu_autocomplete_completion_func_cli_resolve_alias
    # recurse to resolve alias-of-alias chains.  Before the fix, their
    # `local -r bu_alias_spec=($1)` aborted on bash 4.4.
    local a1=__test_b44_chain_a
    local a2=__test_b44_chain_b

    # Register alias B -> get-module (source-type command)
    bu_preinit_register_new_alias "$a2" get-module
    # Register alias A -> B
    bu_preinit_register_new_alias "$a1" "$a2"

    # Dispatch through the alias chain
    run bu "$a1"
    assert_success
}

# ===========================================================================
# Alias --help dispatch
# ===========================================================================

function test_alias_sole_help_shows_expansion_and_root_help { #@test
    # A sole --help addressed to the alias is a help request, not slot data.
    run bu where --help </dev/null
    assert_success
    assert_output --partial 'ALIAS'
    assert_output --partial 'where => '
    assert_output --partial 'query-object --where {...}'
    assert_output --partial 'SYNOPSIS'
    refute_output --partial 'Invalid record key'
    refute_output --partial 'command not found'
}

function test_alias_short_help_flag { #@test
    run bu select -h </dev/null
    assert_success
    assert_output --partial 'ALIAS'
    assert_output --partial 'select => '
    assert_output --partial 'query-object --select {...}'
    assert_output --partial 'SYNOPSIS'
}

function test_alias_gc_help_shows_slots_verbatim { #@test
    # gc's {}/{?}/{...} slots must appear verbatim in the expansion and
    # get-command's help must render (previously empty output).
    run bu gc --help </dev/null
    assert_success
    assert_output --partial 'gc => '
    assert_output --partial 'get-command --namespace {} {?} --verb {} {?} --noun {} {...}'
    assert_output --partial 'SYNOPSIS'
}

function test_alias_chain_help_one_line_per_hop { #@test
    local a1=__test_help_chain_a
    local a2=__test_help_chain_b
    bu_preinit_register_new_alias "$a2" get-module
    bu_preinit_register_new_alias "$a1" "$a2"

    run bu "$a1" --help </dev/null
    assert_success
    assert_output --partial "$a1 => "
    assert_output --partial "$a2 => "
    assert_output --partial 'get-module'
    assert_output --partial 'SYNOPSIS'
}

function test_alias_trailing_help_passes_through { #@test
    # --help after other args is NOT intercepted; it flows through the alias
    # spec and the root command renders its own help (no ALIAS header).
    run bu where type -eq source --help </dev/null
    assert_success
    assert_output --partial 'SYNOPSIS'
    refute_output --partial 'ALIAS'
}

function test_alias_normal_dispatch_unchanged { #@test
    local infile=$BATS_TEST_TMPDIR/rows.jsonl
    printf '{"name":"x","type":"source"}\n{"name":"y","type":"alias"}\n' > "$infile"
    run bu where type -eq source --format jsonl < "$infile"
    assert_success
    assert_output '{"name":"x","type":"source"}'
}

function test_bash44_alias_chain_completion { #@test
    # Completion must resolve alias-of-alias chains without
    # "readonly variable" abort.
    local a1=__test_b44_comp_a
    local a2=__test_b44_comp_b

    bu_preinit_register_new_alias "$a2" get-module
    bu_preinit_register_new_alias "$a1" "$a2"

    # Trigger completion through the chain; should not abort
    run bu_autocomplete_get_autocompletions bu "$a1" ""
    assert_success
}

function test_alias_first_arg_completion_offers_help { #@test
    # Aliases have no case block, so --help/-h were absent from the alias's
    # first-argument completion (the delegated slot-value completions don't
    # offer them).  The dispatcher intercepts a sole --help/-h at this
    # position (alias expansion + root help), so surface both additively.
    local _c _found_help _found_h

    COMPREPLY=()
    bu_autocomplete_get_autocompletions bu where "" 2>/dev/null
    _found_help=false; _found_h=false
    for _c in "${COMPREPLY[@]}"; do
        [[ "$_c" == "--help" ]] && _found_help=true
        [[ "$_c" == "-h" ]] && _found_h=true
    done
    assert_equal "$_found_help" true
    assert_equal "$_found_h" true

    # gc's first arg is a required --namespace value; --help must be offered
    # additively alongside the delegated namespace completions.
    COMPREPLY=()
    bu_autocomplete_get_autocompletions bu gc "" 2>/dev/null
    _found_help=false; _found_h=false
    for _c in "${COMPREPLY[@]}"; do
        [[ "$_c" == "--help" ]] && _found_help=true
        [[ "$_c" == "-h" ]] && _found_h=true
    done
    assert_equal "$_found_help" true
    assert_equal "$_found_h" true
}

function test_alias_help_completion_respects_prefix { #@test
    # Injected --help/-h must honor the typed prefix like any completion.
    COMPREPLY=()
    bu_autocomplete_get_autocompletions bu where "--h" 2>/dev/null
    assert_equal "${COMPREPLY[*]}" "--help"

    # A non-matching prefix must not inject help entries.
    local _c _has_help=false
    COMPREPLY=()
    bu_autocomplete_get_autocompletions bu where "name" 2>/dev/null
    for _c in "${COMPREPLY[@]}"; do
        [[ "$_c" == "--help" || "$_c" == "-h" ]] && _has_help=true
    done
    assert_equal "$_has_help" false
}

# ===========================================================================
# --options-of / --options-at completion path bugs
# ===========================================================================

function test_options_at_multiline_alternation { #@test
    # Bug 1: multi-line `opt1|\ ... optN)` groups lost all but one option.
    # The v2 parser joined continuation lines with newlines, but the consumer
    # only split on `|`. Fixed by translating newlines to `|` before splitting.
    local tmpfile
    tmpfile=$(mktemp)
    cat > "$tmpfile" <<'EOF'
    case "$1" in
    --alpha|\
    --beta|\
    --gamma|\
    --delta)
        ;;
    esac
EOF
    COMPREPLY=()
    BU_COMPREPLY_METADATA=()
    declare -A bu_parsed_multiselect_arguments=()
    __bu_autocomplete_completion_func_master_helper "$tmpfile" "" "" --options-at "$tmpfile" 1
    rm -f "$tmpfile"

    # All 4 options must be present
    assert_equal "${COMPREPLY[*]}" "--alpha --beta --gamma --delta"
}

function test_options_of_function_no_blank_rows { #@test
    # Bug 3: `declare -f` pretty-prints case alternations with spaced pipes
    # (a | b | c). Splitting on `|` yielded tokens with leading/trailing
    # whitespace that passed the emptiness check, creating blank COMPREPLY rows.
    # Fixed by trimming whitespace and dropping empty tokens after split.
    function __test_sp_pipes() {
        case "$1" in
        a|b|c)
            ;;
        esac
    }

    COMPREPLY=()
    BU_COMPREPLY_METADATA=()
    declare -A bu_parsed_multiselect_arguments=()
    __bu_autocomplete_completion_func_master_helper __test_sp_pipes "" "" --options-of __test_sp_pipes

    # Must be exactly [a, b, c] with no empty entries
    assert_equal "${#COMPREPLY[@]}" 3
    assert_equal "${COMPREPLY[0]}" "a"
    assert_equal "${COMPREPLY[1]}" "b"
    assert_equal "${COMPREPLY[2]}" "c"
}

# ===========================================================================
# Command-directory scanner hardening
# ===========================================================================

function test_bashtabignore_hides_file { #@test
    # .bashtabignore glob patterns should prevent matching files from
    # being registered as commands.
    local tmpdir
    tmpdir=$(mktemp -d)
    # Pattern: hide any file starting with "hidden-"
    echo 'hidden-*' > "$tmpdir/.bashtabignore"

    # Two minimal scripts (no --is-compatible → assumed compatible)
    printf '#!/usr/bin/env bash\necho visible\n' > "$tmpdir/visible-cmd.sh"
    printf '#!/usr/bin/env bash\necho hidden\n' > "$tmpdir/hidden-cmd.sh"

    # Scan this directory (only)
    local -A saved_dirs=()
    local _d; for _d in "${!BU_COMMAND_SEARCH_DIRS[@]}"; do saved_dirs[$_d]=${BU_COMMAND_SEARCH_DIRS[$_d]}; done
    BU_COMMAND_SEARCH_DIRS=()
    BU_COMMAND_SEARCH_DIRS[$tmpdir]=
    __bu_init_env_commands

    # visible-cmd should be registered, hidden-cmd should not
    assert [ -n "${BU_COMMANDS[visible-cmd]:-}" ]
    assert [ -z "${BU_COMMANDS[hidden-cmd]:-}" ]

    # Restore
    BU_COMMAND_SEARCH_DIRS=()
    for _d in "${!saved_dirs[@]}"; do BU_COMMAND_SEARCH_DIRS[$_d]=${saved_dirs[$_d]}; done
    rm -rf "$tmpdir"
}

function test_converter_reject_code_2 { #@test
    # Converter returning 2 should REJECT the file entirely.
    local tmpdir
    tmpdir=$(mktemp -d)

    printf '#!/usr/bin/env bash\necho ok\n' > "$tmpdir/keep-me.sh"
    printf '#!/usr/bin/env bash\necho nope\n' > "$tmpdir/reject-me.sh"

    # Converter: return 2 for reject-me, 1 for everything else (keep default name)
    __test_reject_converter() {
        [[ "$1" == reject-me.sh ]] && return 2
        return 1
    }

    local -A saved_dirs=()
    local _d; for _d in "${!BU_COMMAND_SEARCH_DIRS[@]}"; do saved_dirs[$_d]=${BU_COMMAND_SEARCH_DIRS[$_d]}; done
    BU_COMMAND_SEARCH_DIRS=()
    BU_COMMAND_SEARCH_DIRS[$tmpdir]=__test_reject_converter
    __bu_init_env_commands

    # keep-me should be registered, reject-me should not
    assert [ -n "${BU_COMMANDS[keep-me]:-}" ]
    assert [ -z "${BU_COMMANDS[reject-me]:-}" ]

    # Restore
    BU_COMMAND_SEARCH_DIRS=()
    for _d in "${!saved_dirs[@]}"; do BU_COMMAND_SEARCH_DIRS[$_d]=${saved_dirs[$_d]}; done
    unset -f __test_reject_converter
    rm -rf "$tmpdir"
}

function test_converter_errexit_safe { #@test
    # A converter returning non-zero (1 or 2) must not abort the scanner
    # under set -e.
    local tmpdir
    tmpdir=$(mktemp -d)

    printf '#!/usr/bin/env bash\necho ok\n' > "$tmpdir/some-cmd.sh"

    __test_nonzero_converter() { return 1; }

    local -A saved_dirs=()
    local _d; for _d in "${!BU_COMMAND_SEARCH_DIRS[@]}"; do saved_dirs[$_d]=${BU_COMMAND_SEARCH_DIRS[$_d]}; done
    BU_COMMAND_SEARCH_DIRS=()
    BU_COMMAND_SEARCH_DIRS[$tmpdir]=__test_nonzero_converter

    # Run under set -e in a subshell; must complete without aborting
    run bash -c "
        set -e
        source '$DIR/../bu_entrypoint.sh' || true
        # Override to scan only our dir
        unset BU_COMMAND_SEARCH_DIRS
        declare -A BU_COMMAND_SEARCH_DIRS=([$tmpdir]=__test_nonzero_converter)
        __bu_init_env_commands
    "
    assert_success

    # Restore
    BU_COMMAND_SEARCH_DIRS=()
    for _d in "${!saved_dirs[@]}"; do BU_COMMAND_SEARCH_DIRS[$_d]=${saved_dirs[$_d]}; done
    unset -f __test_nonzero_converter
    rm -rf "$tmpdir"
}

function test_is_compatible_probe_does_not_recurse { #@test
    # Regression: the old script_template.sh honored --is-compatible AFTER
    # sourcing bu_entrypoint.  The framework probes gated commands with
    # `bash <script> --is-compatible`; that probe re-sourced bu_entrypoint,
    # which re-ran the command scan, which re-probed every gated command —
    # infinite recursion that froze the probe until Ctrl-C.  The probe now
    # sets BU_IS_COMPAT_PROBE=1 and the scan no-ops under it, so probing a
    # script with the old layout still terminates and registers the command.
    local tmpdir
    tmpdir=$(mktemp -d)

    # Old (broken) template: --is-compatible check placed AFTER entrypoint source.
    cat > "$tmpdir/old-style.sh" <<'EOF'
#!/usr/bin/env bash
function __test_old_style_main()
{
if [[ -z "$COMP_CWORD" ]]; then
    source "$BU_DIR"/bu_entrypoint.sh
fi
if [[ "$1" == "--is-compatible" ]]; then
    exit 0
fi
echo hi
}
__test_old_style_main "$@"
EOF

    # Probe via a guarded subprocess; must terminate (no recursion) and
    # register the command.  Lazy mode skips the real command dirs so the
    # temp dir is the only thing scanned.
    run timeout 60 bash -c '
        export BU_COMMAND_CACHE_ENABLED=false
        export BU_COMMAND_SCAN_LAZY=true
        source "$1"/bu_entrypoint.sh || true
        unset BU_COMMAND_SEARCH_DIRS
        declare -A BU_COMMAND_SEARCH_DIRS=(["$2"]=)
        BU_COMMAND_SCAN_LAZY=false
        __bu_init_env_commands
        [[ -n "${BU_COMMANDS[old-style]:-}" ]] && echo REGISTERED || echo NOT_REGISTERED
    ' _ "$DIR/.." "$tmpdir"

    assert_success
    assert_output --partial 'REGISTERED'

    rm -rf "$tmpdir"
}

function test_function_registration_dispatches { #@test
    # Bug fix: bu_preinit_register_user_defined_subcommand_function was
    # using \$file (unset) instead of \$fn, silently breaking function
    # registration. Verify a registered function dispatches.
    __test_func_cmd() { echo 'it works'; }

    bu_preinit_register_user_defined_subcommand_function __test_func_cmd __test-func-cmd function

    run bu __test-func-cmd
    assert_success
    assert_output 'it works'

    unset -f __test_func_cmd
}

# ===========================================================================
# BU_OUT_DIR default-guard and BU_COMMAND_CACHE_ENABLED opt-out
# ===========================================================================

function test_bu_out_dir_survives_preset { #@test
    # Setting BU_OUT_DIR before sourcing bu_entrypoint.sh must survive.
    # The default in bu_config_static.sh is now guarded with :-.
    run bash -c "
        export BU_OUT_DIR=/tmp/test-custom-out-bats
        source '$DIR/../bu_entrypoint.sh' || true
        printf '%s' \"\$BU_OUT_DIR\"
    "
    assert_success
    assert_output --partial '/tmp/test-custom-out-bats'
}

function test_command_cache_disabled_skips_load_and_save { #@test
    # BU_COMMAND_CACHE_ENABLED=false must cause both
    # __bu_try_load_command_cache and bu_mark_load_complete to no-op.
    run bash -c "
        export BU_TOP_LEVEL_MODULE=test-nocache-bats
        export BU_COMMAND_CACHE_ENABLED=false
        source '$DIR/../bu_entrypoint.sh' || true
        [[ \"\$BU_COMMAND_CACHE_LOADED\" == false ]] && echo 'loaded-stays-false'
        bu_mark_load_complete && echo 'mark-is-noop'
        [[ \"\$BU_COMMAND_CACHE_LOADED\" == false ]] && echo 'still-false-after-mark'
    "
    assert_success
    assert_output --partial 'loaded-stays-false'
    assert_output --partial 'mark-is-noop'
    assert_output --partial 'still-false-after-mark'
}

function test_command_scan_lazy_defers_to_first_dispatch { #@test
    # BU_COMMAND_SCAN_LAZY=true must leave the registry near-empty and a
    # pending flag set at entrypoint time; the first by-name dispatch
    # must trigger the scan, populate the registry, and clear the flag.
    run bash -c "
        set -euo pipefail
        # Isolate from any machine-local module list leaked into the env
        # (e.g. a prior activation of another project) — the lazy-scan
        # invariant below is about the builtin framework only.
        unset BU_MODULE_LIST
        export BU_COMMAND_SCAN_LAZY=true
        export BU_COMMAND_CACHE_ENABLED=false
        source '$DIR/../bu_entrypoint.sh' || true
        echo \"after-init count=\${#BU_COMMANDS[@]} pending=\${__BU_COMMAND_SCAN_PENDING:-false}\"
        _all_aliases=true
        for _c in \"\${!BU_COMMANDS[@]}\"; do
            [[ \"\${BU_COMMAND_PROPERTIES[\$_c,type]:-}\" == alias ]] || _all_aliases=false
        done
        echo \"after-init all-aliases=\$_all_aliases\"
        bu get-verb --format jsonl >/dev/null 2>&1 || true
        echo \"after-dispatch count=\${#BU_COMMANDS[@]} pending=\${__BU_COMMAND_SCAN_PENDING:-false}\"
        bu get-verb --format jsonl >/dev/null 2>&1 || true
        echo \"after-second count=\${#BU_COMMANDS[@]} pending=\${__BU_COMMAND_SCAN_PENDING:-false}\"
    "
    assert_success

    # Built-in aliases (e.g. gc, where, select, grep, sort) are registered
    # eagerly in bu_core_preinit.sh — outside the directory scan that lazy mode
    # defers — so the registry is near-empty but not empty. That count, and the
    # fully-populated count, both vary across commits/environments, so assert
    # the scan's *behavior* via relationships instead of hardcoded numbers:
    #   near-empty at init -> strictly larger after first dispatch -> stable.
    local init_count= dispatch_count= second_count=
    [[ "$output" =~ after-init\ count=([0-9]+) ]] && init_count=${BASH_REMATCH[1]}
    [[ "$output" =~ after-dispatch\ count=([0-9]+) ]] && dispatch_count=${BASH_REMATCH[1]}
    [[ "$output" =~ after-second\ count=([0-9]+) ]] && second_count=${BASH_REMATCH[1]}

    assert [ "$init_count" -gt 0 ]
    assert [ "$dispatch_count" -gt "$init_count" ]
    assert_equal "$dispatch_count" "$second_count"

    # Every command present at init is an eagerly-registered alias.
    assert_output --partial 'after-init all-aliases=true'

    # pending must be set until the first dispatch clears it.
    assert_output --partial 'pending=true'
    assert_output --partial 'pending=false'
}

# ===========================================================================
# bu new-command scaffolding: --source vs --source-isolated
# ===========================================================================

function test_scaffold_source_isolated_isolation { #@test
    local tmpdir
    tmpdir=$(mktemp -d)

    # VISUAL=true makes bu_edit_file a no-op (no interactive editor).
    VISUAL=true bu new-command --dir "$tmpdir" --name isolated --source-isolated
    local target="$tmpdir/isolated.sh"
    assert [ -f "$target" ]

    # The isolated scaffold must wrap its body in a subshell and set up
    # its own exit handling inside the parens.
    assert grep -q '^(' "$target"
    assert grep -q 'bu_exit_handler_setup' "$target"

    # Fill the subshell body with mutations that must NOT leak.
    local content
    content=$(<"$target")
    content=${content//'# TODO: implement the command body here'/'cd /; export CANARY=1; printf "caller_var=%s\\n" "$caller_var"'}
    printf '%s\n' "$content" > "$target"

    # Non-exported caller variable: the isolated command must still READ it.
    caller_var=42
    local old_pwd=$PWD
    local out
    out=$(builtin source "$target")
    assert_equal "$out" 'caller_var=42'
    assert_equal "$PWD" "$old_pwd"
    assert [ -z "${CANARY:-}" ]

    rm -rf "$tmpdir"
}

function test_scaffold_source_plain_unchanged { #@test
    local tmpdir
    tmpdir=$(mktemp -d)

    VISUAL=true bu new-command --dir "$tmpdir" --name mutator --source
    local target="$tmpdir/mutator.sh"
    assert [ -f "$target" ]

    # --source output is unchanged: no subshell wrapper, no exec bit.
    refute grep -q '^(' "$target"
    assert [ ! -x "$target" ]

    rm -rf "$tmpdir"
}

# ===========================================================================
# # Dispatch: source header and fallback demotion
# ===========================================================================

function test_scaffold_dispatch_header_and_exec_bit { #@test
    local tmpdir
    tmpdir=$(mktemp -d)

    # --source scaffold: header present, no exec bit.
    VISUAL=true bu new-command --dir "$tmpdir" --name src-cmd --source
    local src="$tmpdir/src-cmd.sh"
    assert grep -q '^# Dispatch: source' "$src"
    assert [ ! -x "$src" ]

    # Plain scaffold: no header, exec bit present.
    VISUAL=true bu new-command --dir "$tmpdir" --name exec-cmd
    local execf="$tmpdir/exec-cmd.sh"
    refute grep -q '^# Dispatch: source' "$execf"
    assert [ -x "$execf" ]

    rm -rf "$tmpdir"
}

function test_dispatch_fallback_demotion_warns { #@test
    local tmpdir
    tmpdir=$(mktemp -d)
    printf '#!/usr/bin/env bash\nexport DEMO_POLLUTED=yes\n' > "$tmpdir/demo-oops.sh"
    chmod 644 "$tmpdir/demo-oops.sh"

    local -A saved_dirs=()
    local _d
    for _d in "${!BU_COMMAND_SEARCH_DIRS[@]}"; do saved_dirs[$_d]=${BU_COMMAND_SEARCH_DIRS[$_d]}; done
    BU_COMMAND_SEARCH_DIRS=()
    BU_COMMAND_SEARCH_DIRS[$tmpdir]=
    __bu_init_env_commands

    # Dispatch warns, naming the file and the header that silences it.
    run bu demo-oops
    assert_output --partial '# Dispatch: source'
    assert_output --partial 'demo-oops'

    # It is still sourced (backward compatibility).
    __bu_cli_command_type demo-oops 2>/dev/null
    assert_equal "$BU_RET" source

    BU_COMMAND_SEARCH_DIRS=()
    for _d in "${!saved_dirs[@]}"; do BU_COMMAND_SEARCH_DIRS[$_d]=${saved_dirs[$_d]}; done
    rm -rf "$tmpdir"
}

function test_dispatch_declared_source_no_warning { #@test
    local tmpdir
    tmpdir=$(mktemp -d)
    printf '#!/usr/bin/env bash\n# Dispatch: source\nexport DEMO_SRC=yes\n' > "$tmpdir/demo-src.sh"
    chmod 644 "$tmpdir/demo-src.sh"

    local -A saved_dirs=()
    local _d
    for _d in "${!BU_COMMAND_SEARCH_DIRS[@]}"; do saved_dirs[$_d]=${BU_COMMAND_SEARCH_DIRS[$_d]}; done
    BU_COMMAND_SEARCH_DIRS=()
    BU_COMMAND_SEARCH_DIRS[$tmpdir]=
    __bu_init_env_commands

    # Header registers explicit source type.
    assert_equal "${BU_COMMAND_PROPERTIES[demo-src,type]:-}" source

    # Dispatch sources without any fallback warning.
    run bu demo-src
    assert_success
    refute_output --partial '# Dispatch: source'

    BU_COMMAND_SEARCH_DIRS=()
    for _d in "${!saved_dirs[@]}"; do BU_COMMAND_SEARCH_DIRS[$_d]=${saved_dirs[$_d]}; done
    rm -rf "$tmpdir"
}

function test_dispatch_declared_source_exec_bit_warns { #@test
    local tmpdir
    tmpdir=$(mktemp -d)
    printf '#!/usr/bin/env bash\n# Dispatch: source\ncd /tmp\n' > "$tmpdir/demo-src-x.sh"
    chmod +x "$tmpdir/demo-src-x.sh"

    local -A saved_dirs=()
    local _d
    for _d in "${!BU_COMMAND_SEARCH_DIRS[@]}"; do saved_dirs[$_d]=${BU_COMMAND_SEARCH_DIRS[$_d]}; done
    BU_COMMAND_SEARCH_DIRS=()
    BU_COMMAND_SEARCH_DIRS[$tmpdir]=
    local warnfile=$BATS_TEST_TMPDIR/scan-warn.txt
    __bu_init_env_commands 2>"$warnfile"

    # Header still registers source, but the exec bit draws a scan warning.
    assert_equal "${BU_COMMAND_PROPERTIES[demo-src-x,type]:-}" source
    assert grep -q '# Dispatch: source' "$warnfile"
    assert grep -q 'demo-src-x' "$warnfile"

    BU_COMMAND_SEARCH_DIRS=()
    for _d in "${!saved_dirs[@]}"; do BU_COMMAND_SEARCH_DIRS[$_d]=${saved_dirs[$_d]}; done
    rm -rf "$tmpdir"
}

function test_register_funnel_settles_type_on_rescan { #@test
    # The write-funnel invariant: registering a definition settles the type.
    # The dispatch type cache is populated lazily; a rescan of a headerless
    # file must INVALIDATE the cached type — else chmod +x between scans
    # leaves type=source over an executable and dispatch sources it into
    # the caller's shell (env/cwd pollution).
    local tmpdir
    tmpdir=$(mktemp -d)
    printf '#!/usr/bin/env bash\necho ran\n' > "$tmpdir/flip-cmd.sh"
    # no exec bit, no # Dispatch: header

    local -A saved_dirs=()
    local _d; for _d in "${!BU_COMMAND_SEARCH_DIRS[@]}"; do saved_dirs[$_d]=${BU_COMMAND_SEARCH_DIRS[$_d]}; done
    BU_COMMAND_SEARCH_DIRS=()
    BU_COMMAND_SEARCH_DIRS[$tmpdir]=
    __bu_init_env_commands

    # Dispatch once: lazily derives + caches type=source (fallback demotion)
    bu flip-cmd &>/dev/null || true
    assert_equal "${BU_COMMAND_PROPERTIES[flip-cmd,type]}" source

    # File becomes executable; the rescan must clear the stale cached type...
    chmod +x "$tmpdir/flip-cmd.sh"
    __bu_init_env_commands
    assert [ -z "${BU_COMMAND_PROPERTIES[flip-cmd,type]:-}" ]

    # ...so the next dispatch re-derives execute from the exec bit.
    bu flip-cmd &>/dev/null || true
    assert_equal "${BU_COMMAND_PROPERTIES[flip-cmd,type]}" execute

    # A declared header still wins over the exec bit on rescan.
    printf '#!/usr/bin/env bash\n# Dispatch: source\necho ran\n' > "$tmpdir/flip-cmd.sh"
    __bu_init_env_commands
    assert_equal "${BU_COMMAND_PROPERTIES[flip-cmd,type]}" source

    BU_COMMAND_SEARCH_DIRS=()
    for _d in "${!saved_dirs[@]}"; do BU_COMMAND_SEARCH_DIRS[$_d]=${saved_dirs[$_d]}; done
    rm -rf "$tmpdir"
}

function test_register_funnel_alias_over_command_and_back { #@test
    # Cross-kind re-registration keeps the (definition,type) pair coherent
    # in both directions: alias-over-file writes type=alias atomically;
    # file-over-alias settles (invalidates) so dispatch re-derives from the
    # file rather than word-splitting a path as an alias spec.
    local tmpdir
    tmpdir=$(mktemp -d)
    printf '#!/usr/bin/env bash\necho from-file\n' > "$tmpdir/pair-cmd.sh"
    chmod +x "$tmpdir/pair-cmd.sh"

    local -A saved_dirs=()
    local _d; for _d in "${!BU_COMMAND_SEARCH_DIRS[@]}"; do saved_dirs[$_d]=${BU_COMMAND_SEARCH_DIRS[$_d]}; done
    BU_COMMAND_SEARCH_DIRS=()
    BU_COMMAND_SEARCH_DIRS[$tmpdir]=
    __bu_init_env_commands
    bu pair-cmd &>/dev/null || true
    assert_equal "${BU_COMMAND_PROPERTIES[pair-cmd,type]}" execute

    # Alias overwrites the name: pair flips together.
    bu_preinit_register_new_alias pair-cmd get-command '{...}'
    assert_equal "${BU_COMMAND_PROPERTIES[pair-cmd,type]}" alias
    assert_equal "${BU_COMMANDS[pair-cmd]}" "get-command {...}"

    # File re-registers over the alias: type settles, dispatch runs the file.
    __bu_init_env_commands
    assert [ -z "${BU_COMMAND_PROPERTIES[pair-cmd,type]:-}" ]
    run bu pair-cmd
    assert_success
    assert_output --partial from-file

    unset 'BU_COMMANDS[pair-cmd]'
    unset 'BU_COMMAND_PROPERTIES[pair-cmd,type]'
    BU_COMMAND_SEARCH_DIRS=()
    for _d in "${!saved_dirs[@]}"; do BU_COMMAND_SEARCH_DIRS[$_d]=${saved_dirs[$_d]}; done
    rm -rf "$tmpdir"
}

function test_collision_incumbent_toplevel_wins_bare_name { #@test
    # Layer 2 precedence: lower rank (top-level=1) keeps the bare name;
    # the higher-rank newcomer is parked in the qualified store and stays
    # dispatchable as :<ns>:<cmd>. get-command style properties record the
    # shadow link.
    local tmpdir
    tmpdir=$(mktemp -d)
    printf '#!/usr/bin/env bash\necho FROM-TOP\n' > "$tmpdir/t.sh"
    printf '#!/usr/bin/env bash\necho FROM-DEP\n' > "$tmpdir/d.sh"
    chmod +x "$tmpdir/t.sh" "$tmpdir/d.sh"
    BU_MODULE_RANK[topmod]=1
    BU_MODULE_RANK[depmod]=2

    __bu_command_register coll-a "$tmpdir/t.sh" --module topmod
    # NOT `run` and NOT $(...) capture: both are subshells, and the parking
    # writes would vanish with them. Registration runs in THIS shell; the
    # collision message is checked via a stderr file.
    __bu_command_register coll-a "$tmpdir/d.sh" --module depmod 2>"$tmpdir/msg"
    grep -q collision "$tmpdir/msg"

    run bu coll-a
    assert_output --partial FROM-TOP
    run bu :depmod:coll-a
    assert_output --partial FROM-DEP
    assert_equal "${BU_COMMAND_PROPERTIES[coll-a,shadows]}" ":depmod:coll-a"

    unset 'BU_COMMANDS[coll-a]' 'BU_COMMANDS_QUALIFIED[:depmod:coll-a]'
    unset 'BU_MODULE_RANK[topmod]' 'BU_MODULE_RANK[depmod]'
    rm -rf "$tmpdir"
}

function test_collision_newcomer_toplevel_demotes_incumbent { #@test
    # Reverse arrival order: the dependency registered first; the top-level
    # demotes it into the qualified store and takes the bare name. Both
    # spellings dispatch their own definition afterwards.
    local tmpdir
    tmpdir=$(mktemp -d)
    printf '#!/usr/bin/env bash\necho FROM-TOP\n' > "$tmpdir/t.sh"
    printf '#!/usr/bin/env bash\necho FROM-DEP\n' > "$tmpdir/d.sh"
    chmod +x "$tmpdir/t.sh" "$tmpdir/d.sh"
    BU_MODULE_RANK[topmod]=1
    BU_MODULE_RANK[depmod]=2

    __bu_command_register coll-b "$tmpdir/d.sh" --module depmod
    __bu_command_register coll-b "$tmpdir/t.sh" --module topmod 2>/dev/null

    run bu coll-b
    assert_output --partial FROM-TOP
    run bu :depmod:coll-b
    assert_output --partial FROM-DEP
    run bu :topmod:coll-b
    assert_output --partial FROM-TOP

    unset 'BU_COMMANDS[coll-b]' 'BU_COMMANDS_QUALIFIED[:depmod:coll-b]'
    unset 'BU_MODULE_RANK[topmod]' 'BU_MODULE_RANK[depmod]'
    rm -rf "$tmpdir"
}

function test_collision_same_module_rescan_is_not_a_collision { #@test
    local tmpdir
    tmpdir=$(mktemp -d)
    printf '#!/usr/bin/env bash\necho hi\n' > "$tmpdir/r.sh"
    chmod +x "$tmpdir/r.sh"
    BU_MODULE_RANK[modx]=2

    __bu_command_register coll-c "$tmpdir/r.sh" --module modx
    run __bu_command_register coll-c "$tmpdir/r.sh" --module modx
    refute_output --partial "collision"

    unset 'BU_COMMANDS[coll-c]' 'BU_MODULE_RANK[modx]'
    rm -rf "$tmpdir"
}

function test_collision_session_registration_beats_all { #@test
    # Rank 0 (no module: interactive/session registration) wins over the
    # top-level; the demoted command stays reachable qualified.
    local tmpdir
    tmpdir=$(mktemp -d)
    printf '#!/usr/bin/env bash\necho FROM-TOP\n' > "$tmpdir/t.sh"
    chmod +x "$tmpdir/t.sh"
    BU_MODULE_RANK[topmod]=1
    __coll_sess_fn() { echo FROM-SESSION; }

    __bu_command_register coll-d "$tmpdir/t.sh" --module topmod
    __bu_command_register coll-d __coll_sess_fn --type function --module "" 2>/dev/null

    run bu coll-d
    assert_output --partial FROM-SESSION
    run bu :topmod:coll-d
    assert_output --partial FROM-TOP

    unset 'BU_COMMANDS[coll-d]' 'BU_COMMANDS_QUALIFIED[:topmod:coll-d]'
    unset 'BU_MODULE_RANK[topmod]'
    unset -f __coll_sess_fn
    rm -rf "$tmpdir"
}

function test_module_rank_built_from_module_list_order { #@test
    # BU_MODULE_RANK derives from BU_MODULE_LIST order: top-level=1,
    # dependencies in list order; the framework is pinned at 900.
    run bash -c '
        export BU_MODULE_LIST="alpha:1:/x/a.sh;beta:1:/x/b.sh;gamma:1:/x/c.sh;"
        source "'"$DIR"'/../bu_entrypoint.sh" >/dev/null 2>&1
        echo "a=${BU_MODULE_RANK[alpha]} b=${BU_MODULE_RANK[beta]} g=${BU_MODULE_RANK[gamma]} bu=${BU_MODULE_RANK[bu]}"
    '
    assert_output --partial "a=1 b=2 g=3 bu=900"
}

function test_get_command_shadow_fields_and_all { #@test
    # Layer 3 introspection: the winner carries shadows, --all includes the
    # parked loser with the reverse shadowed_by link, and empty shadow
    # fields serialize as typed nulls so -isnotnull audits are exact.

    local tmpdir
    tmpdir=$(mktemp -d)
    printf '#!/usr/bin/env bash\necho A\n' > "$tmpdir/t.sh"
    printf '#!/usr/bin/env bash\necho B\n' > "$tmpdir/d.sh"
    chmod +x "$tmpdir/t.sh" "$tmpdir/d.sh"
    BU_MODULE_RANK[topmod]=1
    BU_MODULE_RANK[depmod]=2
    __bu_command_register coll-e "$tmpdir/t.sh" --module topmod
    __bu_command_register coll-e "$tmpdir/d.sh" --module depmod 2>/dev/null

    # Default listing: winner only, shadows set, loser absent.
    run bu get-command --format jsonl
    assert_output --partial '"name":"coll-e"'
    refute_output --partial '"name":":depmod:coll-e"'

    local winner
    winner=$(bu get-command --format jsonl | "$BU_OUT_JQ" -c 'select(.name == "coll-e")')
    assert_equal "$(printf '%s' "$winner" | "$BU_OUT_JQ" -r .shadows)" ":depmod:coll-e"

    # --all: the loser appears with the reverse link.
    local loser
    loser=$(bu get-command --all --format jsonl | "$BU_OUT_JQ" -c 'select(.name == ":depmod:coll-e")')
    assert_equal "$(printf '%s' "$loser" | "$BU_OUT_JQ" -r .shadowed_by)" "coll-e"

    # Reads are subshell-safe (only registration writes are not).
    local audit
    audit=$(bu get-command --all --format jsonl | bu query-object where shadowed_by -isnotnull)
    [[ "$audit" == *':depmod:coll-e'* ]]
    [[ "$audit" != *'"name":"get-command"'* ]]

    unset 'BU_COMMANDS[coll-e]' 'BU_COMMANDS_QUALIFIED[:depmod:coll-e]'
    unset 'BU_MODULE_RANK[topmod]' 'BU_MODULE_RANK[depmod]'
    rm -rf "$tmpdir"
}

function test_completion_offers_shadowed_qualified_names { #@test
    # A parked loser Tab-completes: :<ns>:<TAB> offers it, and :<TAB>
    # includes a namespace that exists only in the qualified store.

    local tmpdir
    tmpdir=$(mktemp -d)
    printf '#!/usr/bin/env bash\necho A\n' > "$tmpdir/t.sh"
    printf '#!/usr/bin/env bash\necho B\n' > "$tmpdir/d.sh"
    chmod +x "$tmpdir/t.sh" "$tmpdir/d.sh"
    BU_MODULE_RANK[topmod]=1
    BU_MODULE_RANK[shadowns]=2
    __bu_command_register coll-f "$tmpdir/t.sh" --module topmod
    __bu_command_register coll-f "$tmpdir/d.sh" --module shadowns 2>/dev/null

    COMP_WORDS=("$BU_CLI_COMMAND_NAME" ":shadowns:")
    COMP_CWORD=1
    COMP_LINE="$BU_CLI_COMMAND_NAME :shadowns:"
    COMP_POINT=${#COMP_LINE}
    COMPREPLY=()
    __bu_autocomplete_completion_func_cli "$BU_CLI_COMMAND_NAME" ":shadowns:" "" 2>/dev/null
    local joined="${COMPREPLY[*]}"
    [[ "$joined" == *":shadowns:coll-f"* ]]

    COMP_WORDS=("$BU_CLI_COMMAND_NAME" ":")
    COMP_CWORD=1
    COMP_LINE="$BU_CLI_COMMAND_NAME :"
    COMP_POINT=${#COMP_LINE}
    COMPREPLY=()
    # || true: the namespace-list arm calls compopt, which errors outside a
    # real completion context (fatal under bats errexit); COMPREPLY is
    # still populated before that point.
    __bu_autocomplete_completion_func_cli "$BU_CLI_COMMAND_NAME" ":" "" 2>/dev/null || true
    local _c _found=false
    for _c in "${COMPREPLY[@]}"
    do
        [[ "$_c" == *shadowns* ]] && { _found=true; break; }
    done
    "$_found"

    unset 'BU_COMMANDS[coll-f]' 'BU_COMMANDS_QUALIFIED[:shadowns:coll-f]'
    unset 'BU_MODULE_RANK[topmod]' 'BU_MODULE_RANK[shadowns]'
    rm -rf "$tmpdir"
}

# ===========================================================================
# Compat-cache staleness
# ===========================================================================

# A gated command whose --is-compatible probe checks a binary that is NOT
# part of the BU_CAP fingerprint (which only hashes the probed binaries).
# This is the dynamic-dependency case: the fingerprint does not change when
# this binary appears/disappears, so a stale compat cache would otherwise
# register a broken command.
__write_gated_fixture()
{
    local dir=$1
    cat > "$dir/get-gated.sh" <<'EOF'
#!/usr/bin/env bash
# Dispatch: source
function __bu_get_gated_main()
{
if [[ "$1" == "--is-compatible" ]]; then
    command -v bu_test_gated_dep &>/dev/null || { echo "bu_test_gated_dep required" >&2; exit 1; }
    exit 0
fi
echo gated
}
__bu_get_gated_main "$@"
EOF
}

# Same as __write_gated_fixture but with a distinctive body marker so tests
# can assert that the script body never executed.
__write_gated_fixture_body_marker()
{
    local dir=$1
    cat > "$dir/get-gated.sh" <<'EOF'
#!/usr/bin/env bash
# Dispatch: source
function __bu_get_gated_main()
{
if [[ "$1" == "--is-compatible" ]]; then
    command -v bu_test_gated_dep &>/dev/null || { echo "bu_test_gated_dep required" >&2; exit 1; }
    exit 0
fi
echo DEFERRED_BODY_RAN
}
__bu_get_gated_main "$@"
EOF
}

function test_compat_cache_bypassed_when_command_cache_disabled { #@test
    local tmpdir
    tmpdir=$(mktemp -d)
    local cache_dir="$BATS_TEST_TMPDIR/out"
    local bindir="$BATS_TEST_TMPDIR/bin"
    __write_gated_fixture "$tmpdir"

    # Act 1: caching ENABLED, dependency missing. The probe fails, the command
    # is marked unavailable, and the compat cache is persisted.
    run timeout 60 bash -c '
        export BU_OUT_DIR="$1"
        export BU_COMMAND_CACHE_ENABLED=true
        export BU_COMMAND_SCAN_LAZY=true
        unset BU_TOP_LEVEL_MODULE BU_MODULE_LIST
        source "$2"/bu_entrypoint.sh || true
        unset BU_COMMAND_SEARCH_DIRS
        declare -A BU_COMMAND_SEARCH_DIRS=(["$3"]=)
        BU_COMMAND_SCAN_LAZY=false
        __bu_init_env_commands
        [[ -n "${BU_COMMANDS[get-gated]:-}" ]] && echo "ACT1=REGISTERED" || echo "ACT1=UNAVAILABLE"
        grep -l "get-gated" "$1"/cache/compat-*.cache >/dev/null 2>&1 && echo "ACT1=CACHED" || echo "ACT1=NOT_CACHED"
    ' _ "$cache_dir" "$DIR/.." "$tmpdir"
    assert_success
    assert_output --partial "ACT1=UNAVAILABLE"
    assert_output --partial "ACT1=CACHED"

    # Make the dependency appear on PATH.
    mkdir -p "$bindir"
    printf '#!/usr/bin/env bash\n' > "$bindir/bu_test_gated_dep"
    chmod +x "$bindir/bu_test_gated_dep"

    # Act 2: caching DISABLED, dependency present. The per-environment compat
    # cache must be BYPASSED (not just the command cache): a fresh probe runs
    # and registers the command despite the stale "unavailable" entry.
    run timeout 60 bash -c '
        export BU_OUT_DIR="$1"
        export PATH="$2:$PATH"
        export BU_COMMAND_CACHE_ENABLED=false
        export BU_COMMAND_SCAN_LAZY=true
        unset BU_TOP_LEVEL_MODULE BU_MODULE_LIST
        source "$3"/bu_entrypoint.sh || true
        unset BU_COMMAND_SEARCH_DIRS
        declare -A BU_COMMAND_SEARCH_DIRS=(["$4"]=)
        BU_COMMAND_SCAN_LAZY=false
        __bu_init_env_commands
        [[ -n "${BU_COMMANDS[get-gated]:-}" ]] && echo "ACT2=REGISTERED" || echo "ACT2=UNAVAILABLE"
        [[ -z "${BU_COMPAT_CACHE_FILE:-}" ]] && echo "ACT2=NO_CACHE_LOADED" || echo "ACT2=CACHE_LOADED"
    ' _ "$cache_dir" "$bindir" "$DIR/.." "$tmpdir"
    assert_success
    assert_output --partial "ACT2=REGISTERED"
    assert_output --partial "ACT2=NO_CACHE_LOADED"

    rm -rf "$tmpdir" "$bindir" "$cache_dir"
}

function test_compat_reprobe_recovers_after_dep_appears { #@test
    local tmpdir
    tmpdir=$(mktemp -d)
    local bindir="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$bindir"
    __write_gated_fixture "$tmpdir"

    run timeout 60 bash -c '
        export BU_OUT_DIR="$1"
        export BU_COMMAND_CACHE_ENABLED=false
        export BU_COMMAND_SCAN_LAZY=true
        unset BU_TOP_LEVEL_MODULE BU_MODULE_LIST
        source "$2"/bu_entrypoint.sh || true
        unset BU_COMMAND_SEARCH_DIRS
        declare -A BU_COMMAND_SEARCH_DIRS=(["$3"]=)
        BU_COMMAND_SCAN_LAZY=false
        __bu_init_env_commands
        [[ -z "${BU_COMMANDS[get-gated]:-}" ]] && echo "BEFORE=UNAVAILABLE" || echo "BEFORE=REGISTERED"
        [[ -n "${BU_COMMAND_UNAVAILABLE[get-gated]:-}" ]] && echo "BEFORE=REASON:${BU_COMMAND_UNAVAILABLE[get-gated]}"

        # Make the missing dependency appear on PATH, then reprobe.
        printf "#!/usr/bin/env bash\n" > "$4/bu_test_gated_dep"
        chmod +x "$4/bu_test_gated_dep"
        export PATH="$4:$PATH"
        bu_cap_reprobe_unavailable get-gated

        [[ -n "${BU_COMMANDS[get-gated]:-}" ]] && echo "AFTER=REGISTERED" || echo "AFTER=UNAVAILABLE"
        [[ -z "${BU_COMMAND_UNAVAILABLE[get-gated]:-}" ]] && echo "AFTER=REASON_CLEARED" || echo "AFTER=REASON:${BU_COMMAND_UNAVAILABLE[get-gated]}"
    ' _ "$BATS_TEST_TMPDIR/out" "$DIR/.." "$tmpdir" "$bindir"
    assert_success
    assert_output --partial "BEFORE=UNAVAILABLE"
    assert_output --partial "BEFORE=REASON:bu_test_gated_dep required"
    assert_output --partial "AFTER=REGISTERED"
    assert_output --partial "AFTER=REASON_CLEARED"

    rm -rf "$tmpdir" "$bindir" "$BATS_TEST_TMPDIR/out"
}

function test_compat_deferred_scan_skips_probe { #@test
    local tmpdir
    tmpdir=$(mktemp -d)
    local cache_dir="$BATS_TEST_TMPDIR/out"
    __write_gated_fixture "$tmpdir"

    # Deferred mode + caching disabled: the scan must register the gated
    # command optimistically (pending marker) and must NOT probe it or
    # persist a compat cache.
    run timeout 60 bash -c '
        export BU_OUT_DIR="$1"
        export BU_COMMAND_CACHE_ENABLED=false
        export BU_COMMAND_COMPAT_DEFERRED=true
        export BU_COMMAND_SCAN_LAZY=true
        unset BU_TOP_LEVEL_MODULE BU_MODULE_LIST
        source "$2"/bu_entrypoint.sh || true
        unset BU_COMMAND_SEARCH_DIRS
        declare -A BU_COMMAND_SEARCH_DIRS=(["$3"]=)
        BU_COMMAND_SCAN_LAZY=false
        __bu_init_env_commands
        [[ -n "${BU_COMMANDS[get-gated]:-}" ]] && echo "REGISTERED" || echo "UNAVAILABLE"
        [[ -n "${BU_COMMAND_PROPERTIES[get-gated,compat_pending]:-}" ]] && echo "PENDING" || echo "NOT_PENDING"
        ls "$1"/cache/compat-*.cache >/dev/null 2>&1 && echo "CACHE_WRITTEN" || echo "NO_CACHE"
    ' _ "$cache_dir" "$DIR/.." "$tmpdir"
    assert_success
    assert_output --partial "REGISTERED"
    assert_output --partial "PENDING"
    assert_output --partial "NO_CACHE"

    rm -rf "$tmpdir" "$cache_dir"
}

function test_compat_deferred_compatible_dispatch_consumes_marker { #@test
    local tmpdir bindir
    tmpdir=$(mktemp -d)
    bindir="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$bindir"
    printf '#!/usr/bin/env bash\n' > "$bindir/bu_test_gated_dep"
    chmod +x "$bindir/bu_test_gated_dep"
    __write_gated_fixture "$tmpdir"

    # First dispatch of a COMPATIBLE gated command works and consumes the
    # pending marker.
    run timeout 60 bash -c '
        export BU_OUT_DIR="$1"
        export PATH="$2:$PATH"
        export BU_COMMAND_CACHE_ENABLED=false
        export BU_COMMAND_COMPAT_DEFERRED=true
        export BU_COMMAND_SCAN_LAZY=true
        unset BU_TOP_LEVEL_MODULE BU_MODULE_LIST
        source "$3"/bu_entrypoint.sh || true
        unset BU_COMMAND_SEARCH_DIRS
        declare -A BU_COMMAND_SEARCH_DIRS=(["$4"]=)
        BU_COMMAND_SCAN_LAZY=false
        __bu_init_env_commands
        [[ -n "${BU_COMMAND_PROPERTIES[get-gated,compat_pending]:-}" ]] && echo "PENDING_BEFORE"
        bu get-gated
        echo "DISPATCH_RC=$?"
        [[ -z "${BU_COMMAND_PROPERTIES[get-gated,compat_pending]:-}" ]] && echo "PENDING_CLEARED" || echo "PENDING_STILL_SET"
        [[ -n "${BU_COMMANDS[get-gated]:-}" ]] && echo "STILL_REGISTERED"
    ' _ "$BATS_TEST_TMPDIR/out" "$bindir" "$DIR/.." "$tmpdir"
    assert_success
    assert_output --partial "PENDING_BEFORE"
    assert_output --partial "DISPATCH_RC=0"
    assert_output --partial "PENDING_CLEARED"
    assert_output --partial "STILL_REGISTERED"
    assert_output --partial "gated"

    rm -rf "$tmpdir" "$bindir" "$BATS_TEST_TMPDIR/out"
}

function test_compat_deferred_incompatible_dispatch_settles_once { #@test
    local tmpdir
    tmpdir=$(mktemp -d)
    __write_gated_fixture_body_marker "$tmpdir"

    # First dispatch of an INCOMPATIBLE gated command errors with the probe
    # reason, does not execute the body, and stays unavailable on the second
    # dispatch (the pending marker settles exactly once).
    run timeout 60 bash -c '
        export BU_OUT_DIR="$1"
        export BU_COMMAND_CACHE_ENABLED=false
        export BU_COMMAND_COMPAT_DEFERRED=true
        export BU_COMMAND_SCAN_LAZY=true
        unset BU_TOP_LEVEL_MODULE BU_MODULE_LIST
        source "$2"/bu_entrypoint.sh || true
        unset BU_COMMAND_SEARCH_DIRS
        declare -A BU_COMMAND_SEARCH_DIRS=(["$3"]=)
        BU_COMMAND_SCAN_LAZY=false
        __bu_init_env_commands
        bu get-gated
        echo "DISPATCH1_RC=$?"
        [[ -z "${BU_COMMANDS[get-gated]:-}" ]] && echo "REMOVED1"
        [[ -n "${BU_COMMAND_UNAVAILABLE[get-gated]:-}" ]] && echo "REASON1:${BU_COMMAND_UNAVAILABLE[get-gated]}"
        bu get-gated
        echo "DISPATCH2_RC=$?"
        [[ -z "${BU_COMMANDS[get-gated]:-}" ]] && echo "REMOVED2"
        [[ -n "${BU_COMMAND_UNAVAILABLE[get-gated]:-}" ]] && echo "REASON2:${BU_COMMAND_UNAVAILABLE[get-gated]}"
    ' _ "$BATS_TEST_TMPDIR/out" "$DIR/.." "$tmpdir"
    assert_success
    refute_output --partial "DEFERRED_BODY_RAN"
    assert_output --partial "DISPATCH1_RC=1"
    assert_output --partial "REMOVED1"
    assert_output --partial "REASON1:bu_test_gated_dep required"
    assert_output --partial "DISPATCH2_RC=1"
    assert_output --partial "REMOVED2"
    assert_output --partial "REASON2:bu_test_gated_dep required"

    rm -rf "$tmpdir" "$BATS_TEST_TMPDIR/out"
}

function test_compat_deferred_alias_dispatch_errors { #@test
    local tmpdir
    tmpdir=$(mktemp -d)
    __write_gated_fixture_body_marker "$tmpdir"

    # An incompatible gated command reached through an alias must also be
    # probed on first dispatch (alias execution bypasses the top-level lookup).
    run timeout 60 bash -c '
        export BU_OUT_DIR="$1"
        export BU_COMMAND_CACHE_ENABLED=false
        export BU_COMMAND_COMPAT_DEFERRED=true
        export BU_COMMAND_SCAN_LAZY=true
        unset BU_TOP_LEVEL_MODULE BU_MODULE_LIST
        source "$2"/bu_entrypoint.sh || true
        unset BU_COMMAND_SEARCH_DIRS
        declare -A BU_COMMAND_SEARCH_DIRS=(["$3"]=)
        BU_COMMAND_SCAN_LAZY=false
        __bu_init_env_commands
        bu_preinit_register_new_alias g get-gated
        bu g
        echo "ALIAS1_RC=$?"
        [[ -n "${BU_COMMAND_UNAVAILABLE[get-gated]:-}" ]] && echo "REASON1:${BU_COMMAND_UNAVAILABLE[get-gated]}"
        bu g
        echo "ALIAS2_RC=$?"
        [[ -n "${BU_COMMAND_UNAVAILABLE[get-gated]:-}" ]] && echo "REASON2:${BU_COMMAND_UNAVAILABLE[get-gated]}"
    ' _ "$BATS_TEST_TMPDIR/out" "$DIR/.." "$tmpdir"
    assert_success
    refute_output --partial "DEFERRED_BODY_RAN"
    assert_output --partial "ALIAS1_RC=1"
    assert_output --partial "REASON1:bu_test_gated_dep required"
    assert_output --partial "ALIAS2_RC=1"
    assert_output --partial "REASON2:bu_test_gated_dep required"

    rm -rf "$tmpdir" "$BATS_TEST_TMPDIR/out"
}




