# bash-ide source=./bu_core_base.sh
# bash-ide source=../../bu_user_defined_decl.sh

# MARK: Custom compopt

# Requires 
# has_name: String
# completion_options: AssociativeArray 
# to be defined
# ```
# *Description*:
# Compute fzf dropdown positioning to fit within the terminal.
#
# *Params*:
# - `$1`: Terminal columns (COLUMNS)
# - `$2`: Anchor column — the column where the dropdown should start
#          (typically the column of the completing word's first character)
# - `$3`: Completing word length (characters of text being replaced)
# - `$4`: Base fzf text width (completions + padding, min ~60)
# - `$5`: Preview window width (0 if no preview, typically 40)
#
# *Sets*:
# - `${BU_RET[0]}`: left_margin (fzf --margin 0,right,0,left part)
# - `${BU_RET[1]}`: right_margin
# - `${BU_RET[2]}`: box_length (chars available inside borders for text)
# ```
__bu_fzf_compute_dimensions()
{
    local columns=$1
    local anchor_col=$2
    local word_len=$3
    local base_width=$4
    local preview_width=${5:-0}

    local borders_width=3
    (( preview_width > 0 )) && borders_width=5

    local left_pos=$anchor_col
    (( left_pos < 0 )) && left_pos=0

    local min_width=$((base_width + preview_width + word_len))
    local right_pos=$(( left_pos + min_width ))
    (( right_pos > columns )) && right_pos=$columns
    left_pos=$(( right_pos - min_width ))
    (( left_pos < 0 )) && left_pos=0
    right_pos=$(( left_pos + min_width ))
    (( right_pos > columns )) && right_pos=$columns

    local box_length=$((right_pos - left_pos - preview_width - borders_width))
    (( box_length < 20 )) && box_length=20

    local right_margin=$(( columns - right_pos ))
    (( right_margin < 0 )) && right_margin=0

    BU_RET=("$left_pos" "$right_margin" "$box_length")
}

__bu_autocomplete_collect_compopt()
{
    if [[ "$1" = compopt ]]
    then
        shift
    fi
    completion_options=()
    has_name=false
    while (($#))
    do
        case "$1" in
        -o|+o) completion_options[$2]=$1 ; shift 2 ;;
        -D|-E|-I) shift ;;
        *) has_name=true ; shift; break ;;
        esac
    done
}

bu_copy_associative_array()
{
    local -n __map1=$1
    local -n __map2=$2
    __map2=()
    local key
    for key in "${!__map1[@]}"
    do
        # shellcheck disable=SC2004
        __map2[$key]=${__map1[$key]}
    done
}

bu_insert_associative_array()
{
    local -n __map1=$1
    # shellcheck disable=SC2178
    local -n __map2=$2
    local key
    for key in "${!__map1[@]}"
    do
        # shellcheck disable=SC2004
        __map2[$key]=${__map1[$key]}
    done
}

bu_autocomplete_initialize_current_completion_options()
{
    local completion_command=$1
    local has_name
    local -A completion_options=()
    # shellcheck disable=SC2046
    __bu_autocomplete_collect_compopt $(compopt "$completion_command" 2>/dev/null)
    bu_copy_associative_array completion_options BU_COMPOPT_CURRENT_COMPLETION_OPTIONS
    BU_COMPOPT_DYNAMIC_COMPLETION_OPTIONS=()
    # bu_print_var BU_COMPOPT_CURRENT_COMPLETION_OPTIONS 
}

bu_autocomplete_def_compopt()
{
    BU_COMPOPT_IS_CUSTOM=true
    # shellcheck disable=SC2329
    compopt()
    {
        # shellcheck disable=SC2034
        local -A completion_options=()
        local has_name=false
        __bu_autocomplete_collect_compopt "$@"

        if ! "$has_name"
        then
            bu_insert_associative_array completion_options BU_COMPOPT_DYNAMIC_COMPLETION_OPTIONS
        fi

        builtin compopt "$@"
    }
}

bu_autocomplete_undef_compopt()
{
    unset -f compopt
    BU_COMPOPT_IS_CUSTOM=false
}

bu_autocomplete_def_compopt

# ```
# *Description*:
# Split a leading quote (single or double) off a word being completed, so the
# completion machinery can match and display candidates without the quote, then
# re-attach it at insertion time.  Candidates cannot carry the opening quote
# through `compgen -W`, and a leading `'` would otherwise be misread by fzf as
# an extended-search operator when seeding --query.
#
# *Params*:
# - `$1`: The word being completed (e.g. `'so`, `"so`, or `so`)
#
# *Returns*:
# - `${BU_RET[0]}`: The quote prefix (`'`, `"`, or empty)
# - `${BU_RET[1]}`: The dequoted remainder
# ```
__bu_autocomplete_quote_prefix()
{
    local word=$1
    local prefix=
    local rest=$word
    case "$word" in
    \'*) prefix="'"; rest=${word#\'} ;;
    \"*) prefix='"'; rest=${word#\"} ;;
    esac
    BU_RET=("$prefix" "$rest")
}

# MARK: Parsers
__BU_AUTOCOMPLETE_WORKING_DIRECTORY=.
__BU_AUTOCOMPLETE_OPTION_REGEX='([-\+[:alnum:]_/]+[[:space:]]*\|?[[:space:]]*)*[-\+[:alnum:]_/]+[[:space:]]*'

# ```
# *Description*:
# Append the content of a file to an existing array variable, splitting by lines
#
# *Params*:
# - `$1`: File to read
# - `$2` (optional): Name of the array variable to append to (default: `BU_RET`)
#
# *Returns*:
# - `${BU_RET[@]}` or the array variable named in `$2`: Content of the file appended to the array
#
# *Examples*:
# ```bash
# bu_cat_arr_append /path/to/file # ${BU_RET[@]} has the file content appended
# bu_cat_arr_append /path/to/file MY_ARR # ${MY_ARR[@]} has the file content appended
# ```
# ```
bu_cat_arr_append()
{
    local file=$1
    local ret=${2:-BU_RET}
    mapfile -t <"$file"
    # shellcheck disable=SC1083
    eval "$ret"+=\( \"\${MAPFILE[@]}\" \)
}

# ```
# *Description*:
# Parses out all the cases inside a case block. 
#
# *Params*
# - `$1`: Function name or script path to parse
# - `$2` (optional): Start indicator regex (default: `case .* in`)
# - `$3` (optional): End indicator regex (default: `esac`)
# - `$4` (optional): Start line number of the function/script (default: 1)
#
# *Returns*:
# - `stdout`: List of options inside the case block, separated by newlines and spaces
#
# *Examples*:
# ```bash
# bu_autocomplete_parse_case_block_options my_function
# bu_autocomplete_parse_case_block_options /path/to/script.sh
# ```
# ```
bu_autocomplete_parse_case_block_options()
{
    local function_or_script_path=$1
    local start_indicator=${2:-'case .* in'}
    local end_indicator=$3
    local start_lineno=${4:-1}

    start_indicator=/$start_indicator/
    if [[ -z "$end_indicator" ]]
    then
        end_indicator='! is_in_option && /^[[:space:]]*esac[[:space:]]*/'
    else
        end_indicator=/$end_indicator/
    fi

    if bu_symbol_is_function "$function_or_script_path"
    then
        declare -f "$function_or_script_path"
    else
        cat "$function_or_script_path"
    fi |\
    awk '
    BEGIN {
        is_start = 0
        is_in_option = 0
        case_count = 0
    }
    NR < '"$start_lineno"' { next }
    ! is_start && '"$start_indicator"' {
        is_start = 1
        is_in_option = 0
    }

    ! is_start { next }

    { line = $0 }

    ! is_in_option && ( \
        ( /^[[:space:]]*'"$__BU_AUTOCOMPLETE_OPTION_REGEX"'\)/ && gsub( /\).*/, "", line ) ) \
        || \
        ( /^[[:space:]]*'"$__BU_AUTOCOMPLETE_OPTION_REGEX"'\|\\/ && gsub( /\|\\/, "", line ) ) \
    ) {
        print line
    }

    { line = $0 }

    ! is_in_option && ( \
        ( /^[[:space:]]*'"$__BU_AUTOCOMPLETE_OPTION_REGEX"'\)/ && gsub( /\).*/, "", line ) ) \
    ) {
        is_in_option = 1
    }

    is_in_option && /[[:space:]]*case .* in[[:space:]]*/ {
        ++case_count;
    }

    is_in_option && /[[:space:]]*esac[[:space:]]*/ {
        --case_count;
    }

    is_in_option && !case_count && /.*;;[[:space:]]*$/ {
        is_in_option = 0
    }

    '"$end_indicator"' { exit }
    ' | tr '|' ' '
}

# ```
# *Description*:
# Cached version of `bu_autocomplete_parse_case_block_options`
#
# *Params*
# - `$1`: Function name or script path to parse
# - `$2` (optional): Start indicator regex (default: `case .* in`)
# - `$3` (optional): End indicator regex (default: `esac`)
# - `$4` (optional): Start line number of the function/script (default: 1)
# - `$5`: Cache key
# - `$6` (optional): Invalidate cache boolean (default: false)
#
# *Returns*:
# - `${BU_RET[@]}`: List of options inside the case block
#
# *Examples*:
# ```bash
# bu_autocomplete_parse_case_block_options_cached my_function '' '' '' my_cache_key false # ${BU_RET[@]} has the options
# bu_autocomplete_parse_case_block_options_cached /path/to/script.sh '' '' '' my_cache_key false # ${BU_RET[@]} has the options
# ```
# ```
bu_autocomplete_parse_case_block_options_cached()
{
    local function_or_script_path=$1
    local start_indicator=$2
    local end_indicator=$3
    local start_lineno=$4
    local cache_key=$5
    local is_invalidate_cache=$6
    bu_cached_keyed_execute \
        --invalidate-cache-bool "$is_invalidate_cache" \
        "$cache_key" \
        bu_stdout_to_ret --lines bu_autocomplete_parse_case_block_options "$function_or_script_path" "$start_indicator" "$end_indicator" "$start_lineno"
}

bu_autocomplete_parse_case_block_options_v2()
{
    local function_or_script_path=$1
    local start_indicator=${2:-'case .* in'}
    local end_indicator=$3
    local start_lineno=${4:-1}

    start_indicator=/$start_indicator/
    if [[ -z "$end_indicator" ]]
    then
        end_indicator='! is_in_option && /^[[:space:]]*esac[[:space:]]*/'
    else
        end_indicator=/$end_indicator/
    fi

    cat <<EOF
local -a bu_script_options=() bu_script_option_synopsis=() bu_script_option_docs=()
EOF

    # bu_log_debug "end_lineno[$end_lineno] start_row[$start_row]"

    if bu_symbol_is_function "$function_or_script_path"
    then
        declare -f "$function_or_script_path"
    else
        cat "$function_or_script_path"
    fi |\
    awk '
    # Escape prose for safe embedding in bash double-quoted assignments.
    # Deliberately NOT escaping $: ${VAR} and $(cmd) remain live so docs
    # can interpolate colors/paths and opt into dynamic content — unlike
    # backticks, $(...) has no innocent prose reading.
    function esc(s) {
        gsub(/\\/, "\\\\", s)
        gsub(/"/, "\\\"", s)
        gsub(/`/, "\\`", s)
        return s
    }
    NR < '"$start_lineno"' { next }
    '"$start_indicator"' {
        if (!is_start) {
            is_start = 1
            idx = -1
            outside = 0
            in_alternatives = 1
            pre_documentation = 2
            in_documentation = 3
            post_documentation = 4
            state = 0
            is_in_option = 0
            is_in_documentation = 0

            case_count = 0
            debug_print = 0
        }
    }
    
    ! is_start { next }

    {
        if (debug_print) {
            printf "# state=%s\n", state 
        } 
    }

    { line = $0 }

    state < pre_documentation && ( \
        ( /^[[:space:]]*'"$__BU_AUTOCOMPLETE_OPTION_REGEX"'\|\\/ && gsub( /\|\\/, "", line ) ) \
    ) {
        if (debug_print) {
            printf "# 1: %s\n", NR
        }
        gsub(/^[[:space:]]*/, "", line)
        if ( state == outside ) {
            idx = idx + 1
            state = in_alternatives
            printf "bu_script_options[%d]=\"%s\n", idx, esc(line)
        } else {
            printf "%s\n", esc(line)
        }
        next
    }

    state < pre_documentation && ( \
        ( /^[[:space:]]*'"$__BU_AUTOCOMPLETE_OPTION_REGEX"'\)/ && gsub( /\).*/, "", line) ) \
    ) {
        if (debug_print) {
            printf "# 2: %s\n", NR
        }
        gsub(/^[[:space:]]*/, "", line)

        if ( state == outside ) {
            idx = idx + 1
            printf "bu_script_options[%d]=\"%s\"\n", idx, esc(line)

            option_parameter_description = $0
            if (! sub(/.*\) *# */, "", option_parameter_description)) {
                option_parameter_description = ""
            }
            printf "bu_script_option_synopsis[%d]=\"%s\"\n", idx, esc(option_parameter_description)
        } else {
            printf "%s\"\n", esc(line)
        }
        printf "bu_script_option_docs[%d]=\"", idx, line
        state = pre_documentation
        next
    }

    { line = $0 }

    state == pre_documentation {
        if (debug_print) {
            printf "# 3: %s\n", NR
        }
        if ( $0 ~ /^[[:space:]]*# ?.*/ ) {
            state = in_documentation
        } else {
            # Close the docs string, then re-check this line against the two
            # option-arm patterns before dropping to post_documentation.
            # Single-line arms (e.g. `alpha) a=true;;`) put the next arm on
            # the line that terminates the previous arm doc scan; this
            # re-check exists so a cleanup does not silently swallow every
            # other single-line arm.
            printf "\"\n"

            if ( /^[[:space:]]*'"$__BU_AUTOCOMPLETE_OPTION_REGEX"'\|\\/ ) {
                if (debug_print) {
                    printf "# 8: %s\n", NR
                }
                # Multi-line alternatives group directly after a single-line
                # arm: open a new options row.
                gsub( /\|\\/, "", line )
                gsub(/^[[:space:]]*/, "", line)
                idx = idx + 1
                state = in_alternatives
                printf "bu_script_options[%d]=\"%s\n", idx, esc(line)
                next
            }

            if ( /^[[:space:]]*'"$__BU_AUTOCOMPLETE_OPTION_REGEX"'\)/ ) {
                if (debug_print) {
                    printf "# 9: %s\n", NR
                }
                # Next single-line arm: emit its option row exactly like the
                # primary arm-close matcher outside branch, and stay in
                # pre_documentation so a chain of consecutive single-line arms
                # is all caught.
                gsub( /\).*/, "", line )
                gsub(/^[[:space:]]*/, "", line)
                idx = idx + 1
                printf "bu_script_options[%d]=\"%s\"\n", idx, esc(line)

                option_parameter_description = $0
                if (! sub(/.*\) *# */, "", option_parameter_description)) {
                    option_parameter_description = ""
                }
                printf "bu_script_option_synopsis[%d]=\"%s\"\n", idx, esc(option_parameter_description)

                printf "bu_script_option_docs[%d]=\"", idx, line
                state = pre_documentation
                next
            }

            state = post_documentation
        }
    }

    state == in_documentation {
        if (debug_print) {
            printf "# 4: %s\n", NR
        }
        if ( $0 ~ /^[[:space:]]*# ?.*/ ) {
            sub( /^[[:space:]]*# ?/, "", line )
            print esc(line)
        } else {
            state = post_documentation
            printf "\"\n"
        }
    }

    state == post_documentation && /[[:space:]]*case .* in[[:space:]]*/ {
        ++case_count;
        if (debug_print) {
            printf "# 5: %s\n", NR
        }
    }

    state == post_documentation && /[[:space:]]*esac[[:space:]]*/ {
        --case_count;
        if (debug_print) {
            printf "# 6: %s\n", NR
        }
        next;
    }

    state == post_documentation && !case_count && /.*;;[[:space:]]*$/ {
        if (debug_print) {
            printf "# 7: %s\n", NR
        }
        state = outside
    }

    '"$end_indicator"' && !case_count { exit 0 }
    '
}


bu_autohelp_parse_case_block_help()
{
    bu_log_trace "parse_case start"
    local function_or_script_path=$1
    local start_indicator=${2:-'case .* in'}
    local end_indicator=$3
    local end_lineno=$4

    start_indicator=/$start_indicator/
    if [[ -z "$end_indicator" ]]
    then
        end_indicator='! is_in_option && /^[[:space:]]*esac[[:space:]]*/'
    else
        end_indicator=/$end_indicator/
    fi

    cat <<EOF
local -a bu_script_options=() bu_script_option_synopsis=() bu_script_option_docs=()
EOF

    local start_row=0
    if [[ -n "$end_lineno" ]]
    then
        bu_log_trace "parse_case before awk1 (find start_row)"
        start_row=$(
            if bu_symbol_is_function "$function_or_script_path"
            then
                declare -f "$function_or_script_path"
            else
                cat "$function_or_script_path"
            fi |\
            awk '
            BEGIN {
                start_row = 0
                case_count = 0
            }
            '"$start_indicator"' {
                ++case_count;
                # Ignore nested cases
                if (case_count == 1) {
                    start_row = NR
                }
            }
            '"$end_indicator"' {
                --case_count;
            }
            NR == '"$end_lineno"' {
                print start_row
                exit 0
            }
            '
        )
        bu_log_trace "parse_case after awk1"
    fi

    # bu_log_debug "end_lineno[$end_lineno] start_row[$start_row]"

    bu_log_trace "parse_case before awk2 (extract options)"
    if bu_symbol_is_function "$function_or_script_path"
    then
        declare -f "$function_or_script_path"
    else
        cat "$function_or_script_path"
    fi |\
    awk '
    # Escape prose for safe embedding in bash double-quoted assignments.
    # Deliberately NOT escaping $: ${VAR} and $(cmd) remain live so docs
    # can interpolate colors/paths and opt into dynamic content — unlike
    # backticks, $(...) has no innocent prose reading.
    function esc(s) {
        gsub(/\\/, "\\\\", s)
        gsub(/"/, "\\\"", s)
        gsub(/`/, "\\`", s)
        return s
    }
    NR < '"$start_row"' { next }
    '"$start_indicator"' {
        if (!is_start) {
            is_start = 1
            idx = -1
            outside = 0
            in_alternatives = 1
            pre_documentation = 2
            in_documentation = 3
            post_documentation = 4
            state = 0
            is_in_option = 0
            is_in_documentation = 0

            case_count = 0
            debug_print = 0
        }
    }
    
    ! is_start { next }

    {
        if (debug_print) {
            printf "# state=%s\n", state 
        } 
    }

    { line = $0 }

    state < pre_documentation && ( \
        ( /^[[:space:]]*'"$__BU_AUTOCOMPLETE_OPTION_REGEX"'\|\\/ && gsub( /\|\\/, "", line ) ) \
    ) {
        if (debug_print) {
            printf "# 1: %s\n", NR
        }
        gsub(/^[[:space:]]*/, "", line)
        if ( state == outside ) {
            idx = idx + 1
            state = in_alternatives
            printf "bu_script_options[%d]=\"%s\n", idx, esc(line)
        } else {
            printf "%s\n", esc(line)
        }
        next
    }


    # Documented positional catch-all: *)# SYNOPSIS (autohelp only, not v2)
    state < pre_documentation && /^[[:space:]]*\*\)#/ {
        if (debug_print) {
            printf "# pos: %s\n", NR
        }
        if ( state == outside ) {
            idx = idx + 1
            printf "bu_script_options[%d]=\"*\"\n", idx

            option_parameter_description = $0
            if (! sub(/.*\) *# */, "", option_parameter_description)) {
                option_parameter_description = ""
            }
            printf "bu_script_option_synopsis[%d]=\"%s\"\n", idx, esc(option_parameter_description)

            printf "bu_script_option_docs[%d]=\"", idx, line
            state = pre_documentation
        }
        next
    }
    state < pre_documentation && ( \
        ( /^[[:space:]]*'"$__BU_AUTOCOMPLETE_OPTION_REGEX"'\)/ && gsub( /\).*/, "", line) ) \
    ) {
        if (debug_print) {
            printf "# 2: %s\n", NR
        }
        gsub(/^[[:space:]]*/, "", line)

        if ( state == outside ) {
            idx = idx + 1
            printf "bu_script_options[%d]=\"%s\"\n", idx, esc(line)

            option_parameter_description = $0
            if (! sub(/.*\) *# */, "", option_parameter_description)) {
                option_parameter_description = ""
            }
            printf "bu_script_option_synopsis[%d]=\"%s\"\n", idx, esc(option_parameter_description)
        } else {
            printf "%s\"\n", esc(line)
        }
        printf "bu_script_option_docs[%d]=\"", idx, line
        state = pre_documentation
        next
    }

    { line = $0 }

    state == pre_documentation {
        if (debug_print) {
            printf "# 3: %s\n", NR
        }
        if ( $0 ~ /^[[:space:]]*# ?.*/ ) {
            state = in_documentation
        } else {
            # Close the docs string, then re-check this line against the two
            # option-arm patterns before dropping to post_documentation.
            # Single-line arms (e.g. `alpha) a=true;;`) put the next arm on
            # the line that terminates the previous arm doc scan; this
            # re-check exists so a cleanup does not silently swallow every
            # other single-line arm.
            printf "\"\n"

            if ( /^[[:space:]]*'"$__BU_AUTOCOMPLETE_OPTION_REGEX"'\|\\/ ) {
                if (debug_print) {
                    printf "# 8: %s\n", NR
                }
                # Multi-line alternatives group directly after a single-line
                # arm: open a new options row.
                gsub( /\|\\/, "", line )
                gsub(/^[[:space:]]*/, "", line)
                idx = idx + 1
                state = in_alternatives
                printf "bu_script_options[%d]=\"%s\n", idx, esc(line)
                next
            }

            if ( /^[[:space:]]*'"$__BU_AUTOCOMPLETE_OPTION_REGEX"'\)/ ) {
                if (debug_print) {
                    printf "# 9: %s\n", NR
                }
                # Next single-line arm: emit its option row exactly like the
                # primary arm-close matcher outside branch, and stay in
                # pre_documentation so a chain of consecutive single-line arms
                # is all caught.
                gsub( /\).*/, "", line )
                gsub(/^[[:space:]]*/, "", line)
                idx = idx + 1
                printf "bu_script_options[%d]=\"%s\"\n", idx, esc(line)

                option_parameter_description = $0
                if (! sub(/.*\) *# */, "", option_parameter_description)) {
                    option_parameter_description = ""
                }
                printf "bu_script_option_synopsis[%d]=\"%s\"\n", idx, esc(option_parameter_description)

                printf "bu_script_option_docs[%d]=\"", idx, line
                state = pre_documentation
                next
            }

            state = post_documentation
        }
    }

    state == in_documentation {
        if (debug_print) {
            printf "# 4: %s\n", NR
        }
        if ( $0 ~ /^[[:space:]]*# ?.*/ ) {
            sub( /^[[:space:]]*# ?/, "", line )
            print esc(line)
        } else {
            state = post_documentation
            printf "\"\n"
        }
    }

    state == post_documentation && /[[:space:]]*case .* in[[:space:]]*/ {
        ++case_count;
        if (debug_print) {
            printf "# 5: %s\n", NR
        }
    }

    state == post_documentation && /[[:space:]]*esac[[:space:]]*/ {
        --case_count;
        if (debug_print) {
            printf "# 6: %s\n", NR
        }
        next;
    }

    state == post_documentation && !case_count && /.*;;[[:space:]]*$/ {
        if (debug_print) {
            printf "# 7: %s\n", NR
        }
        state = outside
    }

    '"$end_indicator"' && !case_count { exit 0 }
    '
    bu_log_trace "parse_case after awk2"
}

bu_parse_multiselect()
{
    if [[ -n "$error_msg" ]]
    then
        return
    fi

    local -r num_args=$1
    local -r arg1=$2
    if shift 2 && bu_env_is_in_autocomplete && ((num_args > 1)) && [[ -n "$arg1" ]]
    then
        bu_parsed_multiselect_arguments[$arg1]=1
    fi

    if [[ "${__bu_g_is_inject:-}" == true ]]
    then
        autocompletion+=(--options-at "${BASH_SOURCE[1]}" "${BASH_LINENO[0]}" "$@")
    else
        autocompletion=(--options-at "${BASH_SOURCE[1]}" "${BASH_LINENO[0]}" "$@")
    fi
    shift_by=1
    : $((__bu_g_shift_by++))
}

bu_parse_positional()
{
    local -r num_args=$1
    shift
    if (( shift_by >= num_args ))
    then
        return
    fi

    : $((shift_by++)) $((__bu_g_shift_by++))
    if [[ "${__bu_g_is_inject:-}" == true ]]
    then
        autocompletion+=("$@")
    else
        autocompletion=("$@")
    fi
}

bu_validate_positional()
{
    if bu_env_is_in_autocomplete
    then
        return
    fi
    if (($# == 1))
    then
        local -r cur_word=$1
        local -r prev_word=
    else
        local -r cur_word=${!shift_by}
        if ((shift_by))
        then
            local -r prev_idx=$((shift_by - 1))
            local -r prev_word=${!prev_idx}
        else
            local -r prev_word=
        fi
    fi
    bu_scope_push
    local -r saved_dir=$PWD
    bu_scoped_set +e
    if bu_popd_silent 2>/dev/null
    then
        bu_scope_add_cleanup bu_pushd_silent "$saved_dir"
    fi
    local COMPREPLY=()
    __bu_autocomplete_completion_func_master_helper "${BASH_SOURCE[1]}" "$cur_word" "$prev_word" "${autocompletion[@]}"
    case ${#COMPREPLY[@]} in
    0)
        is_help=true
        error_msg="[$cur_word] did not match any of the options generated by ${BU_TPUT_UNDERLINE}${autocompletion[*]}${BU_TPUT_NO_UNDERLINE}"
        ;;
    1)
        ;;
    *)
        if [[ " ${COMPREPLY[*]} " != *" $cur_word "* ]]
        then
            is_help=true
            error_msg="[$cur_word] did not match any of the options generated by ${BU_TPUT_UNDERLINE}${autocompletion[*]}${BU_TPUT_NO_UNDERLINE}, possible alternatives: $(echo; printf "%q\n" ${COMPREPLY[*]})"
        fi
        ;;
    esac
    bu_scope_pop
}

bu_parse_command_context()
{
    BU_RET=()
    local -r start_marker=$1
    if (($# < 2))
    then
        return
    fi

    local -r end_marker=${start_marker:2}--
    autocompletion=(
        :"$end_marker"
        --as-if $BU_CLI_COMMAND_NAME "${start_marker:2}"
    )

    local i
    for (( i = 2; i <= $#; i++ ))
    do
        if [[ "${!i}" = "$end_marker" ]]
        then
            break
        fi
        BU_RET+=("${!i}")
    done
    if [[ "${!i}" = "$end_marker" ]]
    then
        autocompletion=()
    else
        autocompletion+=("${BU_RET[@]}" as-if--)
    fi

    : $(( shift_by += i - 1 )) $(( __bu_g_shift_by += i - 1 ))
}

bu_parse_nested()
{
    local -r nested_impl=$1
    shift
    if (( shift_by >= $# ))
    then
        return
    fi
    shift "$shift_by"
    local nested_args=("$@")
    local saved_shift_by=$shift_by
    shift_by=0
    local __bu_g_shift_by=0
    "$nested_impl" "${nested_args[@]}"
    shift_by=$saved_shift_by
    : $((shift_by += __bu_g_shift_by))
}

bu_parse_nested_multiselect()
{
    local -r nested_impl=$1
    shift
    if (( shift_by >= $# ))
    then
        return
    fi

    local -r last_word=${!shift_by}
    shift "$shift_by"
    local nested_args=("$@")
    autocompletion=(--options-of "$nested_impl")
    if bu_env_is_in_autocomplete
    then
        bu_parsed_multiselect_arguments[$last_word]=1
    fi

    local saved_shift_by=$shift_by
    shift_by=1
    "$nested_impl" "${nested_args[@]}"
    : $((shift_by += saved_shift_by))
}

# ```
# *Description*:
# Repeatable-subcommand parse, stay-in-multiselect variant.  Identical to
# `bu_parse_nested_multiselect` except it folds the nested shift counter back
# like `bu_parse_nested` (`shift_by = saved_shift_by + __bu_g_shift_by`),
# leaving `shift_by=1` so the outer loop stays at the multiselect position and
# re-enters the same case arm for the next option.  Already-used words are
# still recorded in `bu_parsed_multiselect_arguments` during autocomplete, so
# the remaining options are offered with used ones filtered out.
# ```
bu_parse_nested_multiselect_stay()
{
    local -r nested_impl=$1
    shift
    if (( shift_by >= $# ))
    then
        return
    fi

    local -r last_word=${!shift_by}
    shift "$shift_by"
    local nested_args=("$@")
    autocompletion=(--options-of "$nested_impl")
    if bu_env_is_in_autocomplete
    then
        bu_parsed_multiselect_arguments[$last_word]=1
    fi

    local saved_shift_by=$shift_by
    shift_by=1
    local __bu_g_shift_by=0
    "$nested_impl" "${nested_args[@]}"
    shift_by=$saved_shift_by
    : $((shift_by += __bu_g_shift_by))
}

# ```
# *Description*:
# Compose-mode parse: like `bu_parse_nested` but APPENDS `--options-of <impl>`
# to the accumulated `autocompletion` array instead of replacing it.  Sets an
# inject flag so that `bu_parse_multiselect` and `bu_parse_positional` called
# inside the impl also append rather than reset.  Returns the impl's exit
# status so callers can chain with `||`.
#
# Intended for catch-all arms that want to offer candidates from multiple
# resolver impls:
#
#     *)
#         bu_parse_inject resolver_a "$@" || bu_parse_inject resolver_b "$@"
#         ;;
#
# *Params*:
# - `$1`: Impl function name
# - `$@`: Remaining arguments (shifted by `shift_by - 1` before calling impl)
#
# *Returns*:
# - The impl's exit code (0 / 1 / 124).
# - `autocompletion`: Augmented with `--options-of <impl>` plus whatever the
#   impl's own parse calls contribute.
# ```
bu_parse_inject()
{
    local -r inject_impl=$1
    shift

    # Append the impl reference to the existing autocompletion array so
    # the master helper can parse the impl's case block for options.
    autocompletion+=(--options-of "$inject_impl")

    # Save and reset shift state (same pattern as bu_parse_nested).
    local saved_shift_by=$shift_by
    # Use shift_by - 1 so the impl sees the current arg as its first.
    (( saved_shift_by > 0 )) && shift "$((saved_shift_by - 1))"
    local inject_args=("$@")
    shift_by=0
    local __bu_g_shift_by=0

    # Set the inject flag so inner parse calls append.
    local __bu_g_is_inject=true

    "$inject_impl" "${inject_args[@]}"
    local inject_rc=$?

    # Restore the outer loop's shift state. This DIFFERS from
    # `bu_parse_nested` on purpose: nested shifts PAST the current token
    # (`shift "$shift_by"`), so the impl counts only the tokens after it and
    # `shift_by = saved_shift_by + __bu_g_shift_by` is correct. Inject
    # instead RE-PRESENTS the current token (`shift "$((saved_shift_by - 1))"`
    # above), so the impl's own `bu_parse_multiselect`/`bu_parse_positional`
    # calls re-count it in `__bu_g_shift_by`. Adding both counts would
    # double-count the token, which is exactly what the symmetric
    # `shift_by=$saved_shift_by; shift_by += __bu_g_shift_by` restoration
    # here would do — so do NOT "clean up" this asymmetry back to nested's
    # form.
    shift_by=$saved_shift_by
    if (( __bu_g_shift_by > 0 ))
    then
        # The impl consumed at least one token: the re-presented token is
        # already included in __bu_g_shift_by, so drop it from the outer
        # count (guarded for saved_shift_by == 0, where no token was
        # re-presented).
        : $((shift_by += __bu_g_shift_by))
        (( saved_shift_by > 0 )) && : $((shift_by -= 1))
    fi
    # Impl consumed nothing (rejected the token): leave shift_by at the
    # outer value so the outer loop still advances past the token after the
    # whole `||` chain rejects.

    return "$inject_rc"
}

# MARK: Parse errors
bu_parse_error_enum()
{
    local -r unrecognized_option=$1
    is_help=true
    error_msg="Unrecognized option[$unrecognized_option] for function[${FUNCNAME[1]}]"
}

bu_parse_error_argn()
{
    local -r option=$1
    local -r num_args_given=$2
    # shellcheck disable=SC2034
    is_help=true
    error_msg="Expected $shift_by arguments for function[${FUNCNAME[1]}], option[$option], got $num_args_given arguments"
}


# ```
# *Description*:
# Gets the completion function name for a given command
#
# *Params*:
# - `$1`: Command to get the completion function for
#
# *Returns*:
# - `$BU_RET`: 
#   - Name of the completion function if exit code = 0
#   - Empty if exit code = 1
#   - The completion spec if exit code = 2
# - Exit code:
#   - 0 if completion func is found
#   - 1 if no completion found
#   - 2 if non -F completion spec is found
# ```
bu_autocomplete_get_completion_func()
{
    local completion_for=$1
    bu_stdout_to_ret complete -p "$completion_for" 2>/dev/null
    if [[ -z "$BU_RET" ]]
    then
        # Trigger lazy loading (bash-completion v2) — only for dedicated completion files,
        # NOT _completion_loader which registers a generic fallback for everything
        { declare -F __load_completion &>/dev/null && __load_completion "$completion_for" </dev/null 2>/dev/null; } || true
        bu_stdout_to_ret complete -p "$completion_for" 2>/dev/null
    fi
    if [[ -z "$BU_RET" ]]
    then
        return 1
    fi
    case "$BU_RET" in
    *' -F '*)
        # Strip everything before (inclusive of) -F
        BU_RET=${BU_RET#* -F }
        # Strip all words after the completion function's name
        BU_RET=${BU_RET%% *}
        ;;
    *)
        BU_RET=${BU_RET% "$completion_for"}
        BU_RET=${BU_RET#complete }
        return 2
    esac
}

# ```
# *Description*:
# Populates the `${COMPREPLY[@]}` array with autocompletions for a given command line
#
# *Params*:
# - `...`: All parameters are treated as the command line to get autocompletions for
#
# *Returns*:
# - `${BU_RET_MAP[has_ansi_colors]}`: Whether the command is "ansi aware"
# - `${COMPREPLY[@]}`: List of autocompletions
# ```

# ```
# *Description*:
# Populate BU_COMPREPLY_METADATA with color-coded file hints:
#   directories  → (empty, already indicated by / suffix + color)
#   symlinks     → "{blue}→ target{reset}  {green}type{reset} ({yellow}size{reset})"
#   regular files → "{green}type{reset} ({yellow}size{reset})"
# Batches a single stat(1) + file(1) call.  Symlink target sizes
# are resolved via stat -L.
#
# *Params*:
# - `$@`: File paths (must be existing paths)
#
# *Returns (appends to)*:
# - `${BU_COMPREPLY_METADATA[@]}`
# ```
__bu_file_metadata_append()
{
    (($# == 0)) && return

    # Separate symlinks, directories, regular files
    local -a regs=() links=()
    local f
    for f; do
        if [[ -L "$f" ]]; then links+=("$f")
        else regs+=("$f")
        fi
    done

    # --- Batch stat for sizes ---
    local -A sz_map=()
    if ((${#regs[@]} > 0)); then
        local -a reg_sizes=()
        local line i=0
        while IFS= read -r line; do reg_sizes+=("$line"); done < <(stat -c '%s' -- "${regs[@]}" 2>/dev/null)
        while ((${#reg_sizes[@]} < ${#regs[@]})); do reg_sizes+=(0); done
        for f in "${regs[@]}"; do sz_map["$f"]=${reg_sizes[i]}; ((i++)); done
    fi
    if ((${#links[@]} > 0)); then
        local -a link_sizes=()
        local line i=0
        while IFS= read -r line; do link_sizes+=("$line"); done < <(stat -L -c '%s' -- "${links[@]}" 2>/dev/null)
        while ((${#link_sizes[@]} < ${#links[@]})); do link_sizes+=(0); done
        for f in "${links[@]}"; do sz_map["$f"]=${link_sizes[i]}; ((i++)); done
    fi

    # --- Batch file(1) for type tags (regular files, not symlinks) ---
    local -A type_map=()
    if ((${#regs[@]} > 0)); then
        local -a ftypes=()
        local line i=0
        while IFS= read -r line; do ftypes+=("$line"); done < <(file -b -- "${regs[@]}" 2>/dev/null)
        for f in "${regs[@]}"; do type_map["$f"]=${ftypes[i]}; ((i++)); done
    fi

    # --- Build colored metadata ---
    local g=$BU_TPUT_GREY  gn=$BU_TPUT_GREEN  yl=$BU_TPUT_VSCODE_YELLOW
    local bl=$BU_TPUT_BLUE  rs=$BU_TPUT_RESET
    local sz hint typ tgt short

    for f; do
        if [[ -d "$f" ]]; then
            BU_COMPREPLY_METADATA+=("")
            continue
        fi

        hint=""
        # Symlink target (blue)
        if [[ -L "$f" ]]; then
            tgt=$(readlink "$f" 2>/dev/null)
            hint+="${bl}→ ${tgt}${rs}  "
        fi

        # Type tag (green, from file -b)
        typ=${type_map["$f"]}
        if [[ -n "$typ" ]]; then
            short=$(__bu_file_type_short "$typ")
            [[ -n "$short" ]] && hint+="${gn}${short}${rs} "
        fi

        # Size (yellow inside grey parens)
        sz=${sz_map["$f"]:-0}
        hint+="${g}(${yl}$(__bu_human_size "$sz")${g})${rs}"

        BU_COMPREPLY_METADATA+=("$hint")
    done
}

# ```
# *Description*:
# Map file(1) description to a compact type tag (≤ 4 chars).
#
# *Params*:
# - `$1`: Raw file -b output (e.g. "ASCII text", "ELF 64-bit ... executable")
#
# *Returns*:
# - stdout: short type tag, or empty for uninteresting types
# ```
__bu_file_type_short()
{
    local desc=$1
    # Chop off comma/colon‑delimited detail
    desc=${desc%%,*}
    desc=${desc%%:*}
    # Strip leading/trailing whitespace
    desc=${desc## }
    desc=${desc%% }

    case "$desc" in
        *"ASCII text"*)                     echo "text" ;;
        *"Unicode text"*|*"UTF-8"*"text"*)  echo "text" ;;
        *"CSV text"*)                        echo "csv"  ;;
        *"JSON"*"data"*)                     echo "json" ;;
        *"YAML"*)                            echo "yaml" ;;
        *"XML"*"document"*|*"XML"*"text"*)   echo "xml"  ;;
        *"HTML"*"document"*|*"HTML"*"text"*) echo "html" ;;
        *"shell script"*|*"Bourne-Again"*)   echo "sh"   ;;
        *"Python"*"script"*)                 echo "py"   ;;
        *"Perl"*"script"*)                   echo "pl"   ;;
        *"Ruby"*"script"*)                   echo "rb"   ;;
        *"Node.js"*"script"*)                echo "js"   ;;
        *"ELF"*"executable"*|*"ELF"*"pie executable"*) echo "exe" ;;
        *"ELF"*"shared object"*)             echo "lib"  ;;
        *"ELF"*)                             echo "elf"  ;;
        *"tar archive"*)                      echo "tar"  ;;
        *"gzip compressed"*)                  echo "gz"   ;;
        *"bzip2 compressed"*)                 echo "bz2"  ;;
        *"Zip archive"*)                      echo "zip"  ;;
        *"7-zip archive"*)                    echo "7z"   ;;
        *"archive"*|*"ar archive"*)          echo "ar"   ;;
        *"PNG image"*)                        echo "png"  ;;
        *"JPEG image"*)                       echo "jpg"  ;;
        *"GIF image"*)                        echo "gif"  ;;
        *"SVG"*)                              echo "svg"  ;;
        *"PDF document"*)                     echo "pdf"  ;;
        *"directory"*)                        echo ""     ;;
        *"symbolic link"*)                    echo ""     ;;
        *"empty"*)                            echo "0B"   ;;
        *"very short file"*)                  echo "tiny" ;;
        *"C source"*)                         echo "c"    ;;
        *"C++ source"*)                       echo "c++"  ;;
        *"makefile"*|*"Makefile"*)            echo "mk"   ;;
        *"data"*)                             echo "bin"  ;;
        *)                                    echo ""     ;;
    esac
}

__bu_human_size()
{
    # Convert bytes to human-readable: 0B, 12K, 4.2M, 1.3G
    local b=$1 s u
    if ((b < 0)); then b=0; fi
    if ((b < 1024)); then
        printf '%sB' "$b"
    elif ((b < 1048576)); then
        awk -v n="$b" 'BEGIN { printf "%.1fK", n / 1024 }'
    elif ((b < 1073741824)); then
        awk -v n="$b" 'BEGIN { printf "%.1fM", n / 1048576 }'
    else
        awk -v n="$b" 'BEGIN { printf "%.1fG", n / 1073741824 }'
    fi
}

# ```
# *Description*:
# Clean up COMPREPLY entries from external completion functions.
# Handles two patterns:
#   1. "word (description)" — extracts description to BU_COMPREPLY_METADATA
#   2. Column-padded entries — rtrims trailing whitespace from every entry.
#
# Pattern 2 is needed because some completion functions (notably docker's
# __docker_format_comp_descriptions) pad names to the longest entry's width
# with trailing spaces so that bash's built-in compgen -W display renders
# aligned columns.  Those spaces are display-only and must be stripped
# before the completion text reaches the command line.
#
# *Globals*:
# - COMPREPLY: modified in-place
# - BU_COMPREPLY_METADATA: appended with extracted descriptions (grey)
# ```
__bu_extract_inline_descriptions()
{
    local _i _entry _word _desc
    local _grey="${BU_TPUT_GREY:-[90m}"
    for ((_i = 0; _i < ${#COMPREPLY[@]}; _i++))
    do
        _entry=${COMPREPLY[_i]}
        if [[ "$_entry" == *'  ('* ]]
        then
            _word="${_entry%%  (*}"
            _desc="${_entry#*  (}"
            _desc="${_desc%)}"
            COMPREPLY[_i]="${_word%"${_word##*[! ]}"}"
            BU_COMPREPLY_METADATA[_i]="$_grey${_desc}${BU_TPUT_RESET:-[0m}"
        else
            COMPREPLY[_i]="${_entry%"${_entry##*[! ]}"}"
        fi
    done
}


bu_autocomplete_get_autocompletions()
{
    local BU_AUTOCOMPLETE_ACCEPT_ANSI_COLORS=false
    case "$1" in
    --accept-ansi-colors)
        BU_AUTOCOMPLETE_ACCEPT_ANSI_COLORS=true
        shift
        ;;
    esac

    if (($# <= 1))
    then
        bu_compgen -A command "$1"
        # Technically we should have a separate field, e.g accept metadata
        if "$BU_AUTOCOMPLETE_ACCEPT_ANSI_COLORS" && ((${#COMPREPLY[@]} < 1000))
        then
            mapfile -t BU_COMPREPLY_METADATA < <(type -t "${COMPREPLY[@]}")
            BU_COMPREPLY_METADATA=("${BU_COMPREPLY_METADATA[@]/#/${BU_TPUT_GREY}}")
            BU_COMPREPLY_METADATA=("${BU_COMPREPLY_METADATA[@]/%/${BU_TPUT_RESET}}")
        fi
        return
    fi

    local has_ansi_colors=false

    bu_autocomplete_get_completion_func "$1"
    case "$?" in
    0);;
    1)
        # Try Fig spec first, then fall back to default completion
        if __bu_autocomplete_fig_completion_func "$1" "${command_line[-1]}" ""
        then
            # Fig handled it — skip the completion-func call below
            has_ansi_colors=false
            BU_RET_MAP=([has_ansi_colors]=$has_ansi_colors)
            return 0
        fi
        __bu_autocomplete_completion_func_default "$1"
        if ! bu_autocomplete_get_completion_func "$1"
        then
            bu_log_err "Failed to get completion func for $1"
            return 1
        fi
        ;;
    2)
        # shellcheck disable=SC2086
        bu_compgen $BU_RET -- "${command_line[-1]}"
        return 0
        ;;
    esac

    local completion_func=$BU_RET
    
    local command_line=("$@")
    local COMP_LINE=${command_line[*]}
    local COMP_POINT=${#COMP_LINE}
    local COMP_CWORD=$(( $# - 1 ))
    local COMP_WORDS=( "${command_line[@]}" )
    local COMP_WORDBREAKS=$' \t\n"\'><=;|&(:'
    local completion_command=${command_line[0]}
    local cur_word=${command_line[-1]}
    local prev_word=
    (( $# >= 2 )) && prev_word=${command_line[-2]}
    COMPREPLY=()
    BU_COMPREPLY_METADATA=()
    local tries
    bu_log_debug \
        "completion_func[$completion_func]" "completion_command[$completion_command]" "cur_word[$cur_word]" "prev_word[$prev_word]" \
        "COMP_POINT[$COMP_POINT] COMP_CWORD[$COMP_CWORD]"
    BU_RET_MAP=()
    "$completion_func" "$completion_command" "$cur_word" "$prev_word" &>/dev/null
    local ret=$?
    has_ansi_colors=${BU_RET_MAP[has_ansi_colors]:-false}
    for (( tries = 3; ret == 124 && tries > 0; tries-- ))
    do
        if ! bu_autocomplete_get_completion_func "$1"
        then
            bu_log_err "Failed to get completion func for $1"
            return 1
        fi
        completion_func=$BU_RET

        "$completion_func" "$completion_command" "$cur_word" "$prev_word" &>/dev/null
        ret=$?
        has_ansi_colors=${BU_RET_MAP[has_ansi_colors]:-false}
    done
    BU_RET_MAP=([has_ansi_colors]=$has_ansi_colors)

    if ((${#COMPREPLY[@]} == 0))
    then
        # Taken from the _variables function from /usr/share/bash-completion/bash_completion
        # Extended to handle prefixes (e.g. inside double quotes: "$HO or "2020-11-$HO)
        if [[ "$cur_word" =~ ^([^$]*)(\$(\{[!#]?)?)([A-Za-z0-9_]*)$ ]]
        then
            local _prefix="${BASH_REMATCH[1]}"
            local _dollar="${BASH_REMATCH[2]}"
            local _brace="${BASH_REMATCH[3]}"
            local _name="${BASH_REMATCH[4]}"
            if [[ -n "$_brace" ]]
            then
                local arrs vars
                vars=( $(compgen -A variable -P "${_prefix}${_dollar}" -S '}' -- "$_name") )
                arrs=( $(compgen -A arrayvar -P "${_prefix}${_dollar}" -S '[' -- "$_name") )
                if ((${#vars[@]} == 1 && ${#arrs[@]} != 0))
                then
                    compopt -o nospace &>/dev/null
                    COMPREPLY+=("${arrs[@]}")
                else
                    COMPREPLY+=("${vars[@]}")
                fi
            else
                COMPREPLY+=( $(compgen -A variable -P "${_prefix}\$" -- "$_name") )
            fi
        else
            if [[ "$cur_word" =~ ^(\$\{[#!]?)([A-Za-z0-9_]*)\[([^]]*)$ ]]
            then
                local IFS=$'\n'
                COMPREPLY+=($(compgen -W '$(printf %s\\n "${!'${BASH_REMATCH[2]}'[@]}")' -P "${BASH_REMATCH[1]}${BASH_REMATCH[2]}[" -S ']}' -- "${BASH_REMATCH[3]}"))
                if [[ ${BASH_REMATCH[3]} == [@*] ]]; then
                    COMPREPLY+=("${BASH_REMATCH[1]}${BASH_REMATCH[2]}[${BASH_REMATCH[3]}]}")
                fi
                # No __ltrim_colon_completions here for simplicity
            else
                if [[ $cur =~ ^\$\{[#!]?[A-Za-z0-9_]*\[.*\]$ ]]
                then
                    COMPREPLY+=("$cur}")
                    # No __ltrim_colon_completions here for simplicity
                    return 0
                fi
            fi
        fi
    fi

    # Extract inline descriptions from external command completions.
    # Some completion functions embed descriptions as "word (description)".
    # Move the description to BU_COMPREPLY_METADATA so it isn't inserted.
    __bu_extract_inline_descriptions

    # File metadata: if completions are existing files/dirs, add hints
    if ((${#COMPREPLY[@]} > 0)) && [[ -e "${COMPREPLY[0]}" && -e "${COMPREPLY[-1]}" ]]; then
        if ((${#COMPREPLY[@]} < 2000)); then
            # Add trailing slashes to directories
            local _fm_i
            for (( _fm_i = 0; _fm_i < ${#COMPREPLY[@]}; _fm_i++ )); do
                if [[ -d "${COMPREPLY[_fm_i]}" && "${COMPREPLY[_fm_i]: -1}" != / ]]; then
                    COMPREPLY[_fm_i]+=/
                fi
            done
            if (( ${#BU_COMPREPLY_METADATA[@]} == 0 )); then
                __bu_file_metadata_append "${COMPREPLY[@]}"
            fi
        fi
    fi

    return "$ret"
}

# ```
# *Description*:
# Adds autocompletions to the current `${COMPREPLY[@]}` array
#
# *Params*:
# - All parameters are passed to `bu_autocomplete_get_autocompletions`
#
# *Returns*:
# - `${COMPREPLY[@]}`: Original contents plus new autocompletions
# ```
bu_autocomplete_add_autocompletions()
{
    local saved_compreply=("${COMPREPLY[@]}")
    bu_autocomplete_get_autocompletions "$@"
    COMPREPLY+=("${saved_compreply[@]}")
}

# ```
# *Description*:
# Prints autocompletions to stdout
#
# *Params*:
# - All parameters are passed to `bu_autocomplete_get_autocompletions`
#
# *Returns*:
# - `stdout`: List of autocompletions, one per line
# ```
bu_autocomplete_print_autocompletions()
{
    bu_autocomplete_get_autocompletions "$@"
    printf "%s\n" "${COMPREPLY[@]}"
}

# ```
# *Description*:
# Wrapper around `compgen` that captures output into `${COMPREPLY[@]}`
#
# *Params*:
# - `...`: All parameters are passed to `compgen`
#
# *Returns*:
# - `${COMPREPLY[@]}`: Output of `compgen`
# ```
bu_compgen()
{
    # Some modern versions of bash support a target variable, but we don't assume this
    bu_stdout_to_ret --lines -o COMPREPLY compgen "$@"
}



__bu_autocomplete_compreply_append_find_files()
{
    local base=$1
    local type=$2
    shift 2
    local find_patterns=("$@")
    local pattern
    local candidates=()
    local absolute_base
    if [[ "${base:0:1}" != / ]]
    then
        absolute_base=$(realpath --canonicalize-missing "$__BU_AUTOCOMPLETE_WORKING_DIRECTORY"/"$base"/)
    else
        absolute_base=$base
    fi

    if [[ ! -d "$absolute_base" ]]
    then
        return 0
    fi

    case "$type" in
    directory)
        for pattern in "${find_patterns[@]}"
        do
            candidates+=($(find -L "$absolute_base/" -path "$absolute_base/$pattern/[[:alnum:]_-]*" -prune -o -type d -path "$absolute_base/$pattern" -printf '%P' 2>/dev/null))
        done
        ;;
    file)
        for pattern in "${find_patterns[@]}"
        do
            candidates+=($(find -L "$absolute_base" -type f -path "*/$pattern" -printf '%P' 2>/dev/null))
        done
        ;;
    esac

    COMPREPLY+=("${candidates[@]}")
}

# MARK: Completion

# ```
# Autocomplete worked successfully
# ```
BU_AUTOCOMPLETE_EXIT_CODE_SUCCESS=0
# ```
# Autocomplete failed
# ```
BU_AUTOCOMPLETE_EXIT_CODE_FAIL=1
# ```
# Autocomplete should be retried without moving on to the next word
# ```
BU_AUTOCOMPLETE_EXIT_CODE_RETRY=124

# ```
# *Returns*
# - `${COMPREPLY[@]}`: An array of completions that doesn't necessarily match on cur_word prefix.
# ```

# ```
# *Description*:
# Map raw option synopsis to a compact, color-coded tag.
#   _FLAG         → {green}flag{reset}
#   *_FILTER      → {blue}shortname{reset}  (enum positional)
#   anything else → {yellow}shortname{reset}  (free string positional)
# ```
__bu_synopsis_color()
{
    local raw=$1
    local short tag_color

    case "$raw" in
        _FLAG)
            short=flag
            tag_color=$BU_TPUT_GREEN
            ;;
        *_FILTER)
            short=${raw%_FILTER}
            short=${short,,}
            tag_color=$BU_TPUT_BLUE
            ;;
        *)
            short=${raw,,}
            short=${short#script_}
            short=${short#command_}
            tag_color=$BU_TPUT_VSCODE_YELLOW
            ;;
    esac

    printf '%s%s%s' "$tag_color" "$short" "$BU_TPUT_RESET"
}

# ```
# *Description*:
# Normalize an option token for alias comparison: strip leading `-`/`+`
# characters and lowercase the remainder.
# `--select`, `select` and `SELECT` all normalize to `select`.
#
# *Params*:
# - `$1`: Name of the output variable (nameref)
# - `$2`: Option token to normalize
#
# *Returns*:
# - `$$1`: Normalized token
# ```
__bu_autocomplete_normalize_option()
{
    local -n __bu_autocomplete_normalize_option_out=$1
    local __bu_autocomplete_normalize_option_t=$2
    while [[ "$__bu_autocomplete_normalize_option_t" == [-+]* ]]
    do
        __bu_autocomplete_normalize_option_t=${__bu_autocomplete_normalize_option_t:1}
    done
    __bu_autocomplete_normalize_option_out=${__bu_autocomplete_normalize_option_t,,}
}

__bu_autocomplete_completion_func_master_helper()
{
    local completion_command_path=$1
    local cur_word=$2
    local prev_word=$3
    shift 3
    local args=("$@")
    local i=0
    local offset
    local shift_by
    local terminator
    local should_restore_cwd=false
    local original_cwd=$PWD
    local script_path
    local script_lineno
    local option
    local -a sub_args
    local -a stdout
    local -a opt_cur_word=("$cur_word")
    local has_ansi_colors=false
    local -r accept_ansi_colors=${BU_AUTOCOMPLETE_ACCEPT_ANSI_COLORS:-false}
    local current_ansi_color=
    local reset_ansi_color=
    local BU_RET
    local exit_code=$BU_AUTOCOMPLETE_EXIT_CODE_SUCCESS
    while ((i<${#args[@]}))
    do
        shift_by=1
        case "${args[i]}" in
        :*)
            # Explicit literal, syntax inspired by Ruby symbols
            COMPREPLY+=("${current_ansi_color}${args[i]:1}${reset_ansi_color}")
            ;;
        --hint)
            bu_autocomplete_hint=${args[i+1]}
            shift_by=2
            ;;
        -a|--ansi)
            if "$accept_ansi_colors"
            then
                has_ansi_colors=true
                current_ansi_color=${args[i+1]}
                reset_ansi_color=$BU_TPUT_RESET
            fi
            shift_by=2
            ;;
        +a|--no-ansi)
            current_ansi_color=
            reset_ansi_color=
            ;;
        -c|--append-cur-word)
            opt_cur_word=("$cur_word")
            ;;
        +c|--no-append-cur-word)
            opt_cur_word=()
            ;;
        --options-of|--options-at)
            script_path=${args[i+1]}
            case "${args[i]}" in
            --options-of) 
                script_lineno= 
                shift_by=2
                ;;
            --options-at) 
                script_lineno=${args[i+2]}
                shift_by=3
                ;;
            esac
            # bu_print_var bu_parsed_multiselect_arguments >/dev/tty
            local -a bu_script_options bu_script_option_synopsis bu_script_option_docs
            eval "$(bu_autocomplete_parse_case_block_options_v2 "$script_path" "" "" "$script_lineno")"

            for ((_opt_row=0; _opt_row<${#bu_script_options[@]}; _opt_row++))
            do
                # Translate newlines (from multi-line `opt1|\ … optN)` groups)
                # to pipes, then split. Also handle `declare -f` pretty-print
                # (a | b | c) by trimming whitespace and dropping empties.
                local _entry=${bu_script_options[_opt_row]//$'\n'/|}
                bu_str_split '|' "$_entry"
                local -a line_options=()
                local _opt
                for _opt in "${BU_RET[@]}"; do
                    while [[ "$_opt" == ' '* || "$_opt" == *' ' ]]; do
                        _opt=${_opt# }
                        _opt=${_opt% }
                    done
                    [[ -n "$_opt" ]] && line_options+=("$_opt")
                done
                # Update BU_RET so the non-alias code path below also
                # gets the cleaned tokens (avoids spaces breaking
                # compgen -W splitting at the end of the helper).
                BU_RET=("${line_options[@]}")

                # Alias heuristic: alternatives equal modulo leading -/+ and
                # case (--select, select, SELECT) are the same option. Show a
                # single row, and exclude it once any form has been used.
                # Options that merely share a handler but differ after
                # normalization (--json, --yaml) are NOT merged.
                local is_alias_group=false
                if ((${#line_options[@]} > 1))
                then
                    local norm_base normalized_option
                    __bu_autocomplete_normalize_option norm_base "${line_options[0]}"
                    is_alias_group=true
                    for option in "${line_options[@]:1}"
                    do
                        __bu_autocomplete_normalize_option normalized_option "$option"
                        if [[ "$normalized_option" != "$norm_base" ]]
                        then
                            is_alias_group=false
                            break
                        fi
                    done
                fi

                if "$is_alias_group"
                then
                    local is_alias_used=false
                    for option in "${line_options[@]}"
                    do
                        if [[ "${bu_parsed_multiselect_arguments[$option]}" = 1 ]]
                        then
                            is_alias_used=true
                            break
                        fi
                    done
                    "$is_alias_used" && continue

                    # Prefer the first form, unless the user has typed the
                    # prefix of another form (keeps the row alive through the
                    # compgen prefix filter downstream)
                    local display_option=${line_options[0]}
                    for option in "${line_options[@]:1}"
                    do
                        if [[ -n "$cur_word" && "$option" == "$cur_word"* && "$display_option" != "$cur_word"* ]]
                        then
                            display_option=$option
                            break
                        fi
                    done

                    COMPREPLY+=("${current_ansi_color}${display_option}${reset_ansi_color}")
                    local _syn=${bu_script_option_synopsis[_opt_row]}
                    local _desc=${bu_script_option_docs[_opt_row]}
                    _desc=${_desc%"${_desc##*[![:space:]]}"} # rtrim: extracted docs carry a trailing newline
                    _desc=${_desc//$'\n'/"\n"}
                    _desc=${_desc//$'\t'/}
                    # Short type tag, color-coded: flag=green, enum=blue, str=yellow
                    local _tag=$(__bu_synopsis_color "$_syn")
                    local _aka="aka ${line_options[*]:1}"
                    [[ -n "$_desc" ]] && _aka+=" — "
                    BU_COMPREPLY_METADATA+=("${_tag} ${BU_TPUT_GREY}${_aka}${_desc}${BU_TPUT_RESET}")
                    continue
                fi

                # Some heuristics:
                # If ${BU_RET[@]} is of length 2, and one of them is short-form, and the other is long-form
                # e.g. -d --dir
                # then having either the long-form or the short-form will suffice in ruling out the other.
                if ((${#BU_RET[@]} == 2)) &&
                    [[
                        (
                            (${BU_RET[0]} == [-+][^-]* && ${BU_RET[1]} == --*) ||
                            (${BU_RET[1]} == [-+][^-]* && ${BU_RET[0]} == --*)
                        ) && 
                        (
                            "${bu_parsed_multiselect_arguments[${BU_RET[0]}]}" = 1 ||
                            "${bu_parsed_multiselect_arguments[${BU_RET[1]}]}" = 1
                        )
                    ]]
                then
                    continue
                fi
                # Otherwise, we don't assume that options on the same line mean the same thing
                # In this case, we will only leave out the exact options that have been parsed
                # TODO: Handle the case where an option is allowed to be given more than once.
                for option in "${BU_RET[@]}"; do
                    # TODO: Filtering here
                    case "${bu_parsed_multiselect_arguments[$option]}" in
                    '') 
                        COMPREPLY+=("${current_ansi_color}${option}${reset_ansi_color}")
                        local _syn=${bu_script_option_synopsis[_opt_row]}
                        local _desc=${bu_script_option_docs[_opt_row]}
                        _desc=${_desc%"${_desc##*[![:space:]]}"} # rtrim: extracted docs carry a trailing newline
                        _desc=${_desc//$'\n'/"\n"}
                        _desc=${_desc//$'\t'/}
                        # Short type tag, color-coded: flag=green, enum=blue, str=yellow
                        local _tag=$(__bu_synopsis_color "$_syn")
                        BU_COMPREPLY_METADATA+=("${_tag} ${BU_TPUT_GREY}${_desc}${BU_TPUT_RESET}")
                        ;;
                    1) continue ;;
                    esac
                done
            done
            ;;
        --cwd)
            should_restore_cwd=true
            cd "${args[i+1]}"
            shift_by=2
            ;;
        --sh|--enum|--stdout|--ret|--as-if|--pipeline-fields|--delimited)
            # Generic completion utilities
            terminator=${args[i]#--}--
            for (( offset = 1; i + offset < "${#args[@]}"; offset++ ))
            do
                if [[ "${args[i + offset]}" = "$terminator" ]]
                then
                    break
                fi
            done
            sub_args=("${args[@]:i+1:offset-1}")
            case "${args[i]}" in
            --enum)
                if [[ -n "$current_ansi_color" ]]
                then
                    # TODO: Filtering here
                    sub_args=("${sub_args[@]/#/$current_ansi_color}")
                    sub_args=("${sub_args[@]/%/$reset_ansi_color}")
                fi
                COMPREPLY+=("${sub_args[@]}")
                ;;
            --stdout)
                # shellcheck disable=SC2207
                if [[ -n "$current_ansi_color" ]]
                then
                    # TODO: Filtering here
                    stdout=($("${sub_args[@]}" "${opt_cur_word[@]}"))
                    stdout=("${stdout[@]/#/$current_ansi_color}")
                    stdout=("${stdout[@]/%/$reset_ansi_color}")
                    COMPREPLY+=("${stdout[@]}")
                else
                    COMPREPLY+=($("${sub_args[@]}" "${opt_cur_word[@]}"))
                fi
                ;;
            --ret)
                if "${sub_args[@]}" "${opt_cur_word[@]}"
                then
                    if [[ -n "$current_ansi_color" ]]
                    then
                        # TODO: Filtering here
                        BU_RET=("${BU_RET[@]/#/$current_ansi_color}")
                        BU_RET=("${BU_RET[@]/%/$reset_ansi_color}")
                    fi
                    COMPREPLY+=("${BU_RET[@]}")
                fi
                ;;
            --as-if)
                bu_autocomplete_add_autocompletions "${sub_args[@]}" "${opt_cur_word[@]}"
                ;;
            --pipeline-fields)
                # Shorthand for --ret __bu_out_complete_pipeline_fields [--dot] [--nested] ret--
                # Resolves record fields from the upstream pipeline producer.
                # Optional --dot prefix for jq-style completions (.name, .verb, ...).
                # Optional --nested for tree-aware completion (server.host, server.port).
                # When fields are found, dynamically updates bu_autocomplete_hint to
                # show the available field names. Place --hint BEFORE --pipeline-fields
                # in the DSL array so the dynamic hint can override the static one.
                local _pf_is_dot=false
                local _pf_is_nested=false
                local _pf_arg
                for _pf_arg in "${sub_args[@]}"
                do
                    case "$_pf_arg" in
                    --dot)    _pf_is_dot=true ;;
                    --nested) _pf_is_nested=true ;;
                    esac
                done
                local -a _pf_call_args=()
                "$_pf_is_dot" && _pf_call_args+=(--dot)
                "$_pf_is_nested" && _pf_call_args+=(--nested)
                if __bu_out_complete_pipeline_fields "${_pf_call_args[@]}" "${opt_cur_word[@]}"
                then
                    if [[ -n "$current_ansi_color" ]]
                    then
                        BU_RET=("${BU_RET[@]/#/$current_ansi_color}")
                        BU_RET=("${BU_RET[@]/%/$reset_ansi_color}")
                    fi
                    COMPREPLY+=("${BU_RET[@]}")
                    # Dynamic hint: show the actual available field names
                    # (overrides any static --hint set earlier in the DSL array)
                    local _pf_hint_prefix="field"
                    "$_pf_is_dot" && _pf_hint_prefix="jq expression"
                    local _pf_field_list="${BU_RET[*]}"
                    bu_autocomplete_hint="$_pf_hint_prefix: ${_pf_field_list// /, }"
                fi
                ;;
            --delimited)
                # Comma-delimited multiselect: completing "name,ve" suggests
                # "name,version" excluding already-selected fields.  Syntax:
                #   --delimited [--delimiter X] opt1 opt2 ... delimited--
                # Options before the sentinel are the allowed tokens; an
                # optional --delimiter overrides the default comma.
                local _dl_delim=,
                local -a _dl_options=()
                local _dl_pending_delim=
                local _dl_arg
                for _dl_arg in "${sub_args[@]}"
                do
                    if [[ -n "$_dl_pending_delim" ]]
                    then
                        _dl_delim=$_dl_arg
                        _dl_pending_delim=
                    elif [[ "$_dl_arg" == --delimiter ]]
                    then
                        _dl_pending_delim=1
                    else
                        _dl_options+=("$_dl_arg")
                    fi
                done
                ((${#_dl_options[@]})) || break

                # Comma-splitting logic: extract prefix and already-used tokens
                local _dl_prefix=
                local -A _dl_used=()
                local _dl_last_seg=${opt_cur_word[0]}
                if [[ "$_dl_last_seg" == *"$_dl_delim"* ]]
                then
                    _dl_prefix=${_dl_last_seg%"$_dl_delim"*}$_dl_delim
                    _dl_last_seg=${_dl_last_seg##*$_dl_delim}
                    local _dl_used_token
                    local _dl_ifs=$IFS
                    IFS=$_dl_delim
                    for _dl_used_token in ${opt_cur_word[0]%"$_dl_delim"*}
                    do
                        [[ -n "$_dl_used_token" ]] && _dl_used[$_dl_used_token]=1
                    done
                    IFS=$_dl_ifs
                fi

                local _dl_opt
                for _dl_opt in "${_dl_options[@]}"
                do
                    [[ -n "${_dl_used[$_dl_opt]:-}" ]] && continue
                    [[ "$_dl_opt" == "$_dl_last_seg"* ]] || continue
                    local _dl_candidate=${_dl_prefix}${_dl_opt}
                    [[ -n "$current_ansi_color" ]] && \
                        _dl_candidate=${current_ansi_color}${_dl_candidate}${reset_ansi_color}
                    COMPREPLY+=("$_dl_candidate")
                done

                # Auto-hint: show available options (overrides static --hint)
                local _dl_hint_list="${_dl_options[*]}"
                bu_autocomplete_hint="${_dl_delim}-separated: ${_dl_hint_list// /, }"
                ;;
            --sh)
                # Exec any arbitrary command
                # Useful for pushd and popd
                "${sub_args[@]}"
                ;;
            esac
            shift_by=$(( 1 + offset ))
            ;;
        *)
            bu_user_defined_autocomplete_lazy "${args[@]:i}"
            case $? in
            "$BU_AUTOCOMPLETE_EXIT_CODE_SUCCESS")
                shift_by=$BU_RET
                ;;
            "$BU_AUTOCOMPLETE_EXIT_CODE_RETRY")
                shift_by=$BU_RET
                exit_code=$BU_AUTOCOMPLETE_EXIT_CODE_RETRY
                ;;
            "$BU_AUTOCOMPLETE_EXIT_CODE_FAIL")
                # If all else fails, treat the arg like a literal
                COMPREPLY+=("${current_ansi_color}${args[i]}${reset_ansi_color}")
                ;;
            esac
            ;;
        esac
        : $(( i += shift_by ))
    done

    if [[ -e "${COMPREPLY[0]}" && -e "${COMPREPLY[-1]}" ]]
    then
        # If we are changing directories, then most likely the list of files are directory dependent,
        # We can also check the value of compopt if there is `-o filenames`
        # like in the fzf completion function but I'm too lazy to add that right now.
        if (( ${#COMPREPLY[@]} < 2000 ))
        then
            for (( i = 0; i < ${#COMPREPLY[@]}; i++ ))
            do
                if [[ -d "${COMPREPLY[i]}" && "${COMPREPLY[i]:${#COMPREPLY[i]}-1}" != / ]]
                then
                    COMPREPLY[i]+=/
                fi
            done
            local dirs_or_files=()
            local non_files=()
            if "$accept_ansi_colors"
            then
                has_ansi_colors=true
                for (( i = 0; i < ${#COMPREPLY[@]}; i++ ))
                do
                    if [[ -e "${COMPREPLY[i]}" ]]
                    then
                        dirs_or_files+=("${COMPREPLY[i]}")
                    else
                        non_files+=("${COMPREPLY[i]}")
                    fi
                done
                # Populate file metadata before ls reorders entries (only if no
                # other metadata was already set by the completion function)
                if (( ${#BU_COMPREPLY_METADATA[@]} == 0 )); then
                    __bu_file_metadata_append "${dirs_or_files[@]}"
                fi
                mapfile -t COMPREPLY < <(ls -d --color -- "${dirs_or_files[@]}")
                COMPREPLY+=("${non_files[@]}")
            else
                if (( ${#BU_COMPREPLY_METADATA[@]} == 0 )); then
                    __bu_file_metadata_append "${COMPREPLY[@]}"
                fi
            fi
        fi
    fi
    # Note that if ansi colors are enabled, we must do the filtering up top individually (if we want to, but this can be a TODO)!
    if ! "$has_ansi_colors"
    then
        
        if ((${#BU_COMPREPLY_METADATA[@]}>0))
        then
            for ((i=0; i < ${#COMPREPLY[@]}; i++))
            do
                COMPREPLY[i]="${COMPREPLY[i]}"%"$i"
            done
            # bu_compgen -W "${COMPREPLY[*]}" -- "$cur_word"
            mapfile -t COMPREPLY < <(compgen -W "${COMPREPLY[*]}" -- "$cur_word")
            local idx
            local filtered_bu_compreply_metadata=()
            for ((i=0; i < ${#COMPREPLY[@]}; i++))
            do
                idx=${COMPREPLY[i]#*\%}
                COMPREPLY[i]=${COMPREPLY[i]%\%*}
                filtered_bu_compreply_metadata+=("${BU_COMPREPLY_METADATA[idx]}")
            done
            BU_COMPREPLY_METADATA=("${filtered_bu_compreply_metadata[@]}")
        else
            bu_compgen -W "${COMPREPLY[*]}" -- "$cur_word"
        fi
    fi
    cd "$original_cwd"
    BU_RET_MAP=([has_ansi_colors]=$has_ansi_colors)
    return "$exit_code"
}

# ```
# *Description*:
# Implementation of the master command completion function for sourcing scripts.
# Does not use any of the global COMP_ variables, instead takes all necessary parameters to be more self-contained.
#
# *Params*
# - `$1`: Completion command path
# - `$2`: Current word being completed
# - `$3`: Previous word
# - `$4`: Current word index
# - `$5`: Tail being completed
# - `...`: All words in the command line
#
# *Returns*
# - `${COMPREPLY[@]}`: List of autocompletions
# ```
__bu_autocomplete_completion_func_master_impl()
{
    local completion_command_path=$1
    local cur_word=$2
    local prev_word=$3
    local comp_cword=$4
    local tail=$5
    shift 5
    # bu_log_tty
    # bu_log_tty "__bu_autocomplete_completion_func_master_impl path[$completion_command_path] cur[$cur_word] prev[$prev_word] cword[$comp_cword] tail[$tail] $(printf "'%s' " "$@")"
    # bu_log_tty
    local comp_words=("$@")
    comp_words[comp_cword]=${comp_words[comp_cword]%$tail}
    local processed_comp_words=(
        "$completion_command_path"
        "${comp_words[@]:1:comp_cword}"
    )
    COMPREPLY=()
    
    local bu_autocomplete_hint=
    local lazy_autocomplete_args=()
    local -A -g bu_parsed_multiselect_arguments=()
    # bu_log_tty reached0
    local exit_code
    # bu_log_tty
    # bu_log_tty "__bu_autocomplete_completion_func_master_impl cword[$comp_cword] $(printf "'%s' " "${comp_words[@]}")"
    # bu_log_tty
    case "${comp_words[comp_cword]}" in
    '>'|'>>'|'<')
        prev_word="${comp_words[comp_cword]}"
        cur_word=
        ;;
    esac
    case "$prev_word" in
    '>'|'>>'|'<')
        bu_autocomplete_initialize_current_completion_options bu
        compopt -o filenames
        compopt -o nospace
        bu_compgen -f -- "$cur_word"
        exit_code=0
        ;;
    *)
        if builtin source "${processed_comp_words[@]}" &>/dev/null
        then
            lazy_autocomplete_args=("${BU_RET[@]}")
        fi
        # bu_log_tty reached3
        # Scripts might set -e, and because we are sourcing them, we unset it
        set +ex
        # bu_log_tty lazy_autocomplete_args="${lazy_autocomplete_args[*]}"
        
        bu_autocomplete_initialize_current_completion_options bu
        __bu_autocomplete_completion_func_master_helper "$completion_command_path" "$cur_word" "$prev_word" "${lazy_autocomplete_args[@]}"
        exit_code=$?
        ;;
    esac

    local is_nospace=false
    local is_filenames=false
    if ((${#command_line[@]} > 1))
    then
        if [[ "${BU_COMPOPT_CURRENT_COMPLETION_OPTIONS[nospace]}" = -o || "${BU_COMPOPT_DYNAMIC_COMPLETION_OPTIONS[nospace]}" = -o ]]
        then
            is_nospace=true
        fi
        if [[ "${BU_COMPOPT_CURRENT_COMPLETION_OPTIONS[filenames]}" = -o || "${BU_COMPOPT_DYNAMIC_COMPLETION_OPTIONS[filenames]}" = -o ]]
        then
            is_filenames=true
        fi
    fi

    # bu_log_tty "COMPREPLY=${COMPREPLY[*]}"
    if [[ -n "$bu_autocomplete_hint" ]]
    then
        compopt -o nosort # Bash 4.4+
        # May be unset in the plain bash completion path (the variable is
        # only set, as a local, by the fzf binding entry point), so default
        # it: a bare "$VAR" here executes an empty command name.
        if ! "${BU_AUTOCOMPLETE_ACCEPT_ANSI_COLORS:-false}"
        then
            if ((!${#COMPREPLY[@]}))
            then
                # regular bash completion
                # https://stackoverflow.com/questions/70538848/simulate-bashs-compreply-response-without-actually-completing-it
                # Add an invisible element
                COMPREPLY=("Hint: $bu_autocomplete_hint" $'\xC2\xA0')
            fi
        else
            # fzf autocomplete case
            BU_COMPREPLY_HINT=$bu_autocomplete_hint
        fi
    fi
    if ((exit_code == BU_AUTOCOMPLETE_EXIT_CODE_RETRY))
    then
        compopt -o nospace
    elif ((${#COMPREPLY} == 1)) && [[ -n "${tail:0:1}" ]] && ! "$is_nospace"
    then
        # When there is (1) only 1 completion suggestion, (2) the cursor is right before a non-space char, (3) No `compopt -o nospace` has been invoked

        # Force add a space because compopt +o nospace doesn't create a space in this case
        COMPREPLY[0]+=' '
    fi
}

__bu_autocomplete_completion_func_cli_resolve_alias()
{
    # shellcheck disable=SC2206
    # Note: NOT readonly — bash 4.4 aborts on re-declaring a readonly
    # array local in a recursive call (alias-of-alias chain)
    local bu_alias_spec=($1)
    shift
    local -r bu_aliased_command=${bu_alias_spec[0]}
    local -r function_or_script_path=${BU_COMMANDS[$bu_aliased_command]}
    if [[ -z "$function_or_script_path" ]]
    then
        return 1
    fi

    local resolved_options=()

    # bu_log_tty "cmdline: $(printf "'%s' " "$@")"

    local arg
    for arg in "${bu_alias_spec[@]:1}"
    do
        case "$arg" in
        '{?}')
            if ((!$#))
            then
                break
            fi
            ;;
        '{}')
            if ((!$#))
            then
                break
            fi
            resolved_options+=("$1")
            shift
            ;;
        '{...}')
            resolved_options+=("$@")
            shift $#
            ;;
        *)
            resolved_options+=("$arg")
            ;;
        esac
        if ((!$#))
        then
            break
        fi
    done

    __bu_cli_command_type "$bu_aliased_command"
    local -r type=$BU_RET
    BU_RET=()
    case "$type" in
    alias)
        __bu_autocomplete_completion_func_cli_resolve_alias "$function_or_script_path" "${resolved_options[@]}"
        ;;
    execute|source|function)
        BU_RET=("$function_or_script_path" "${resolved_options[@]}")
        ;;
    *)
        return 1
        ;;
    esac
}

# ```
# *Description*:
# Completion function for the master command `bu`
#
# *Params*:
# - `$1`: Completion command (should be `bu`)
# - `$2`: Current word being completed
# - `$3`: Previous word
#
# *Returns*:
# - `${COMPREPLY[@]}`: List of autocompletions
# ```
__bu_autocomplete_completion_func_cli()
{
    # Complete deferred command scan on first completion.
    bu_ensure_command_scan

    local -r completion_command=$1
    local -r cur_word=$2
    local -r prev_word=$3

    # Accept the primary CLI name or any registered alias
    if [[ "$completion_command" != "$BU_CLI_COMMAND_NAME" ]]
    then
        local _accepted=false
        local _alias
        for _alias in "${BU_CLI_COMMAND_ALIASES[@]}"; do
            if [[ "$completion_command" == "$_alias" ]]
            then
                _accepted=true
                break
            fi
        done
        "$_accepted" || return 1
    fi
    
    COMPREPLY=()
    if ((COMP_CWORD == 1))
    then
        local _completion_kind=command
        if [[ "$cur_word" == :* ]]
        then
            # Namespace-qualified command syntax: :<ns>:<verb-noun>
            # :<TAB>           → suggest namespaces
            # :ns:<TAB>        → suggest commands in namespace `ns`
            # :ns:get-<TAB>   → suggest commands in namespace `ns` starting with `get-`
            local ns_part=${cur_word#:}
            if [[ "$ns_part" == *:* ]]
            then
                # Namespace specified: complete commands within it
                _completion_kind=scoped-command
                local ns_name=${ns_part%%:*}
                local ns_prefix=":$ns_name:"
                local cmd_prefix=${ns_part#$ns_name:}
                local -a ns_commands=()
                local -A _ns_seen=()
                local cmd
                for cmd in "${!BU_COMMANDS[@]}"
                do
                    if [[ "${BU_COMMAND_PROPERTIES[$cmd,namespace]}" == "$ns_name" ]]
                    then
                        _ns_seen[$cmd]=1
                        ns_commands+=("$cmd")
                    fi
                done
                # Shadowed (collision-parked) commands from the qualified store.
                local _qkey _qbare
                for _qkey in "${!BU_COMMANDS_QUALIFIED[@]}"
                do
                    if [[ "$_qkey" == ":$ns_name:"* ]]
                    then
                        _qbare=${_qkey#*:}
                        _qbare=${_qbare#*:}
                        if [[ -z "${_ns_seen[$_qbare]:-}" ]]
                        then
                            _ns_seen[$_qbare]=1
                            ns_commands+=("$_qbare")
                        fi
                    fi
                done
                if ((${#ns_commands[@]} > 0))
                then
                    local ns_word=":$ns_name:$cmd_prefix"
                    bu_compgen -W "${ns_commands[*]}" -- "$cmd_prefix"
                    local i
                    for (( i = 0; i < ${#COMPREPLY[@]}; i++ ))
                    do
                        COMPREPLY[i]=":$ns_name:${COMPREPLY[i]}"
                    done
                fi
            else
                # No namespace yet: complete namespace names
                _completion_kind=namespace-list
                local -a namespaces=()
                local -A _ns_list_seen=()
                local ns
                for ns in "${!BU_COMMAND_NAMESPACES[@]}"
                do
                    [[ -z "$ns" ]] && continue  # skip default/empty namespace
                    _ns_list_seen[$ns]=1
                    namespaces+=(":$ns:")
                done
                # Namespaces that exist only in the qualified store (every
                # command of that module lost its bare name).
                local _qkey _qns
                for _qkey in "${!BU_COMMANDS_QUALIFIED[@]}"
                do
                    _qns=${_qkey#:}
                    _qns=${_qns%%:*}
                    [[ -z "$_qns" ]] && continue
                    [[ -n "${_ns_list_seen[$_qns]:-}" ]] && continue
                    _ns_list_seen[$_qns]=1
                    namespaces+=(":$_qns:")
                done
                bu_compgen -W "${namespaces[*]}" -- "$cur_word"
                # Accepting a bare :ns: must NOT add a trailing space — the
                # user continues typing the command part.
                compopt -o nospace
            fi
        else
            # Command position after a pipe: only suggest commands whose
            # input format/fields are compatible with the upstream stream.
            local -a _pipe_candidates=("${!BU_COMMANDS[@]}")
            __bu_out_filter_compatible_commands _pipe_candidates
            bu_compgen -W "${_pipe_candidates[*]}" -- "$cur_word"
        fi
        if "${BU_AUTOCOMPLETE_ACCEPT_ANSI_COLORS:-false}"
        then
            local i
            local color
            # Only surface module provenance when more than one module is
            # registered — a single-module project renders byte-identically
            # to the pre-provenance dropdown.
            local _show_module_tag=false
            if ((${#BU_MODULE_REGISTRY[@]} > 1))
            then
                _show_module_tag=true
            fi
            for (( i = 0; i < ${#COMPREPLY[@]}; i++ ))
            do
                # Namespace rows are not registry keys — purpose-built
                # metadata (live command count), never a type probe.
                if [[ "$_completion_kind" == namespace-list ]]
                then
                    local _ns_name=${COMPREPLY[i]#:}
                    _ns_name=${_ns_name%:}
                    local _ns_count=0
                    local _c
                    for _c in "${!BU_COMMANDS[@]}"
                    do
                        [[ "${BU_COMMAND_PROPERTIES[$_c,namespace]:-}" == "$_ns_name" ]] && : $((_ns_count++))
                    done
                    # Count shadowed commands from the qualified store too.
                    local _qk
                    for _qk in "${!BU_COMMANDS_QUALIFIED[@]}"
                    do
                        [[ "$_qk" == ":$_ns_name:"* ]] && : $((_ns_count++))
                    done
                    local _ns_label=commands
                    if (( _ns_count == 1 ))
                    then
                        _ns_label=command
                    fi
                    BU_COMPREPLY_METADATA[i]="${BU_TPUT_VSCODE_DARK_GREEN}namespace${BU_TPUT_RESET} (${_ns_count} ${_ns_label})"
                    COMPREPLY[i]=${BU_TPUT_VSCODE_PINK}${COMPREPLY[i]}${BU_TPUT_RESET}
                    continue
                fi

                # Scoped rows are ":ns:cmd" — strip the qualifier before any
                # registry lookup (the display string is not a registry key).
                local _lookup=${COMPREPLY[i]}
                if [[ "$_completion_kind" == scoped-command ]]
                then
                    _lookup=${_lookup#*:}
                    _lookup=${_lookup#*:}
                fi

                __bu_cli_command_type "$_lookup"
                BU_COMPREPLY_METADATA[i]="${BU_TPUT_GREY}$BU_RET${BU_TPUT_RESET}"
                if "$_show_module_tag"
                then
                    local _mod=${BU_COMMAND_PROPERTIES[$_lookup,module]:-}
                    local _mod_display=bu
                    if [[ -n "$_mod" ]]
                    then
                        _mod_display=${BU_MODULE_DISPLAY_NAMES[$_mod]:-$_mod}
                    fi
                    BU_COMPREPLY_METADATA[i]+=" ${BU_TPUT_VSCODE_BLUE}[${_mod_display}]${BU_TPUT_RESET}"
                fi
                case "$BU_RET" in
                alias)
                    color=$BU_TPUT_VSCODE_DARK_BLUE
                    ;;
                function)
                    color=$BU_TPUT_VSCODE_YELLOW
                    ;;
                source)
                    color=$BU_TPUT_VSCODE_ORANGE
                    ;;
                execute)
                    color=$BU_TPUT_VSCODE_GREEN
                    ;;
                esac
                COMPREPLY[i]=${color}${COMPREPLY[i]}${BU_TPUT_RESET}
            done
            BU_RET_MAP=([has_ansi_colors]=true)
        fi
        return 0
    fi

    local arg1=${COMP_WORDS[1]}
    local function_or_script_path=${BU_COMMANDS[$arg1]}
    if [[ -z "$function_or_script_path" ]]
    then
        return 1
    fi

    if [[ "${BU_COMMAND_PROPERTIES[$arg1,type]}" = 'alias' ]]
    then
        if ! __bu_autocomplete_completion_func_cli_resolve_alias "$function_or_script_path" "${COMP_WORDS[@]:2:COMP_CWORD-1}"
        then
            # bu_log_tty alias comp words failed
            return 1
        fi
        local -r comp_cword=$((${#BU_RET[@]} - 1))
        # Note: NOT readonly — bash 4.4 aborts on re-declaring a readonly
        # array local on subsequent completion invocations
        local comp_words=("${BU_RET[@]}")
        # bu_log_tty alias comp words: "${comp_words[@]}"
        __bu_autocomplete_completion_func_master_impl "${comp_words[0]}" "${comp_words[comp_cword]}" "${comp_words[comp_cword-1]}" "$comp_cword" "" "${comp_words[@]}"

        # Alias --help discoverability: at the alias's FIRST argument a sole
        # --help/-h is intercepted by the dispatcher (prints the expansion and
        # the root command's help).  Offer both here, additively, alongside
        # the delegated slot-value completions — aliases otherwise have no
        # case block, so --help is otherwise absent from the dropdown.
        if (( COMP_CWORD == 2 ))
        then
            local -a _alias_help_entries=()
            local _ah_entry
            for _ah_entry in --help -h
            do
                [[ -z "$cur_word" || "$_ah_entry" == "$cur_word"* ]] && _alias_help_entries+=("$_ah_entry")
            done

            if ((${#_alias_help_entries[@]} > 0))
            then
                # Strip the "Hint: …" + NBSP pseudo-entries the master impl
                # emits when the delegated completion produced nothing — we
                # are about to supply real completions.
                if ((${#COMPREPLY[@]} == 2)) && [[ "${COMPREPLY[0]}" == "Hint: "* ]]
                then
                    COMPREPLY=()
                    BU_COMPREPLY_METADATA=()
                fi

                # Align metadata with COMPREPLY: delegated entries may have
                # produced completions without a parallel metadata row.
                while ((${#BU_COMPREPLY_METADATA[@]} < ${#COMPREPLY[@]}))
                do
                    BU_COMPREPLY_METADATA+=("")
                done

                # Resolve the root command's display name from its script path
                # (comp_words[0] is the terminal command's path, e.g. for an
                # alias chain the help is rendered by the last hop's command).
                local _alias_root_cmd=
                local _ah_cmd
                for _ah_cmd in "${!BU_COMMANDS[@]}"
                do
                    if [[ "${BU_COMMANDS[$_ah_cmd]}" == "${comp_words[0]}" ]]
                    then
                        _alias_root_cmd=$_ah_cmd
                        break
                    fi
                done
                [[ -n "$_alias_root_cmd" ]] || _alias_root_cmd=${function_or_script_path%% *}

                local _ah_existing _ah_dup
                for _ah_entry in "${_alias_help_entries[@]}"
                do
                    # Skip when the delegated completion already offers this
                    # token (e.g. a slotless alias delegating to an option list).
                    _ah_dup=false
                    for _ah_existing in "${COMPREPLY[@]}"
                    do
                        [[ "$_ah_existing" == "$_ah_entry" ]] && _ah_dup=true && break
                    done
                    "$_ah_dup" && continue

                    COMPREPLY+=("$_ah_entry")
                    BU_COMPREPLY_METADATA+=("${BU_TPUT_GREEN}flag${BU_TPUT_RESET} ${BU_TPUT_GREY}show alias expansion and ${_alias_root_cmd} help${BU_TPUT_RESET}")
                done
            fi
        fi
    else
        local -r comp_cword=$((COMP_CWORD - 1))
        # Note: NOT readonly — bash 4.4 aborts on re-declaring a readonly
        # array local on subsequent completion invocations
        local comp_words=(
            "$function_or_script_path"
            "${COMP_WORDS[@]:2}"
        )
        local tail
        if [[ "${COMP_LINE:COMP_POINT-1:1}" = ' ' ]]
        then
            tail=${COMP_WORDS[COMP_CWORD]}
        else
            tail=${COMP_LINE:COMP_POINT}
            tail=${tail%% *}
        fi
        __bu_autocomplete_completion_func_master_impl "$function_or_script_path" "$cur_word" "$prev_word" "$comp_cword" "$tail" "${comp_words[@]}"
    fi
}

__bu_autocomplete_completion_func_script()
{
    local completion_command=$1
    local cur_word=$2
    local prev_word=$3
    __bu_autocomplete_completion_func_master_impl "$completion_command" "$cur_word" "$prev_word" "$COMP_CWORD" "" "${COMP_WORDS[@]}"
}

# ```
# *Description*:
# Completion function that retrieves autocompletions from a cached file
#
# *Params*:
# - `$1`: Completion command
# - `$2`: Current word being completed
# - `$3`: Previous word
#
# *Returns*:
# - `${COMPREPLY[@]}`: List of autocompletions
# ```
__bu_autocomplete_completion_func_cached()
{
    local completion_command=$1
    local cur_word=$2
    local prev_word=$3

    bu_user_defined_convert_command_to_key "$completion_command"
    local key=$BU_RET

    bu_cat_str "$BU_NAMED_CACHE_DIR/$key"
    bu_compgen -W "$BU_RET" -- "$cur_word"
}

# ```
# *Description*:
# Completion function for the default case when no specific completion function is found.
#
# *Params*:
# - `$1`: Completion command
# - `$2`: Current word being completed (unused)
# - `$3`: Previous word (unused)
#
# *Returns*:
# - Exit code:
#   - 0: Autocomplete worked successfully
#   - 124: Autocomplete should be retried
#   - 1 or any other code: Autocomplete failed
# - `${COMPREPLY[@]}`: List of autocompletions
# ```
__bu_autocomplete_completion_func_default()
{
    local completion_command=$1
    # local cur_word=$2 # unused
    # local prev_word=$3 # unused

    bu_user_defined_convert_command_to_key "$completion_command"
    local key=$BU_RET
    if [[ -e "$BU_NAMED_CACHE_DIR"/"$key" ]]
    then
        complete -F __bu_autocomplete_completion_func_cached -- "$completion_command"
        return 124
    fi

    # Consult bash's default compspec (complete -D) before falling back
    # to _completion_loader / _minimal.  A user or embedding project that
    # installs a custom -D handler expects it to be honoured for every
    # command with no specific compspec, including inside BashTab's fzf
    # completion path.
    local default_spec
    if default_spec=$(complete -p -D 2>/dev/null)
    then
        # Parse the -F <func> from:  complete -F my_func -D
        local default_func=
        if [[ "$default_spec" =~ [[:space:]]-F[[:space:]]+([^[:space:]]+) ]]
        then
            default_func=${BASH_REMATCH[1]}
            # Register the default handler for this command so the
            # retry loop re-resolves and invokes it.
            complete -F "$default_func" -- "$completion_command"
            return 124
        fi
    fi

    if bu_symbol_is_function _completion_loader
    then
        complete -F _completion_loader -- "$completion_command"
    elif bu_symbol_is_function _minimal
    then
        complete -F _minimal -- "$completion_command"
    else
        return 1
    fi

    return 124
}

# ```
# *Description*:
# Completion func for the `source` builtin/function.
# ```
__bu_autocomplete_completion_func_source()
{
    local completion_command=$1
    local cur_word=$2
    local prev_word=$3
    case "$completion_command" in
    source|.) ;;
    *) bu_log_err "Unexpected command[$completion_command]"; return 1;;
    esac

    if ((COMP_CWORD == 1))
    then
        local paths=()
        bu_str_split : "$PATH"
        local dir
        for dir in "${BU_RET[@]}"
        do
            if [[ -d "$dir" ]]
            then
                paths+=("$dir")
            fi
        done
        local -a path_shell_scripts
        mapfile -t path_shell_scripts < <(
            find "${paths[@]}" \
                -mindepth 1 -maxdepth 1 \
                -type f \( -not -executable \) \
                \( -name '*.sh' -or -name 'activate' -or -name '.bashrc' \) \
                -printf "%P\n"
        )

        local -a local_files
        compopt -o filenames
        mapfile -t local_files < <(compgen -f "$cur_word")

        bu_compgen -W "${path_shell_scripts[*]} ${local_files[*]}" -- "$cur_word"
    elif ((COMP_CWORD > 1))
    then
        local script
        if ! script=$(command -v -- "${COMP_WORDS[1]}")
        then
            return
        fi
        # Check if this script is covered by BashTab
        # String concatenation is not ideal, but it should do
        # Alternatively we can have a hashset of the full command paths
        if [[ " ${BU_COMMANDS[*]} " != *" $script "* ]]
        then
            return # Not covered
        fi

        __bu_autocomplete_completion_func_master_impl "$script" "$cur_word" "$prev_word" "$((COMP_CWORD - 1))" "" "${COMP_WORDS[@]:1}"
    fi
}

# Taken from stackoverflow and github gist
__bu_terminal_get_pos()
{
    local row col
    local oldstty=$(stty -g </dev/tty)
    stty raw -echo min 0 </dev/tty
    printf '%b' '\033[6n' >/dev/tty
    IFS='[;' read -r -d R _ row col </dev/tty
    stty "$oldstty" </dev/tty
    BU_RET=("$row" "$col")
    # IFS=';' read -s -d r -p $'\E[6n' row col >/dev/tty </dev/tty
    # row="${row#*[}"
    # BU_RET=("$row" "$col")
}

# Slight optimization over __bu_terminal_get_pos
__bu_terminal_get_pos2()
{
    local row col
    local oldstty=$1
    stty raw -echo min 0 </dev/tty
    printf '%b' '\033[6n' >/dev/tty
    IFS='[;' read -r -d R _ row col </dev/tty
    stty "$oldstty" </dev/tty
    BU_RET=("$row" "$col")
}

__bu_fzf_print_header()
{
    local proc_tmp_dir=$1
    local fzf_selection=$2
    shift 2

    local prev_fzf_selections=()
    mapfile -t prev_fzf_selections <"$proc_tmp_dir"/fzf_dynamic_autocomplete.txt

    printf "%s " "${prev_fzf_selections[@]}" "$fzf_selection"
}
export -f __bu_fzf_print_header

__bu_fzf_print_autocompletion()
{
    # Not sure why bash -ic ... freezes, we need to assume interactive mode to more effectively replicate the current shell
    # Note: On Ubuntu, in a non-interactive shell, the default .bashrc will just early return. No point sourcing it.
    # source "$HOME"/.bashrc &>/dev/null

    if [[ -f /usr/share/bash-completion/bash_completion ]]; then
        . /usr/share/bash-completion/bash_completion
    elif [[ -f /etc/bash_completion ]]; then
        . /etc/bash_completion
    fi

    source "$BU_DIR"/bu_entrypoint.sh &>/dev/null
    # {
    #     local i
    #     echo "$# arg(s): $*"
    #     for ((i=0;i<=$#;i++)); do
    #         printf "%s: %s\n" "$i" "${!i}"
    #     done
    # } >> "$BU_LOG_DIR"/autocomplete_debug.log

    local proc_tmp_dir=$1
    local fzf_selection=$2
    shift 2

    local prev_fzf_selections=()
    mapfile -t prev_fzf_selections <"$proc_tmp_dir"/fzf_dynamic_autocomplete.txt
    printf "%s\n" "$fzf_selection" >> "$proc_tmp_dir"/fzf_dynamic_autocomplete.txt

    local args=("$@")
    args+=("${prev_fzf_selections[@]}" "$fzf_selection" "")
    # printf "'%s' " bu_autocomplete_print_autocompletions "${args[@]}" >> "$BU_LOG_DIR"/autocomplete_debug.log
    bu_autocomplete_print_autocompletions "${args[@]}" #2>&1 | tee --append "$BU_LOG_DIR"/autocomplete_debug.log
}
# We don't really need this export unless we need to do logging earlier than the sourcing of bu_entrypoint.sh
export BU_LOG_DIR
export -f __bu_fzf_print_autocompletion

__bu_fzf_finish()
{
    local proc_tmp_dir=$1

    local prev_fzf_selections=()
    mapfile -t prev_fzf_selections <"$proc_tmp_dir"/fzf_dynamic_autocomplete.txt

    printf "%s " "${prev_fzf_selections[@]}"
}
export -f __bu_fzf_finish


declare -a -g __BU_PADDING_TABLE=(
    ''
    ' '
    '  '
    '   '
    '    '
    '     '
    '      '
    '       '
    '        '
    '         '
    '          '
    '           '
    '            '
    '             '
    '              '
    '               '
    '                '
    '                 '
    '                  '
    '                   '
    '                    '
    '                     '
    '                      '
    '                       '
    '                        '
    '                         '
    '                          '
    '                           '
    '                            '
    '                             '
    '                              '
    '                               '
    '                                '
    '                                 '
    '                                  '
    '                                   '
    '                                    '
    '                                     '
    '                                      '
    '                                       '
    '                                        '
    '                                         '
    '                                          '
    '                                           '
    '                                            '
    '                                             '
    '                                              '
    '                                               '
    '                                                '
    '                                                 '
    '                                                  '
    '                                                   '
    '                                                    '
    '                                                     '
    '                                                      '
    '                                                       '
    '                                                        '
    '                                                         '
    '                                                          '
    '                                                           '
    '                                                            '
    '                                                             '
    '                                                              '
    '                                                               '
    '                                                                '
    '                                                                 '
    '                                                                  '
    '                                                                   '
    '                                                                    '
    '                                                                     '
    '                                                                      '
    '                                                                       '
    '                                                                        '
    '                                                                         '
    '                                                                          '
    '                                                                           '
    '                                                                            '
    '                                                                             '
    '                                                                              '
    '                                                                               '
    '                                                                                '
    '                                                                                 '
    '                                                                                  '
    '                                                                                   '
    '                                                                                    '
    '                                                                                     '
    '                                                                                      '
    '                                                                                       '
    '                                                                                        '
)

# Let's parse without bothering to tokenize first
__bu_parse_bash()
{
    local -n __bu_parse_bash_token_stack=$1
    local -n __bu_parse_bash_color_stack=$2
    local -n __bu_parse_bash_op_idx_stack=$3
    __bu_parse_bash_token_stack=('')
    __bu_parse_bash_color_stack=('')
    __bu_parse_bash_op_idx_stack=(0) # Use 0 as a sentinel value
    local command_line_front=$4
    local i
    local j
    # Possible tokens on the token stack to consider
    # { : means we are in a command group
    # ( : means we are in a subshell or left bracket as part of an arithmetic expression
    # (( : means we are in an arithmetic context
    # $ : means we just saw a dollar sign, it could mean a bunch of things
    # $( : means we are in a command substitution
    # $(( : means we are in a arithmetic subsitution
    # $A : means we are inside a variable, but without the enclosing {
    # ${ : means we are inside a variable
    # ' : means we are enclosed in a single quote
    # " : means we are enclosed in a double quote
    # ) : possible closing bracket
    # Anything else : Word on the token stack
    local bracket_depth=0
    # Assume we won't get crazy deep (3 * 2 * 2 = 12 is more than enough)
    local bracket_colors=("$BU_TPUT_BOLD$BU_TPUT_VSCODE_YELLOW" "$BU_TPUT_BOLD$BU_TPUT_VSCODE_PINK" "$BU_TPUT_BOLD$BU_TPUT_VSCODE_DARK_BLUE")
    # local bracket_colors=(YY PP BB)
    bracket_colors+=("${bracket_colors[@]}")
    bracket_colors+=("${bracket_colors[@]}")
    local is_op_prev=
    local char
    local op
    local is_new_or_append_word
    local is_open_bracket
    local is_close_bracket
    local is_same_op
    local is_separator
    for ((i = 0; i < ${#command_line_front}; i++))
    do
        op=${__bu_parse_bash_token_stack[${__bu_parse_bash_op_idx_stack[-1]}]}
        char="${command_line_front:i:1}"
        if ((${#__bu_parse_bash_token_stack[@]} == "${__bu_parse_bash_op_idx_stack[-1]}" + 1))
        then
            is_op_prev=true
        else
            is_op_prev=false
        fi
        is_new_or_append_word=false
        is_open_bracket=false
        is_close_bracket=false
        is_same_op=false
        is_separator=false # &, |, ;
        case "$char" in
        '{')
            case "$op" in
            "'"|'"') 
                is_new_or_append_word=true
                ;;
            '$')
                __bu_parse_bash_token_stack[-1]='${'
                ;;
            *)
                is_open_bracket=true
                ;;
            esac
            ;;
        '(')
            case "${__bu_parse_bash_token_stack[-1]}" in
            '(')
                if "$is_op_prev"
                then
                    __bu_parse_bash_token_stack[-1]='(('
                else
                    is_open_bracket=true
                fi
                ;;
            '$(')
                if "$is_op_prev"
                then
                    __bu_parse_bash_token_stack[-1]='$(('
                else
                    is_open_bracket=true
                fi
                ;;
            '$')
                if "$is_op_prev"
                then
                    __bu_parse_bash_token_stack[-1]='$('
                    __bu_parse_bash_color_stack[-1]="${bracket_colors[bracket_depth++]}"
                else
                    :
                fi
                ;;
            "'"|'"')
                is_new_or_append_word=true
                ;;
            *)
                is_open_bracket=true
                ;;
            esac
            ;;
        ')')
            case "$op" in
            '"'|"'")
                is_new_or_append_word=true
                ;;
            ')')
                if ! "$is_op_prev"
                then
                    bu_log_err "Syntax error"
                    return 1
                fi
                is_close_bracket=true
                is_same_op=true
                ;;
            *)
                is_close_bracket=true
                ;;
            esac
            ;;
        '}')
            case "$op" in
            '"'|"'")
                is_new_or_append_word=true
                ;;
            *)
                is_close_bracket=true
                ;;
            esac
            ;;
        '|'|'&')
            case "$op" in
            "'"|'"')
                is_new_or_append_word=true
                ;;
            "$char")
                if "$is_op_prev"
                then
                    __bu_parse_bash_token_stack[-1]+=$char
                else
                    is_separator=true
                fi
                ;;
            *)
                is_separator=true
                ;;
            esac
            ;;
        ';') 
            case "$op" in
            "'"|'"')
                is_new_or_append_word=true
                ;;
            *)
                is_separator=true
                ;;
            esac
            ;;
        "'") 
            case "$op" in
            "'")
                is_close_bracket=true
                ;;
            '"')
                is_new_or_append_word=true
                ;;
            *)
                is_open_bracket=true
                ;;
            esac
            ;;
        '"')
            case "$op" in
            '"')
                is_close_bracket=true
                ;;
            "'")
                is_new_or_append_word=true
                ;;
            *)
                is_open_bracket=true
                ;;
            esac
            ;;
        '$')
            case "$op" in
            "'")
                is_new_or_append_word=true
                ;;
            '"')
                is_new_or_append_word=true
                ;;
            '$')
                if "$is_op_prev"
                then
                    __bu_parse_bash_token_stack[-1]='$$'
                    unset -v '__bu_parse_bash_op_idx_stack[-1]'
                else
                    : # Error
                fi
                ;;
            *)
                __bu_parse_bash_op_idx_stack+=("${#__bu_parse_bash_token_stack[@]}")
                __bu_parse_bash_token_stack+=('$')
                __bu_parse_bash_color_stack+=("$BU_TPUT_BOLD$BU_TPUT_VSCODE_DARK_BLUE")
                ;;
            esac
            ;;
        ' ')
            case "$op" in
            "'"|'"')
                is_new_or_append_word=true
                ;;
            *)
                __bu_parse_bash_token_stack+=(' ')
                __bu_parse_bash_color_stack+=('')
                ;;
            esac
            ;;
        *)
            # To keep things simple we will ignore backslash (\)

            case "$op" in
            '$'*|'${'*)
                __bu_parse_bash_token_stack[-1]+=$char
                ;;
            *)
                is_new_or_append_word=true
                ;;
            esac
            ;;
        esac

        if "$is_new_or_append_word"
        then
            if "$is_op_prev"
            then
                __bu_parse_bash_token_stack+=('')
                case "$op" in
                "'"|'"')
                    __bu_parse_bash_color_stack+=("$BU_TPUT_VSCODE_ORANGE")
                    ;;
                *)
                    __bu_parse_bash_color_stack+=('')
                    ;;
                esac
            fi
            __bu_parse_bash_token_stack[-1]+=$char
        fi
        if "$is_open_bracket"
        then
            __bu_parse_bash_op_idx_stack+=("${#__bu_parse_bash_token_stack[@]}")
            __bu_parse_bash_token_stack+=("$char")
            __bu_parse_bash_color_stack+=("${bracket_colors[bracket_depth++]}")
        fi
        if "$is_close_bracket"
        then
            if "$is_same_op"
            then
                __bu_parse_bash_token_stack[-1]+=$char
            else
                __bu_parse_bash_op_idx_stack+=("${#__bu_parse_bash_token_stack[@]}")
                __bu_parse_bash_token_stack+=("$char")
            fi
            # Find the nearest closing bracket
            for ((j=${#__bu_parse_bash_op_idx_stack[@]}-2; j > 0; j--))
            do
                case "${__bu_parse_bash_token_stack[${__bu_parse_bash_op_idx_stack[j]}]}" in
                '$('*|'${'*|'$(('*)
                    break
                    ;;
                ';'|'|'|'||'|'&&'|'$'*)
                    ;;
                *)
                    break
                    ;;
                esac
            done
            case "${__bu_parse_bash_token_stack[${__bu_parse_bash_op_idx_stack[j]}]}" in
            '('|'$('*)
                if [[ "${__bu_parse_bash_token_stack[-1]}" != ')' ]]
                then
                    bu_log_err "Parse error, expected ), got ${__bu_parse_bash_token_stack[-1]}"
                    return 1
                fi
                ;;
            '${'*|'{')
                if [[ "${__bu_parse_bash_token_stack[-1]}" != '}' ]]
                then
                    bu_log_err "Parse error, expected }, got ${__bu_parse_bash_token_stack[-1]}"
                    return 1
                fi
                ;;
            '(('|'$(('*)
                if [[ "${__bu_parse_bash_token_stack[-1]}" = ')' ]]
                then
                    continue
                fi
                if [[ "${__bu_parse_bash_token_stack[-1]}" != '))' ]]
                then
                    bu_log_err "Parse error, expected )), got ${__bu_parse_bash_token_stack[-1]}"
                    return 1
                fi
                ;;
            '"')
                if [[ "${__bu_parse_bash_token_stack[-1]}" != '"' ]]
                then
                    bu_log_err "Parse error, expected \", got ${__bu_parse_bash_token_stack[-1]}"
                    return 1
                fi
                ;;
            "'")
                if [[ "${__bu_parse_bash_token_stack[-1]}" != "'" ]]
                then
                    bu_log_err "Parse error, expected ', got ${__bu_parse_bash_token_stack[-1]}"
                    return 1
                fi
                ;;
            *)
                # printf -- "- %s\n" "${__bu_parse_bash_token_stack[@]}"
                # printf -- "-- %s\n" "${__bu_parse_bash_op_idx_stack[@]}"
                bu_log_err "Unexpected operator [${__bu_parse_bash_token_stack[${__bu_parse_bash_op_idx_stack[j]}]}]"
                return 1
                ;;
            esac
            __bu_parse_bash_token_stack+=('')
            __bu_parse_bash_color_stack+=("${bracket_colors[--bracket_depth]}" '')
            __bu_parse_bash_op_idx_stack=("${__bu_parse_bash_op_idx_stack[@]:0:j}")
        fi
        if "$is_separator"
        then
            __bu_parse_bash_op_idx_stack+=("${#__bu_parse_bash_token_stack[@]}")
            __bu_parse_bash_token_stack+=("$char")
            __bu_parse_bash_color_stack+=("$BU_TPUT_VSCODE_BLUE")
        fi
    done
}

bu_color_bash()
{
    local -a token_stack color_stack op_idx_stack
    local i colored_command_line
    __bu_parse_bash token_stack color_stack op_idx_stack "$*"

    for ((i=op_idx_stack[-1]+1; i < ${#token_stack[@]}; i++))
    do
        case "${token_stack[i]}" in
        *=*)
            color_stack[i]=$BU_TPUT_VSCODE_DARK_GREEN # Setting Environment variable
            ;;
        *)
            color_stack[i]=$BU_TPUT_VSCODE_GREEN # Command
            break
            ;;
        esac
    done

    for ((i=0;i<${#token_stack[@]};i++))
    do
        colored_command_line+=${color_stack[i]}${token_stack[i]}"$BU_TPUT_RESET"
    done
    printf "%s\n" "$colored_command_line"
}

export BU_TPUT_UNDERLINE BU_TPUT_RESET
__bu_bind_fzf_autocomplete_impl_display()
{
    local line=$1
    line=${line//'__ANSI__'/$'\E'}
    line=${line//'\n'/$'\n'}
    printf "%s" "$line"
}

export -f __bu_bind_fzf_autocomplete_impl_display

__bu_bind_fzf_autocomplete_impl()
{
    local command_line_front=$1
    local command_line_back=$2
    local move_cursor_to_end=$3
    local fzf_dynamic_reload=${4:-false}
    local use_tab_to_confirm=${5:-false}

    if "$BU_AUTOCOMPLETE_USE_TREE_SITTER" && bu_symbol_is_function bu_ts_parse; then
        __bu_bind_fzf_autocomplete_impl_ts "$@"
        return
    fi

    local delimiter=$'\x01'


    
    # This works for many simple expressions, but even something like
    # grep $(ls) --<autocomplete> will break
    # command_line_front_after_pipe=${command_line_front_after_pipe##*'('}
    # command_line_front_after_pipe=${command_line_front_after_pipe##*'{ '} # Note brace requires a space right after
    # command_line_front_after_pipe=${command_line_front_after_pipe##*'||'}
    # command_line_front_after_pipe=${command_line_front_after_pipe##*'&&'}
    # command_line_front_after_pipe=${command_line_front_after_pipe##*';'}
    # command_line_front_after_pipe=${command_line_front_after_pipe##*'|'}
    # command_line_front_after_pipe=${command_line_front_after_pipe#"${command_line_front_after_pipe%%[![:space:]]*}"}

    local -a token_stack color_stack op_idx_stack 
    local i colored_command_line
    __bu_parse_bash token_stack color_stack op_idx_stack "$command_line_front"

    local environment_vars=

    while ((${#op_idx_stack[@]} > 1))
    do
        case "${token_stack[op_idx_stack[-1]]}" in
        '$('|'$((') break;;
        '"'|"'"|'('|'{') unset -v 'op_idx_stack[-1]';;
        '$'*) unset -v 'op_idx_stack[-1]';;
        *) break;;
        esac
    done

    for ((i = ${op_idx_stack[-1]} + 1; i < ${#token_stack[@]}; i++))
    do
        case "${token_stack[i]}" in
        *=*|' ')
            # For convenience we also append any spaces we find here
            environment_vars+=${token_stack[i]}
            ;;
        *)
            command_name=${token_stack[i]}
            break
            ;;
        esac
    done
    # printf -- "- %s\n" "${token_stack[@]}"
    # printf -- "-- %s\n" "${op_idx_stack[@]}"
    bu_list_join '' "${token_stack[@]:i}"
    local command_line_front_after_pipe=${BU_RET#"${BU_RET%%[![:space:]]*}"} # Remove any leading space

    local command_line_options_colored=
    for ((i++; i < ${#token_stack[@]}; i++))
    do
        case "${token_stack[i]}" in
        -*|--*|' '-*|' '--*)
            command_line_options_colored+=${BU_TPUT_VSCODE_DARK_BLUE}${token_stack[i]}${BU_TPUT_RESET}
            ;;
        *)
            command_line_options_colored+=${token_stack[i]}
            ;;
        esac
    done

    command_name=${command_name#"${command_name%%[![:space:]]*}"}
    environment_vars=${environment_vars#"${environment_vars%%[![:space:]]*}"}

    local command_line_front_before_pipe=${command_line_front:0:${#command_line_front}-${#command_line_front_after_pipe}}
    command_line_front_before_pipe=${command_line_front_before_pipe%$environment_vars}

    # printf "%s\n" "$command_line_front_before_pipe"

    local command_line=($command_line_front_after_pipe)

    tput sc
    local oldstty=$(stty -g </dev/tty)
    __bu_terminal_get_pos2 "$oldstty"
    local row_start=${BU_RET[0]}
    # https://stackoverflow.com/questions/22322879/how-to-print-current-bash-prompt
    # Note that @P is a Bash 4.4 feature.
    # Remove \[ \] markers (preserve content — ANSI codes inside need to survive)
    # and strip kitty OSC 133 shell-integration sequences which contain $? that
    # @P would expand, corrupting them into visible garbage.
    local ps1_clean
    ps1_clean=$(printf '%s' "$PS1" | sed -E 's/\\\[|\\\]//g; s/\\e\\]133;[^\\]*(\\a|\\e\\)//g')
    # Now @P-expand the cleaned prompt and take the last line (after last \n → real newline)
    local ps1_expanded="${ps1_clean@P}"
    local ps1_last_row="${ps1_expanded##*$'\n'}"
    printf "%s" "$ps1_last_row" # | tee /tmp/bashtab_prompt.raw
    #echo "" >> /tmp/bashtab_prompt.raw

    # Compute visible prompt width.  Strip all ANSI escape sequences from
    # the already-rendered string: CSI (ESC [ ... letter), OSC (ESC ] ... BEL).
    local ps1_noesc
    ps1_noesc=$(printf '%s' "$ps1_last_row" | sed -E 's/\x1B\[[^a-zA-Z]*[a-zA-Z]//g; s/\x1B\][^\x07]*(\x07|\x1B\\)//g; s/\x1B[PX^_][^\x1B]*(\x1B\\)?//g')
    local col_with_ps1=$((${#ps1_noesc} % COLUMNS))

    local command_line_back_last_word=${command_line_back%%[[:space:]]*}
    local command_line_back_no_operator=${command_line_back_last_word}
    command_line_back_no_operator=${command_line_back_no_operator%%')'*}
    command_line_back_no_operator=${command_line_back_no_operator%%';'*}
    command_line_back_no_operator=${command_line_back_no_operator%%'&&'*}
    command_line_back_no_operator=${command_line_back_no_operator%%'|'*}

    local displayed_command_line_back=${BU_TPUT_RED}${command_line_back_no_operator}${BU_TPUT_RESET}${BU_TPUT_GREY}${command_line_back:${#command_line_back_no_operator}}${BU_TPUT_RESET}

    printf "%s%s%s%s%s%s" "${BU_TPUT_GREY}${command_line_front_before_pipe}${BU_TPUT_RESET}" "${BU_TPUT_VSCODE_GREEN}${environment_vars}${BU_TPUT_RESET}" "${BU_TPUT_VSCODE_YELLOW}${command_name}${BU_TPUT_RESET}" "${command_line_options_colored}" "${BU_TPUT_BLUE}${BU_TPUT_UNDERLINE}?${BU_TPUT_RESET}" "$displayed_command_line_back"

    # We need to append a space if we swallowed a space
    if [[ "${command_line_front:${#command_line_front}-1}" = ' ' ]]
    then
        command_line+=("")
    fi

    if ((!${#command_line[@]}))
    then
        command_line+=("")
    fi

    if ((${#command_line[@]} > 1))
    then
        bu_autocomplete_initialize_current_completion_options "${command_line[0]}"
    else
        BU_COMPOPT_CURRENT_COMPLETION_OPTIONS=()
        BU_COMPOPT_DYNAMIC_COMPLETION_OPTIONS=()
    fi

    BU_RET_MAP=()
    local BU_COMPREPLY_HINT=
    # "Type info"
    local -a BU_COMPREPLY_METADATA=()
    # bu_print_var BU_COMPOPT_CURRENT_COMPLETION_OPTIONS > /dev/tty
    bu_autocomplete_get_autocompletions --accept-ansi-colors "${command_line[@]}"
    if (($? && !${#COMPREPLY[@]}))
    then
        tput rc
        bu_log_err "bu_autocomplete_get_autocompletions ${command_line[0]} ... failed"
        return 1
    fi

    if ((!${#COMPREPLY[@]}))
    then
        if [[ -n "${BU_COMPREPLY_HINT}" ]]
        then
            printf "\n%s\n" "${BU_TPUT_VSCODE_YELLOW}Hint:${BU_TPUT_RESET} ${BU_COMPREPLY_HINT}"
        fi
        tput rc

        return 0
    fi

    local completion_func_has_ansi_colors=${BU_RET_MAP[has_ansi_colors]:-false}
    # bu_print_var BU_COMPOPT_CURRENT_COMPLETION_OPTIONS > /dev/tty
    local is_nospace=false
    local is_dynamic_nospace=false
    local is_filenames=false
    if ((${#command_line[@]} > 1))
    then
        if [[ "${BU_COMPOPT_CURRENT_COMPLETION_OPTIONS[nospace]}" = -o ]]
        then
            is_nospace=true
        fi
        if [[ "${BU_COMPOPT_DYNAMIC_COMPLETION_OPTIONS[nospace]}" = -o ]]
        then
            is_dynamic_nospace=true
        fi
        if [[ "${BU_COMPOPT_CURRENT_COMPLETION_OPTIONS[filenames]}" = -o || "${BU_COMPOPT_DYNAMIC_COMPLETION_OPTIONS[filenames]}" = -o ]]
        then
            is_filenames=true
        fi
    fi

    local is_ansi=$completion_func_has_ansi_colors
    if ! "$completion_func_has_ansi_colors"
    then
        if "$is_filenames"
        then
            local i
            # We won't do this processing if COMPREPLY is too big to avoid lag
            if ((${#COMPREPLY[@]} < 2000))
            then
                for (( i = 0; i < ${#COMPREPLY[@]}; i++ ))
                do
                    if [[ -d "${COMPREPLY[i]}" && "${COMPREPLY[i]:${#COMPREPLY[i]}-1}" != / ]]
                    then
                        COMPREPLY[i]+=/
                    fi
                done
                if ((${#COMPREPLY[@]})) && [[ -e ${COMPREPLY[0]} && -e ${COMPREPLY[-1]} ]]
                then
                    mapfile -t BU_COMPREPLY_METADATA < <(file "${COMPREPLY[@]}" | sed 's/.*: *//' | awk '{printf "%s\n", substr($0, 1, 20)}')
                    BU_COMPREPLY_METADATA=("${BU_COMPREPLY_METADATA[@]/#/${BU_TPUT_GREY}}")
                    BU_COMPREPLY_METADATA=("${BU_COMPREPLY_METADATA[@]/%/${BU_TPUT_RESET}}")
                fi
                #mapfile -t COMPREPLY < <(printf "%q\n" "${COMPREPLY[@]}")

                # Get some ansi color codes in to make the world more colorful
                # - If completion func already provides ansi colors, then don't proceed 
                # - Heuristic, if 2 elements (the first and the last) of COMPREPLY
                #   exist relative to our current working directory, then we assume
                #   that all the remaining elements also exist. We could strengthen the
                #   heuristic by testing more files.
                if ((${#COMPREPLY[@]})) && [[ -e ${COMPREPLY[0]} && -e ${COMPREPLY[-1]} ]]
                then
                    # Note: -U is a gnu ls option
                    mapfile -t COMPREPLY < <(ls -d -U --color -- "${COMPREPLY[@]}")
                    is_ansi=true
                fi
            fi
        else
            # mapfile -t COMPREPLY < <(printf "%q\n" "${COMPREPLY[@]}")
            case "${command_line[0]}" in          
            *)
                ;;
            esac

            # ── Enrich preview from external command --help / fig specs ──
            if "$BU_AUTOCOMPLETE_BIND_FZF_DISPLAY_METADATA" && bu_symbol_is_function __bu_help_enrich_preview
            then
                local _help_should_preview
                __bu_help_enrich_preview COMPREPLY BU_COMPREPLY_METADATA "${command_line[@]}"
                _help_should_preview=$BU_RET
            fi
        fi
    fi

    __bu_terminal_get_pos2 "$oldstty"
    local row_before_fzf=${BU_RET[0]}


    local base_width=60

    local bu_compreply_metadata_no_ansi=()
    local show_preview=false

    # Force preview when --help descriptions are available for external commands
    if [[ "${_help_should_preview:-false}" == true ]]
    then
        show_preview=true
    fi

    if "$BU_AUTOCOMPLETE_BIND_FZF_DISPLAY_METADATA" && (("${#BU_COMPREPLY_METADATA[@]}" > 0)) && ((${#COMPREPLY[@]} < 2000))
    then
        mapfile -t bu_compreply_metadata_no_ansi < <(sed -r -e 's/\\n/ /g' -e "s/\x1B\[([0-9]{1,3}(;[0-9]{1,3})*)?[mGK]//g" < <(printf "%s\n" "${BU_COMPREPLY_METADATA[@]}"))
        local total_len=0
        for ((i=0; i < ${#bu_compreply_metadata_no_ansi[@]}; i++))
        do
            : $((total_len+=${#bu_compreply_metadata_no_ansi[i]}))
        done
        local avg_len=$(( total_len / ${#bu_compreply_metadata_no_ansi[@]} ))
        base_width=$(( base_width > avg_len + 30 ? base_width : avg_len + 30 ))
        base_width=$(( base_width > ${#__BU_PADDING_TABLE[@]} ? ${#__BU_PADDING_TABLE[@]} : base_width ))
        for ((i=0; i < ${#bu_compreply_metadata_no_ansi[@]}; i++))
        do
            if (( base_width < ${#bu_compreply_metadata_no_ansi[i]} ))
            then
                show_preview=true
                break
            fi
        done
    fi

    local preview_window_size=0
    if "$show_preview"; then
        preview_window_size=40
    fi

    # Anchor dropdown under the completing word's first character
    local _fw_anchor=$(( (col_with_ps1 - 2 + READLINE_POINT - ${#command_line[-1]}) % COLUMNS ))
    (( _fw_anchor < 0 )) && _fw_anchor=0
    __bu_fzf_compute_dimensions "$COLUMNS" "$_fw_anchor" "${#command_line[-1]}" "$base_width" "$preview_window_size"
    local left_pos=${BU_RET[0]}
    local right_margin=${BU_RET[1]}
    local box_length=${BU_RET[2]}

    # Preserve a typed opening quote across whole-word replacement: candidates
    # can't carry the quote through compgen -W, and fzf misreads a leading `'`
    # as an extended-search operator. Strip it for --query, re-attach on insert.
    local quote_prefix=
    local query_word=${command_line[-1]}
    __bu_autocomplete_quote_prefix "$query_word"
    quote_prefix=${BU_RET[0]}
    query_word=${BU_RET[1]}

    local fzf_opts=(
        --exit-0
        --select-1
        --reverse
        --height 20% --min-height 14
        --extended --exact -i
        --cycle
        --no-sort
        --sync
        --margin "0,$right_margin,0,$left_pos"
        --query "$query_word"
    )

    if [[ -n "$BU_COMPREPLY_HINT" ]]
    then
        fzf_opts+=(--header "Hint: $BU_COMPREPLY_HINT")
    fi

    if "$BU_AUTOCOMPLETE_BIND_FZF_DISPLAY_METADATA" && (("${#BU_COMPREPLY_METADATA[@]}")) && ((${#COMPREPLY[@]} < 2000))
    then
        local i
        local pad
        local min_pad=1
        # Save colored copy before __ANSI__ escape (used for inline display)
        local -a bu_compreply_metadata_colored=("${BU_COMPREPLY_METADATA[@]}")
        # https://github.com/junegunn/fzf/issues/4626
        BU_COMPREPLY_METADATA=("${BU_COMPREPLY_METADATA[@]//$'\E'/'__ANSI__'}") # Extremely hacky to prevent fzf from swallowing our ansi colors
        if ! "$is_ansi"
        then
            # echo box_length: $box_length
            local _trim
            for i in "${!bu_compreply_metadata_no_ansi[@]}"
            do
                _trim=$((box_length - ${#COMPREPLY[i]}))
                ((_trim < 0)) && _trim=0
                bu_compreply_metadata_no_ansi[i]=${bu_compreply_metadata_no_ansi[i]:0:$_trim}
                pad=$((box_length - ${#COMPREPLY[i]} - ${#bu_compreply_metadata_no_ansi[i]}))
                # echo COMPREPLY: ${#COMPREPLY[i]} bu_compreply_metadata_no_ansi: ${#bu_compreply_metadata_no_ansi[i]} ${bu_compreply_metadata_no_ansi[i]} pad: $pad
                COMPREPLY[i]=${COMPREPLY[i]}${delimiter}${__BU_PADDING_TABLE[pad > min_pad ? pad : min_pad]}${bu_compreply_metadata_colored[i]}${delimiter}${BU_COMPREPLY_METADATA[i]}
            done
        else
            # Best effort attempt to strip ansi color codes
            # https://stackoverflow.com/questions/17998978/removing-colors-from-output
            # ansi2txt seems really good, but let's go dependency free and use sed
            local -a compreply_no_color
            mapfile -t compreply_no_color < <(sed -r -e 's/\x1B\(B\x1B\[m//g' -e "s/\x1B\[([0-9]{1,3}(;[0-9]{1,3})*)?[mGK]//g" < <(printf "%s\n" "${COMPREPLY[@]}"))
            # echo box_length: $box_length
            local _trim
            for i in "${!bu_compreply_metadata_no_ansi[@]}"
            do
                _trim=$((box_length - ${#compreply_no_color[i]}))
                ((_trim < 0)) && _trim=0
                bu_compreply_metadata_no_ansi[i]=${bu_compreply_metadata_no_ansi[i]:0:$_trim}
                pad=$((box_length - ${#compreply_no_color[i]} - ${#bu_compreply_metadata_no_ansi[i]}))
                # printf "%q " compreply_no_color: \"${compreply_no_color[i]}\" ${#compreply_no_color[i]} bu_compreply_metadata_no_ansi: ${bu_compreply_metadata_no_ansi[i]} ${#bu_compreply_metadata_no_ansi[i]} ${bu_compreply_metadata_no_ansi[i]} pad: $pad
                # echo
                COMPREPLY[i]=${COMPREPLY[i]}${delimiter}${__BU_PADDING_TABLE[pad > min_pad ? pad : min_pad]}${bu_compreply_metadata_colored[i]}${delimiter}${BU_COMPREPLY_METADATA[i]}
            done
        fi

        fzf_opts+=(
            --delimiter "$delimiter"
            --nth 1
            --with-nth 1,2
        )

        if "${show_preview}"
        then
            fzf_opts+=(
                --preview="__bu_bind_fzf_autocomplete_impl_display {3}" 
                --preview-window=:$preview_window_size:wrap
            )
        fi

        is_ansi=true
    fi

    if "$is_ansi"
    then
        fzf_opts+=(--ansi)
    fi

    local fzf_colors=(
        #   fg         Text
        #   bg         Background
        #   preview-fg Preview window text
        #   preview-bg Preview window background
        #   hl         Highlighted substrings
        #   fg+        Text (current line)
        #   bg+        Background (current line)
        #   gutter     Gutter on the left (defaults to bg+)
        #   hl+        Highlighted substrings (current line)
        #   info       Info
        #   border     Border of the preview window and horizontal separators (--border)
        #   prompt     Prompt
        #   pointer    Pointer to the current line
        #   marker     Multi-select marker
        #   spinner    Streaming input indicator
        #   header     Header
        'fg:#569CD6' # VSCode Dark+ dark blue text, approx xterm 74
        'bg:#1F1F1F' # VSCode Dark+ background, approx xterm 16
        'hl:#C586C0' # VSCode Dark+ pink text, approx xterm 175
        'fg+:#9CDCFE' # VSCode Dark+ blue text, approx xterm 153
        'hl+:#D16969' # VSCode Dark+ red text, approx xterm 167
        'header:#DCDCAA' # VSCode Dark+ function text, approx xterm 187
        'prompt:#DCDCAA'
        'info:#B5CEA8'
        'pointer:#CCCCCC' # VSCode Dark+ regular text, approx xterm 188
        'border:#CCCCCC'
        'gutter:#1F1F1F'
        'preview-fg:-1'
        'preview-bg:-1'
    )
    bu_list_join , "${fzf_colors[@]}"
    fzf_opts+=(--color=dark,"$BU_RET")

    local selected_command
    if selected_command=$(
        if "$fzf_dynamic_reload"
        then
            # Initial design:
            # - tab: selects a suggestion, then moves on to the next word
            # - enter: selects a suggestion and quits (i.e. almost same as the default accept behavior)
            # - change: no additional handling needed

            local command_line_no_last=("${command_line[@]}")
            if ((${#command_line_no_last[@]}))
            then
                unset command_line_no_last[-1]
            fi
            : > "$BU_PROC_TMP_DIR"/fzf_dynamic_autocomplete.txt
            printf "%s\n" "${COMPREPLY[@]}" | uniq | \
                fzf \
                    --header '' \
                    "${fzf_opts[@]}" \
                    --bind "tab:clear-query+transform-header(bash -c '__bu_fzf_print_header $BU_PROC_TMP_DIR \"{}\" ${command_line_no_last[*]}')+reload-sync(bash -c '__bu_fzf_print_autocompletion $BU_PROC_TMP_DIR \"{}\" ${command_line_no_last[*]}')" \
                    --bind "enter:transform-query(bash -c '__bu_fzf_finish $BU_PROC_TMP_DIR')+print-query"

            rm -f "$BU_PROC_TMP_DIR"/fzf_dynamic_autocomplete.txt
        else
            # No need for tput lines and tput cols, bash already has $LINES and $COLUMNS
            # margin is Top,Right,Bottom,Left
            # Note that VSCode's completion suggestion box is 12 lines high, for fzf we also need to account for the finder info and search box
            
            if "$use_tab_to_confirm"
            then
                fzf_opts+=(--bind "tab:accept")
            fi
            
            if (("${#COMPREPLY[@]}" > 10000))
            then
                printf "%s\n" "${COMPREPLY[@]}" | \
                    fzf \
                        "${fzf_opts[@]}"
            else
                printf "%s\n" "${COMPREPLY[@]}" | sort --unique | \
                    fzf \
                        "${fzf_opts[@]}"
            fi
        fi
    ) && [[ -n "$selected_command" ]]
    then
        if "$BU_AUTOCOMPLETE_BIND_FZF_DISPLAY_METADATA" && (("${#BU_COMPREPLY_METADATA[@]}"))
        then
            selected_command=${selected_command%%"${delimiter}"*}
        fi
        # Bash seems to be bugged sometimes when READLINE_LINE is modified multiple times
        # So we use these temporary variables, and set READLINE_LINE, READLINE_POINT in one shot at the end
        local readline_line
        local readline_point
        command_line[-1]="${quote_prefix}${selected_command}"
        readline_line=${command_line[*]}
        # Remove the last word of command_line_back
        command_line_back=${command_line_back:${#command_line_back_no_operator}}
        # Remove a space if any, because we're about to insert one later one (of course, depending on if nospace is set, and some other conditions)
        command_line_back=${command_line_back# }
        
        # If we are expecting filenames, then if the file is a directory, we're not done, so don't append a space.
        # Dynamic nospace (compopt -o nospace issued DURING the completion) is
        # honored unconditionally — the completion function asked for no space.
        # Static spec nospace keeps the suffix heuristic: respect it only when
        # the completed word looks like it needs a suffix (directory /, option
        # =, namespace :, etc.) — not for subcommands that just happen to have
        # nospace set by their completion spec.
        if ! "$is_dynamic_nospace" && \
           ! { "$is_filenames" && [[ "${readline_line:${#readline_line}-1}" = / ]]; } && \
           ! { "$is_nospace" && [[ "${readline_line:${#readline_line}-1}" = [/=:@] ]]; } && \
           [[ "${readline_line:${#readline_line}-1}" != ' ' && "${command_line_back:0:1}" != ' ' ]]
        then
            readline_line+=' '
        fi

        readline_line=${command_line_front_before_pipe}${environment_vars}${readline_line}

        readline_point=${#readline_line}
        readline_line+=$command_line_back
        if "$move_cursor_to_end"
        then
            if [[ "${readline_line:${#readline_line}-1}" != ' ' && "${command_line_back:0:1}" != ' ' ]]
            then
                readline_line+=' '
            fi
            readline_point=${#readline_line}
        fi
        READLINE_LINE=$readline_line
        READLINE_POINT=$readline_point
    fi
    __bu_terminal_get_pos2 "$oldstty"
    local row_after_fzf=${BU_RET[0]}
    # fzf might shift our command line up if there isn't enough space at the bottom
    # If fzf shifts, then there is no need to restore the cursor
    if ((row_before_fzf == row_after_fzf))
    then
        tput rc
    elif ((row_start < row_before_fzf))
    then
        tput cuu "$((row_before_fzf - row_start))"
    fi
}

# ```
# *Description*:
# Binds fzf to the autocomplete of the current command line at the cursor position.
# This is a readline binding function.
#
# *Params*: None
#
# *Returns*: None
# ```
__bu_bind_fzf_autocomplete()
{
    __bu_bind_fzf_autocomplete_impl "${READLINE_LINE:0:$READLINE_POINT}" "${READLINE_LINE:$READLINE_POINT}" false false
}

__bu_bind_fzf_autocomplete_dynamic()
{
    __bu_bind_fzf_autocomplete_impl "${READLINE_LINE:0:$READLINE_POINT}" "${READLINE_LINE:$READLINE_POINT}" false true
}

__bu_bind_fzf_tab_autocomplete()
{
    __bu_bind_fzf_autocomplete_impl "${READLINE_LINE:0:$READLINE_POINT}" "${READLINE_LINE:$READLINE_POINT}" false false true
}

# ```
# *Description*:
# Tree-sitter powered fzf autocomplete implementation.
# Uses the tree-sitter-bash daemon for accurate cursor-position tracking,
# range-based replacement (LSP TextEdit style), and context-aware completion.
# ```
__bu_bind_fzf_autocomplete_impl_ts()
{
    local command_line_front=$1
    local command_line_back=$2
    local move_cursor_to_end=$3
    local fzf_dynamic_reload=${4:-false}
    local use_tab_to_confirm=${5:-false}

    local cursor_offset=${#command_line_front}

    # Parse with tree-sitter daemon
    bu_ts_parse "$cursor_offset" "$command_line_front" || {
        # Fall back to built-in parser if tree-sitter fails
        __bu_bind_fzf_autocomplete_impl_legacy "$@"
        return
    }

    local original=${BU_TS_RESULT[original]}
    local pipe_before=${BU_TS_RESULT[pipeBefore]}
    local pipe_after=${BU_TS_RESULT[pipeAfter]}
    local cmd_name=${BU_TS_RESULT[cmdName]}
    local complete_kind=${BU_TS_RESULT[cursor,completeKind]}
    local replace_start=${BU_TS_RESULT[cursor,replaceStart]}
    local replace_end=${BU_TS_RESULT[cursor,replaceEnd]}

    # Build command_line array from cmdWords (unit-separator delimited)
    local -a command_line=()
    local _saved_ifs=$IFS
    IFS=$''
    if [[ -n "${BU_TS_RESULT[cmdWords]}" ]]; then
        command_line=(${BU_TS_RESULT[cmdWords]})
    else
        command_line=("")
    fi
    IFS=$_saved_ifs
    # Bash drops trailing empty fields; restore if original ends with space
    if [[ "${original:${#original}-1}" = ' ' ]]; then
        command_line+=("")
    fi

    tput sc
    local oldstty=$(stty -g </dev/tty)
    __bu_terminal_get_pos2 "$oldstty"
    local row_start=${BU_RET[0]}

    # strip kitty OSC 133 shell-integration sequences which contain $? that
    # @P would expand, corrupting them into visible garbage.
    local ps1_clean=$(sed -E 's/\\e\\]133;[^\\]*(\\a|\\e\\)//g' <<<"$PS1")
    local ps1_clean_last_row=${ps1_clean##*$'\n'}
    # Now @P-expand the cleaned prompt and take the last line (after last \n → real newline)
    local ps1_expanded="${ps1_clean_last_row@P}"
    local ps1_last_row="${ps1_expanded##*$'\n'}"
    printf "%s" "$ps1_last_row" # | tee /tmp/bashtab_prompt_ts.raw
    #echo "" >> /tmp/bashtab_prompt_ts.raw

    # Compute visible prompt width.  Strip all ANSI escape sequences from
    # the already-rendered string: CSI (ESC [ ... letter), OSC (ESC ] ... BEL).
    local ps1_noesc=$(sed -E 's/\\\[([^\\]*([^\\]\]|\\[^]])?)*\\\]//g; s/\x1B\[[^a-zA-Z]*[a-zA-Z]//g; s/\x1B\][^\x07]*(\x07|\x1B\\)//g; s/\x1B[PX^_][^\x1B]*(\x1B\\)?//g' <<<"$ps1_clean_last_row")
    local ps1_noesc_rendered="${ps1_noesc@P}"
    local col_with_ps1=$((${#ps1_noesc_rendered} % COLUMNS))

    # bu_log_tty "Len:$col_with_ps1|$ps1_noesc|$ps1_clean_last_row|"

    # Print the full command line with syntax highlighting (IDE-style preview)
    # Build the text already typed between command name and the word being completed
    local prefix_end=${#pipe_before}
    if [[ -n "${BU_TS_RESULT[envVars]}" ]]; then
        prefix_end=$((prefix_end + ${#BU_TS_RESULT[envVars]} + 1))
    fi
    prefix_end=$((prefix_end + ${#cmd_name}))
    # When cursor is at end of line, replaceStart/End are both 0; use cursor offset
    local effective_start=$replace_start
    local effective_end=$replace_end
    if (( effective_start == 0 && effective_end == 0 )); then
        effective_start=$cursor_offset
        effective_end=$cursor_offset
    fi
    local already_typed=""
    if (( effective_start > prefix_end )); then
        already_typed="${original:prefix_end:effective_start-prefix_end}"
    fi
    local completing_word=""
    # Only show completing word if it starts after the command name
    if (( effective_end > effective_start && effective_start >= prefix_end )); then
        completing_word="${original:effective_start:effective_end-effective_start}"
    fi

    # Build displayed back portion (first word in red, rest in grey)
    local back_first=${command_line_back%%[[:space:]]*}
    local back_rest=${command_line_back:${#back_first}}
    local displayed_back=${BU_TPUT_RED}${back_first}${BU_TPUT_RESET}${BU_TPUT_GREY}${back_rest}${BU_TPUT_RESET}

    printf "%s%s%s%s%s%s" \
        "${BU_TPUT_GREY}${pipe_before}${BU_TPUT_RESET}" \
        "${BU_TPUT_VSCODE_GREEN}${BU_TS_RESULT[envVars]}${BU_TPUT_RESET}" \
        "${BU_TPUT_VSCODE_YELLOW}${cmd_name}${BU_TPUT_RESET}" \
        "${already_typed}" \
        "${BU_TPUT_VSCODE_RED}${completing_word}${BU_TPUT_BLUE}${BU_TPUT_UNDERLINE}?${BU_TPUT_RESET}" \
        "$displayed_back"

    # --- Generate completions based on the kind of node at cursor ---
    COMPREPLY=()
    local BU_COMPREPLY_METADATA=()
    local BU_COMPREPLY_HINT=
    local BU_RET_MAP=()
    local is_ansi=false
    local is_range_replace=false

    case "$complete_kind" in
    dollar_word|dollar_brace)
        # Variable expansion: complete variable names (range-based)
        is_range_replace=true
        local cur_text=${BU_TS_RESULT[cursor,replaceText]}
        local var_name=${cur_text#\$}
        var_name=${var_name#\{}
        if [[ "$complete_kind" == "dollar_brace" ]]; then
            COMPREPLY=($(compgen -A variable -P "\${" -S "}" -- "$var_name"))
        else
            COMPREPLY=($(compgen -A variable -P "\$" -- "$var_name"))
        fi
        ;;
    *)
        # Generic completion via bash completion system (whole-word replacement)
        bu_autocomplete_initialize_current_completion_options "${command_line[0]}"
        if ((${#command_line[@]} > 1)); then
            bu_autocomplete_initialize_current_completion_options "${command_line[0]}"
        else
            BU_COMPOPT_CURRENT_COMPLETION_OPTIONS=()
            BU_COMPOPT_DYNAMIC_COMPLETION_OPTIONS=()
        fi
        bu_autocomplete_get_autocompletions --accept-ansi-colors "${command_line[@]}"
        is_ansi=${BU_RET_MAP[has_ansi_colors]:-false}
        ;;
    esac

    if (( ${#COMPREPLY[@]} == 0 )) && [[ -z "$BU_COMPREPLY_HINT" ]]; then
        tput rc
        return 0
    fi

    local is_nospace=false
    local is_dynamic_nospace=false
    local is_filenames=false
    if ((${#command_line[@]} > 1)); then
        [[ "${BU_COMPOPT_CURRENT_COMPLETION_OPTIONS[nospace]}" = -o ]] && is_nospace=true
        [[ "${BU_COMPOPT_DYNAMIC_COMPLETION_OPTIONS[nospace]}" = -o ]] && is_dynamic_nospace=true
        [[ "${BU_COMPOPT_CURRENT_COMPLETION_OPTIONS[filenames]}" = -o || "${BU_COMPOPT_DYNAMIC_COMPLETION_OPTIONS[filenames]}" = -o ]] && is_filenames=true
    fi

    # --- Enrich preview from external command --help / fig specs (TS path) ---
    local _help_should_preview_ts=false
    if "$BU_AUTOCOMPLETE_BIND_FZF_DISPLAY_METADATA" && bu_symbol_is_function __bu_help_enrich_preview
    then
        __bu_help_enrich_preview COMPREPLY BU_COMPREPLY_METADATA "${command_line[@]}"
        _help_should_preview_ts=$BU_RET
    fi

    # --- fzf display setup ---
    __bu_terminal_get_pos2 "$oldstty"
    local row_before_fzf=${BU_RET[0]}

    local fzf_opts=(
        --exit-0
        --select-1
        --reverse
        --height 20% --min-height 14
        --extended --exact -i
        --cycle
        --no-sort
        --sync
    )

    # --- Width & metadata calculations (shared with non-TS path) ---
    local base_width=60
    local bu_compreply_metadata_no_ansi=()
    local show_preview=false

    # Force preview when --help descriptions are available for external commands
    if [[ "${_help_should_preview_ts:-false}" == true ]]
    then
        show_preview=true
    fi

    if "$BU_AUTOCOMPLETE_BIND_FZF_DISPLAY_METADATA" && (("${#BU_COMPREPLY_METADATA[@]}" > 0)) && ((${#COMPREPLY[@]} < 2000)); then
        mapfile -t bu_compreply_metadata_no_ansi < <(sed -r -e 's/\\n/ /g' -e "s/\x1B\[([0-9]{1,3}(;[0-9]{1,3})*)?[mGK]//g" < <(printf "%s\n" "${BU_COMPREPLY_METADATA[@]}"))
        local _ts_total=0 _ts_i
        for ((_ts_i=0; _ts_i < ${#bu_compreply_metadata_no_ansi[@]}; _ts_i++)); do
            : $((_ts_total+=${#bu_compreply_metadata_no_ansi[_ts_i]}))
        done
        local _ts_avg=$(( _ts_total / ${#bu_compreply_metadata_no_ansi[@]} ))
        base_width=$(( base_width > _ts_avg + 30 ? base_width : _ts_avg + 30 ))
        base_width=$(( base_width > ${#__BU_PADDING_TABLE[@]} ? ${#__BU_PADDING_TABLE[@]} : base_width ))
        for ((_ts_i=0; _ts_i < ${#bu_compreply_metadata_no_ansi[@]}; _ts_i++)); do
            if (( base_width < ${#bu_compreply_metadata_no_ansi[_ts_i]} )); then
                show_preview=true; break
            fi
        done
    fi

    local preview_window_size=0
    if "$show_preview"; then
        preview_window_size=40
    fi

    # Anchor under the completing word
    local _fw_replace_len=${BU_TS_RESULT[cursor,replaceEnd]}
    _fw_replace_len=$((_fw_replace_len - ${BU_TS_RESULT[cursor,replaceStart]}))
    (( _fw_replace_len < 0 )) && _fw_replace_len=0
    local _fw_anchor=$(( (col_with_ps1 - 2 + READLINE_POINT - _fw_replace_len) % COLUMNS ))
    (( _fw_anchor < 0 )) && _fw_anchor=0
    __bu_fzf_compute_dimensions "$COLUMNS" "$_fw_anchor" "$_fw_replace_len" "$base_width" "$preview_window_size"
    local left_pos=${BU_RET[0]}
    local right_margin=${BU_RET[1]}
    local box_length=${BU_RET[2]}

    fzf_opts+=(--margin "0,$right_margin,0,$left_pos")

    # Preserve a typed opening quote across whole-word replacement (same as the
    # non-TS path): candidates can't carry the quote through compgen -W, and a
    # leading `'` would be misread by fzf as an extended-search operator.
    local quote_prefix=
    local query_word=${BU_TS_RESULT[cursor,replaceText]}
    __bu_autocomplete_quote_prefix "$query_word"
    quote_prefix=${BU_RET[0]}
    query_word=${BU_RET[1]}
    fzf_opts+=(--query "$query_word")

    if [[ -n "$BU_COMPREPLY_HINT" ]]; then
        fzf_opts+=(--header "Hint: $BU_COMPREPLY_HINT")
    fi

    local fzf_colors=(
        'fg:#569CD6' 'bg:#1F1F1F' 'hl:#C586C0' 'fg+:#9CDCFE'
        'hl+:#D16969' 'header:#DCDCAA' 'prompt:#DCDCAA' 'info:#B5CEA8'
        'pointer:#CCCCCC' 'border:#CCCCCC' 'gutter:#1F1F1F'
        'preview-fg:-1' 'preview-bg:-1'
    )
    bu_list_join , "${fzf_colors[@]}"
    fzf_opts+=(--color=dark,"$BU_RET")

    if "$use_tab_to_confirm"; then
        fzf_opts+=(--bind "tab:accept")
    fi

    # Format metadata alongside completions (same as non-TS path)
    local delimiter=$'\x01'
    if "$BU_AUTOCOMPLETE_BIND_FZF_DISPLAY_METADATA" && (("${#BU_COMPREPLY_METADATA[@]}")) && ((${#COMPREPLY[@]} < 2000)); then
        local _md_i _md_pad _md_min_pad=1
        # Save colored copy before __ANSI__ escape (used for inline display)
        local -a bu_compreply_metadata_colored=("${BU_COMPREPLY_METADATA[@]}")
        # https://github.com/junegunn/fzf/issues/4626
        BU_COMPREPLY_METADATA=("${BU_COMPREPLY_METADATA[@]//$'\E'/'__ANSI__'}")
        if ! "$is_ansi"; then
            local _md_trim
            for _md_i in "${!bu_compreply_metadata_no_ansi[@]}"; do
                _md_trim=$((box_length - ${#COMPREPLY[_md_i]}))
                ((_md_trim < 0)) && _md_trim=0
                bu_compreply_metadata_no_ansi[_md_i]=${bu_compreply_metadata_no_ansi[_md_i]:0:$_md_trim}
                _md_pad=$((box_length - ${#COMPREPLY[_md_i]} - ${#bu_compreply_metadata_no_ansi[_md_i]}))
                COMPREPLY[_md_i]=${COMPREPLY[_md_i]}${delimiter}${__BU_PADDING_TABLE[_md_pad > _md_min_pad ? _md_pad : _md_min_pad]}${bu_compreply_metadata_colored[_md_i]}${delimiter}${BU_COMPREPLY_METADATA[_md_i]}
            done
        else
            local -a _md_stripped
            mapfile -t _md_stripped < <(sed -r -e 's/\x1B\(B\x1B\[m//g' -e "s/\x1B\[([0-9]{1,3}(;[0-9]{1,3})*)?[mGK]//g" < <(printf "%s\n" "${COMPREPLY[@]}"))
            local _md_trim
            for _md_i in "${!bu_compreply_metadata_no_ansi[@]}"; do
                _md_trim=$((box_length - ${#_md_stripped[_md_i]}))
                ((_md_trim < 0)) && _md_trim=0
                bu_compreply_metadata_no_ansi[_md_i]=${bu_compreply_metadata_no_ansi[_md_i]:0:$_md_trim}
                _md_pad=$((box_length - ${#_md_stripped[_md_i]} - ${#bu_compreply_metadata_no_ansi[_md_i]}))
                COMPREPLY[_md_i]=${COMPREPLY[_md_i]}${delimiter}${__BU_PADDING_TABLE[_md_pad > _md_min_pad ? _md_pad : _md_min_pad]}${bu_compreply_metadata_colored[_md_i]}${delimiter}${BU_COMPREPLY_METADATA[_md_i]}
            done
        fi

        fzf_opts+=(
            --delimiter "$delimiter"
            --nth 1
            --with-nth 1,2
        )

        if "$show_preview"; then
            fzf_opts+=(
                --preview="__bu_bind_fzf_autocomplete_impl_display {3}"
                --preview-window=:$preview_window_size:wrap
            )
        fi

        is_ansi=true
    fi

    if "$is_ansi"; then
        fzf_opts+=(--ansi)
    fi

    local selected_command
    if selected_command=$(
        printf "%s
" "${COMPREPLY[@]}" | sort --unique | fzf "${fzf_opts[@]}"
    ) && [[ -n "$selected_command" ]]; then
        # Strip ANSI color codes from the selection
        # Strip ANSI color codes from the selection (literal ESC via $'\x1b')
        selected_command=$(sed -r $'s/\x1b\\[[0-9;]*[mGK]//g' <<<"$selected_command")
        selected_command=$(sed -r $'s/\x1b\\(B//g' <<<"$selected_command")
        # Strip metadata delimiter from fzf selection (if metadata was shown)
        if "$BU_AUTOCOMPLETE_BIND_FZF_DISPLAY_METADATA" && (("${#BU_COMPREPLY_METADATA[@]}")); then
            selected_command=${selected_command%%"${delimiter}"*}
        fi
        local readline_line
        local readline_point

        if "$is_range_replace"; then
            # --- Range-based replacement (LSP TextEdit) ---
            # Splice: keep text before replaceStart, insert selection, keep after replaceEnd
            readline_line="${original:0:replace_start}${selected_command}${original:replace_end}"
            readline_point=${#readline_line}
        else
            # --- Whole-word replacement (traditional) ---
            command_line[-1]="${quote_prefix}${selected_command}"
            readline_line=${command_line[*]}
            # Remove the last word of command_line_back
            local back_no_op=${command_line_back%%[[:space:]]*}
            back_no_op=${back_no_op%%)*}
            back_no_op=${back_no_op%%;*}
            back_no_op=${back_no_op%%&&*}
            back_no_op=${back_no_op%%|*}
            command_line_back=${command_line_back:${#back_no_op}}
            command_line_back=${command_line_back# }
            if ! "$is_dynamic_nospace" && \
               ! { "$is_filenames" && [[ "${readline_line:${#readline_line}-1}" = / ]]; } && \
               ! { "$is_nospace" && [[ "${readline_line:${#readline_line}-1}" = [/=:@] ]]; } && \
               [[ "${readline_line:${#readline_line}-1}" != ' ' && "${command_line_back:0:1}" != ' ' ]]; then
                readline_line+=' '
            fi
            readline_line=${pipe_before}${readline_line}
            readline_point=${#readline_line}
        fi

        # Append text that was after the cursor
        readline_line+=$command_line_back

        if "$move_cursor_to_end"; then
            readline_point=${#readline_line}
        fi

        READLINE_LINE=$readline_line
        READLINE_POINT=$readline_point
    fi

    __bu_terminal_get_pos2 "$oldstty"
    local row_after_fzf=${BU_RET[0]}
    if ((row_before_fzf == row_after_fzf)); then
        tput rc
    elif ((row_start < row_before_fzf)); then
        tput cuu "$((row_before_fzf - row_start))"
    fi
}

# Fallback: original implementation for when tree-sitter is unavailable
__bu_bind_fzf_autocomplete_impl_legacy()
{
    # This is just a trampoline back to the real function with tree-sitter disabled.
    # We temporarily flip the toggle so the recursive call uses the old path.
    local _saved=$BU_AUTOCOMPLETE_USE_TREE_SITTER
    BU_AUTOCOMPLETE_USE_TREE_SITTER=false
    __bu_bind_fzf_autocomplete_impl "$@"
    BU_AUTOCOMPLETE_USE_TREE_SITTER=$_saved
}

# ```
# *Description*:
# Binds fzf to the history of bu command invocations for easy searching.
# This is a readline binding function.
#
# *Params*: None
#
# *Returns*: None
# ```
__bu_bind_fzf_history()
{
    touch "$BU_HISTORY"
    local history_result
    if history_result=$(cat "$BU_HISTORY" | fzf --tac --exact +s --sync --header 'bu history')
    then
        READLINE_LINE=$history_result
        READLINE_POINT=${#READLINE_LINE}
    fi
}

bu_autocomplete()
{
    BU_RET=("${autocompletion[@]}")
    case "$1" in
    --no-pop)
        ;;
    --no-pop-fn)
        bu_scope_pop
        ;;
    '')
        bu_scope_pop_function
        ;;
    *)
        bu_log_unrecognized_option "$1"
        ;;
    esac
}

# Requires
# options_finished: Bool
# remaining_options: Array
bu_autocomplete_remaining()
{
    local arg1=
    case "$1" in
    --no-pop|--no-pop-fn)
        arg1=$1
        ;;
    esac

    # shellcheck disable=SC2154
    if "$options_finished" && ((${#remaining_options[@]}))
    then
        autocompletion=("$@")
    fi
    bu_autocomplete "$arg1"
}

# Read with a fixed set of autocompletions
bu_read_word()
{
    BU_RET=
    local reply_name=BU_RET
    local read_args=()
    while (($#))
    do
        case "$1" in
        --prompt) read_args+=(-p "$2 "); shift 2;;
        --reply) reply_name=$2; shift 2;;
        --) shift; break ; ;;
        *) break ;;
        esac
    done
    if (($# <= 100))
    then
        bu_mkdir "$BU_PROC_TMP_DIR"/read
        rm -f "$BU_PROC_TMP_DIR"/read/*
        pushd "$BU_PROC_TMP_DIR"/read &>/dev/null
        touch "$@"
    else
        bu_log_warn "At most 100 autocompletions supported, no autocompletions will be generated"
    fi
    read_args+=("$reply_name")
    read -e -r "${read_args[@]}"

    if (($# <= 100))
    then
        rm -f "$BU_PROC_TMP_DIR"/read/*
        popd &>/dev/null
    fi
}

# This works on Bash 5.2.21 but does not on 4.4
# i.e. even after being disabled, it still shows up
# bind -X | grep -q __bu_bind_fzf_tab_autocomplete
# Hence, to work on older Bash versions, we use a book-keeping variable.
BU_AUTOCOMPLETE_IS_CUSTOM_TAB=false
bu_autocomplete_enable_tab()
{
    bind -x '"\t": "__bu_bind_fzf_tab_autocomplete"'
    BU_AUTOCOMPLETE_IS_CUSTOM_TAB=true
    bu_log_info "fzf TAB enabled"
}

bu_autocomplete_disable_tab()
{
    # This works on bash 5.2.21 but doesn't on Bash 4.4
    # bind -r "\t"
    bind '"\t": complete'
    BU_AUTOCOMPLETE_IS_CUSTOM_TAB=false
    bu_log_info "fzf TAB disabled"
}

bu_autocomplete_toggle_tab()
{
    if "$BU_AUTOCOMPLETE_IS_CUSTOM_TAB"
    then
        bu_autocomplete_disable_tab
    else
        bu_autocomplete_enable_tab
    fi
}

# These autocompletion specs come in useful pretty often

BU_AUTOCOMPLETE_SPEC_DIRECTORY=(
    --sh compopt -o filenames sh--
    --sh compopt -o nospace sh--
    --stdout compgen -d stdout--
)

BU_AUTOCOMPLETE_SPEC_FILE=(
    --sh compopt -o filenames sh--
    --sh compopt -o nospace sh--
    --stdout compgen -f stdout--
)
