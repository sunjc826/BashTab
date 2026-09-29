#!/usr/bin/env -S bats --jobs 1

# Test the fzf formatting step: given COMPREPLY + BU_COMPREPLY_METADATA,
# verify the delimited lines that fzf actually receives.
# Does NOT require fzf — only exercises the stitching logic.

setup() {
    load "test_helper/bats-assert/load.bash"
    load "test_helper/bats-support/load.bash"
    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    source "$DIR"/../bu_entrypoint.sh
    source "$BU_NULL"
}

# Replicate the fzf formatting logic from __bu_bind_fzf_autocomplete_impl.
# Modifies COMPREPLY in-place to delimited fzf lines.
_fzf_format() {
    local box_length=${1:-60}
    local is_ansi=${2:-false}
    local delimiter=$'\x01'
    local -a bu_compreply_metadata_no_ansi=()
    
    if ((${#BU_COMPREPLY_METADATA[@]})); then
        mapfile -t bu_compreply_metadata_no_ansi < <(
            sed -r -e 's/\\n/ /g' -e "s/\x1B\[([0-9]{1,3}(;[0-9]{1,3})*)?[mGK]//g" < <(printf "%s\n" "${BU_COMPREPLY_METADATA[@]}")
        )
    fi

    local -a bu_compreply_metadata_colored=("${BU_COMPREPLY_METADATA[@]}")
    BU_COMPREPLY_METADATA=("${BU_COMPREPLY_METADATA[@]//$'\E'/'__ANSI__'}")

    local i _trim pad min_pad=1
    local -a compreply_no_color=()
    if "$is_ansi"; then
        mapfile -t compreply_no_color < <(sed -r -e 's/\x1B\(B\x1B\[m//g' -e "s/\x1B\[([0-9]{1,3}(;[0-9]{1,3})*)?[mGK]//g" < <(printf "%s\n" "${COMPREPLY[@]}"))
    fi

    for i in "${!bu_compreply_metadata_no_ansi[@]}"; do
        local clen
        if "$is_ansi"; then clen=${#compreply_no_color[i]}
        else clen=${#COMPREPLY[i]}; fi
        _trim=$((box_length - clen))
        ((_trim < 0)) && _trim=0
        bu_compreply_metadata_no_ansi[i]=${bu_compreply_metadata_no_ansi[i]:0:$_trim}
        pad=$((box_length - clen - ${#bu_compreply_metadata_no_ansi[i]}))
        local padding=${__BU_PADDING_TABLE[pad > min_pad ? pad : min_pad]}
        COMPREPLY[i]=${COMPREPLY[i]}${delimiter}${padding}${bu_compreply_metadata_colored[i]}${delimiter}${BU_COMPREPLY_METADATA[i]}
    done
}

# Simulate full selection pipeline: format → fzf → strip → space-add → final line.
# Takes COMPREPLY + BU_COMPREPLY_METADATA (already populated), formats them,
# simulates selecting the entry whose completion matches $2, and returns
# the final command line in $BU_RET.
# $1: command prefix (e.g. "docker")
# $2: completion to select (e.g. "images")
# $3: is_nospace flag (true/false) — static compspec nospace
# $4: is_filenames flag (true/false)
# $5: is_dynamic_nospace flag (true/false) — compopt -o nospace during completion
_simulate_selection() {
    local cmd=$1 target=$2 is_nospace=$3 is_filenames=$4 is_dynamic_nospace=${5:-false}
    local D=$'\x01'

    # Format for fzf
    _fzf_format 60 false

    # Find and "select" the target line (simulate fzf returning the raw line)
    local i selected=""
    for ((i=0; i<${#COMPREPLY[@]}; i++)); do
        local cand="${COMPREPLY[$i]%%$D*}"
        if [[ "$cand" == "$target" ]]; then
            selected="${COMPREPLY[$i]}"
            break
        fi
    done
    [[ -z "$selected" ]] && { BU_RET=""; return 1; }

    # Delimiter stripping (same as production)
    if ((${#BU_COMPREPLY_METADATA[@]})); then
        selected="${selected%%"${D}"*}"
    fi

    # Build command line
    local -a cmd_line=($cmd "$selected")
    local rl="${cmd_line[*]}"
    local cmd_back=""

    # Space-adding logic (exactly from production)
    if ! "$is_dynamic_nospace" && \
       ! { "$is_filenames" && [[ "${rl:${#rl}-1}" = / ]]; } && \
       ! { "$is_nospace" && [[ "${rl:${#rl}-1}" = [/=:@] ]]; } && \
       [[ "${rl:${#rl}-1}" != ' ' && "${cmd_back:0:1}" != ' ' ]]
    then
        rl+=' '
    fi

    BU_RET="$rl"
    return 0
}

# Contract: __bu_autocomplete_quote_prefix splits a typed opening quote off the
# word so fzf can query/insert without it, and reports it for re-attachment.
function test_quote_prefix_contract { #@test
    __bu_autocomplete_quote_prefix "'so"
    assert_equal "${BU_RET[0]}" "'"
    assert_equal "${BU_RET[1]}" "so"

    __bu_autocomplete_quote_prefix '"so'
    assert_equal "${BU_RET[0]}" '"'
    assert_equal "${BU_RET[1]}" "so"

    __bu_autocomplete_quote_prefix "so"
    assert_equal "${BU_RET[0]}" ""
    assert_equal "${BU_RET[1]}" "so"

    __bu_autocomplete_quote_prefix ""
    assert_equal "${BU_RET[0]}" ""
    assert_equal "${BU_RET[1]}" ""
}

# Verify: completion part is clean (no trailing spaces, no metadata leaked)
function test_format_completion_parts_clean { #@test
    COMPREPLY=(images ps run build)
    BU_COMPREPLY_METADATA=("list images" "list containers" "run a command" "build an image")
    _fzf_format 60 false

    local line0="${COMPREPLY[0]}"
    local candidate="${line0%%$'\x01'*}"
    
    echo "candidate='$candidate'"
    assert_equal "$candidate" "images"
}

# Verify: delimiter stripping after selection works
function test_selection_strips_metadata { #@test
    COMPREPLY=(images ps run)
    BU_COMPREPLY_METADATA=("list images" "list containers" "run a command")
    _fzf_format 60 false

    local delimiter=$'\x01'
    local selected="${COMPREPLY[0]}"
    selected="${selected%%"${delimiter}"*}"
    
    echo "selected='$selected'"
    assert_equal "$selected" "images"
}

# Verify: no crash when completion text is longer than box_length
function test_format_long_completion_no_crash { #@test
    COMPREPLY=("a-very-long-option-name-that-exceeds-box-length" "short")
    BU_COMPREPLY_METADATA=("description for long option" "short desc")
    _fzf_format 20 false  # box_length is only 20

    local line0="${COMPREPLY[0]}"
    local candidate="${line0%%$'\x01'*}"
    
    echo "candidate='$candidate'"
    assert_equal "$candidate" "a-very-long-option-name-that-exceeds-box-length"
}

# ── Space-adding logic (the readline_line+=' ' gate) ──

function test_space_added_for_subcommand_nospace_false { #@test
    COMPREPLY=(images ps run)
    BU_COMPREPLY_METADATA=("List images" "List containers" "Run a command")
    _simulate_selection docker images false false
    # Should be "docker images " — exactly one trailing space
    assert_equal "$BU_RET" "docker images "
}

function test_space_added_for_subcommand_even_when_nospace_true { #@test
    # nospace should be ignored for plain subcommands (don't end with /=:@)
    COMPREPLY=(images ps run)
    BU_COMPREPLY_METADATA=("List images" "List containers" "Run a command")
    _simulate_selection docker images true false
    # nospace=true but the word ends with 's' not /=:@ → space still added
    assert_equal "$BU_RET" "docker images "
}

function test_nospace_respected_for_directory { #@test
    COMPREPLY=(dir/ file.txt)
    BU_COMPREPLY_METADATA=("a directory" "a file")
    _simulate_selection ls dir/ true true
    # dir/ ends with / and is_filenames=true → no space
    assert_equal "$BU_RET" "ls dir/"
}

function test_nospace_respected_for_option_equal { #@test
    COMPREPLY=("--format=" "--verbose")
    BU_COMPREPLY_METADATA=("Output format" "Verbose output")
    _simulate_selection cmd --format= true false
    # --format= ends with = and nospace=true → no space
    assert_equal "$BU_RET" "cmd --format="
}

# Contract: compopt -o nospace issued DURING a completion lands in the dynamic
# map and is honored unconditionally at insertion (even for a plain subcommand
# that would otherwise get a trailing space).
function test_dynamic_nospace_contract { #@test
    BU_COMPOPT_CURRENT_COMPLETION_OPTIONS=()
    BU_COMPOPT_DYNAMIC_COMPLETION_OPTIONS=()
    compopt -o nospace 2>/dev/null || true
    assert_equal "${BU_COMPOPT_DYNAMIC_COMPLETION_OPTIONS[nospace]}" "-o"
    assert_equal "${BU_COMPOPT_CURRENT_COMPLETION_OPTIONS[nospace]:-}" ""

    COMPREPLY=(images ps run)
    BU_COMPREPLY_METADATA=("List images" "List containers" "Run a command")
    _simulate_selection docker images false false true
    # dynamic nospace → no trailing space, even though 'images' has no suffix
    assert_equal "$BU_RET" "docker images"
}

function test_space_added_for_short_subcommand_ps { #@test
    # 'ps' is only 2 chars, lots of padding — verify clean result
    COMPREPLY=(ps images run)
    BU_COMPREPLY_METADATA=("List containers" "List images" "Run a command")
    _simulate_selection docker ps false false
    assert_equal "$BU_RET" "docker ps "
}

function test_no_double_space { #@test
    COMPREPLY=(images ps)
    BU_COMPREPLY_METADATA=("List images" "List containers")
    _simulate_selection docker images false false
    # Must be exactly one space, not two
    refute [[ "$BU_RET" == "docker images  " ]]
    assert_equal "$BU_RET" "docker images "
}

# ── Real docker fig spec data ──

function test_real_docker_fig_spec_one_space { #@test
    local spec_path="${BU_FIG_SPEC_DIR:-$DIR/../fig_specs/build}/docker.json"
    [[ -f "$spec_path" ]] || skip "docker fig spec not found"

    COMPREPLY=()
    BU_COMPREPLY_METADATA=()
    __bu_autocomplete_fig_completion_func docker ""

    # Select 'images' — real data with real padding
    _simulate_selection docker images false false
    echo "Result: [$BU_RET]"
    assert_equal "$BU_RET" "docker images "
}

function test_real_docker_fig_spec_short_command_one_space { #@test
    local spec_path="${BU_FIG_SPEC_DIR:-$DIR/../fig_specs/build}/docker.json"
    [[ -f "$spec_path" ]] || skip "docker fig spec not found"

    COMPREPLY=()
    BU_COMPREPLY_METADATA=()
    __bu_autocomplete_fig_completion_func docker ""

    # 'ps' is only 2 chars — lots of padding
    _simulate_selection docker ps false false
    echo "Result: [$BU_RET]"
    refute [[ "$BU_RET" == "docker ps  " ]]
    assert_equal "$BU_RET" "docker ps "
}

function test_real_docker_fig_spec_nospace_still_one_space { #@test
    local spec_path="${BU_FIG_SPEC_DIR:-$DIR/../fig_specs/build}/docker.json"
    [[ -f "$spec_path" ]] || skip "docker fig spec not found"

    COMPREPLY=()
    BU_COMPREPLY_METADATA=()
    __bu_autocomplete_fig_completion_func docker ""

    # nospace=true but subcommand → still one space
    _simulate_selection docker images true false
    echo "Result: [$BU_RET]"
    assert_equal "$BU_RET" "docker images "
}

# ── No-completer fallback keeps the cursor word ──

function test_fallback_no_bad_array_subscript { #@test
    # Regression: command_line was declared after the fallback case, so the
    # no-completer arm indexed an unset array and printed
    # "bad array subscript" on every TAB.
    complete -r true 2>/dev/null || true
    run bu_autocomplete_print_autocompletions true --he
    refute_output --partial "bad array subscript"
}

function test_fig_fallback_passes_cursor_word { #@test
    # Through the no-completer fallback the Fig lookup must receive the real
    # cursor word; an empty word would return the whole unfiltered option set.
    local spec_path="${BU_FIG_SPEC_DIR:-$DIR/../fig_specs/build}/degit.json"
    [[ -f "$spec_path" ]] || skip "degit fig spec not found"
    complete -r degit 2>/dev/null || true
    COMPREPLY=()
    # `|| true` keeps bats' errexit from aborting on the internal "no completer"
    # probe (which returns 1 by design); the function handles it internally.
    bu_autocomplete_get_autocompletions degit --c || true
    assert [ "${#COMPREPLY[@]}" -gt 0 ]
    local candidate
    for candidate in "${COMPREPLY[@]}"; do
        assert_regex "$candidate" '^--c'
    done
}

# ── Docker-style column-padded completions (__start_docker) ──

function test_extract_nested_parens_in_description { #@test
    # docker options have descriptions with nested parens like
    # --log-level  (Set the logging level ("debug", "info", "warn", "error", "fatal"))
    COMPREPLY=('--log-level       (Set the logging level ("debug", "info", "warn", "error", "fatal"))')
    BU_COMPREPLY_METADATA=()
    __bu_extract_inline_descriptions

    echo "COMPREPLY: [${COMPREPLY[0]}]"
    echo "META: [${BU_COMPREPLY_METADATA[0]}]"
    assert_equal "${COMPREPLY[0]}" "--log-level"
    assert_regex "${BU_COMPREPLY_METADATA[0]}" 'Set the logging level'
    assert_regex "${BU_COMPREPLY_METADATA[0]}" 'debug'
}

function test_rtrim_column_padded_entries { #@test
    # Docker's __start_docker pads subcommand names to fixed width
    COMPREPLY=("attach     " "build      " "images     " "ps         ")
    BU_COMPREPLY_METADATA=()
    __bu_extract_inline_descriptions

    echo "After rtrim:"
    printf '  [%q]\n' "${COMPREPLY[@]}"

    assert_equal "${COMPREPLY[0]}" "attach"
    assert_equal "${COMPREPLY[1]}" "build"
    assert_equal "${COMPREPLY[2]}" "images"
    assert_equal "${COMPREPLY[3]}" "ps"
}
