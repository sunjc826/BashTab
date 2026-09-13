#!/usr/bin/env bash
# Pipeline: query
# Dispatch: source
# Synopsis: Apply SQL-style clauses (where, group-by, select, order-by) to a JSONL stream
# ```
# *Description*:
# Tokenize a comma-separated list that may span multiple words with flexible
# comma placement ("a,b", "a, b", "a ,b", "a , b"). The list words begin at
# _cl_start in the caller-provided words array. A word continues the list when
# it is the first list word, when the previous word ended in a comma, or when
# it starts with a comma. During autocomplete the final word is the in-progress
# cursor word: it is excluded from the finalized spec and analyzed separately.
#
# *Params*:
# - $1: nameref to the words array
# - $2: index of the first list word
# - $3: nameref to a stop-words array (exact matches terminate the list;
#       pass an empty array for no stop words)
# - $4: nameref to the output raw spec (concatenated finalized words)
# - $5: nameref to the output consumed count (finalized list words)
# - $6: nameref to the output used-set (associative array)
# - $7: nameref to the output continues flag (true/false)
# ```
__bu_query_object_parse_comma_list()
{
    local -n _cl_words=$1
    local -r _cl_start=$2
    local -n _cl_stop=$3
    local -n _cl_spec=$4
    local -n _cl_consumed=$5
    local -n _cl_used=$6
    local -n _cl_continues=$7

    _cl_spec=
    _cl_consumed=0
    _cl_used=()
    _cl_continues=false

    local -r _cl_count=${#_cl_words[@]}
    local _cl_last=$_cl_count
    bu_env_is_in_autocomplete && _cl_last=$(( _cl_count - 1 ))

    local _cl_pending=false
    local _cl_idx _cl_word _cl_stop_word _cl_is_stop
    for (( _cl_idx = _cl_start; _cl_idx < _cl_last; _cl_idx++ )); do
        _cl_word=${_cl_words[_cl_idx]}
        _cl_is_stop=false
        if (( _cl_idx != _cl_start )); then
            # A flag (other than a negative number) or an exact stop-word
            # always terminates the list, even after a trailing comma.
            if [[ "$_cl_word" == -* && ! "$_cl_word" =~ ^-[0-9] ]]; then
                _cl_is_stop=true
            else
                for _cl_stop_word in "${_cl_stop[@]}"; do
                    if [[ "$_cl_word" == "$_cl_stop_word" ]]; then
                        _cl_is_stop=true
                        break
                    fi
                done
            fi
        fi
        "$_cl_is_stop" && break
        if (( _cl_idx != _cl_start )) && ! "$_cl_pending" && [[ "$_cl_word" != ,* ]]; then
            break
        fi
        [[ -n "$_cl_word" ]] && _cl_spec+="$_cl_word"
        _cl_consumed=$(( _cl_idx - _cl_start + 1 ))
        case "$_cl_word" in
        *,) _cl_pending=true ;;
        *)   _cl_pending=false ;;
        esac
    done

    local _cl_used_item _cl_ifs=$IFS
    IFS=','
    for _cl_used_item in $_cl_spec; do
        [[ -n "$_cl_used_item" ]] && _cl_used[$_cl_used_item]=1
    done
    IFS=$_cl_ifs

    if bu_env_is_in_autocomplete; then
        local _cl_cur=${_cl_words[-1]}
        local _cl_reaches=false
        if (( _cl_consumed == _cl_last - _cl_start )); then
            _cl_reaches=true
        fi
        if "$_cl_reaches" && ( (( _cl_consumed == 0 )) || "$_cl_pending" || [[ "$_cl_cur" == ,* ]] ); then
            _cl_continues=true
        fi
        # Fold the cursor word's own comma-prefix tokens into the used set
        # (e.g. cursor "a,ve" already used field "a").
        local _cl_active=${_cl_cur##*,}
        local _cl_prefix=${_cl_cur%"$_cl_active"}
        IFS=','
        for _cl_used_item in $_cl_prefix; do
            [[ -n "$_cl_used_item" ]] && _cl_used[$_cl_used_item]=1
        done
        IFS=$_cl_ifs
    fi
}

function __bu_bu_query_object_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local select_fields=
local is_select_expand=false
local from_file=
local out_file=
local -a where_exprs=()
local -a grep_exprs=()
local group_keys=
local -a agg_specs=()
local -a having_exprs=()
local order_by=
local is_desc=false
local is_distinct=false
local first=
local format=auto
local columns=
local is_debug=false
local is_explain=false
local query_plan=
local executor=${BU_QUERY_EXECUTOR:-pipeline}
local execution_status=0
local cleanup_status=0
local combined_program=
local query_runner=__bu_query_object_pipeline
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --select|select)# SELECT
        # Fields to keep, in order (comma-separated; new=old renames).
        # The field spec may span multiple words with flexible comma
        # placement: "a,b,c", "a, b, c", "a , b , c", "a ,b ,c".
        local -a _s_words=("$@")
        local -A _s_used=()
        local _s_spec= _s_consumed=0 _s_continues=false
        __bu_query_object_parse_comma_list _s_words 1 __bu_out_query_object_clause_keywords _s_spec _s_consumed _s_used _s_continues

        local _s_shift_by=$(( 1 + _s_consumed ))
        if bu_env_is_in_autocomplete && (( $# >= 2 )) && "$_s_continues"; then
            local _s_cur=${_s_words[-1]}
            local _s_active=${_s_cur##*,}
            local _s_prefix=${_s_cur%"$_s_active"}
            local -a _s_candidates=()
            local _s_cand=
            if __bu_out_complete_pipeline_fields "$_s_active"; then
                for _s_cand in "${BU_RET[@]}"; do
                    [[ -n "${_s_used[$_s_cand]:-}" ]] && continue
                    _s_candidates+=("${_s_prefix}${_s_cand}")
                done
            fi
            if ((${#_s_candidates[@]} > 0)); then
                autocompletion=(--enum "${_s_candidates[@]}" enum-- --hint "Fields, new=old renames")
            else
                autocompletion=(--hint "Fields, new=old renames")
            fi
            _s_shift_by=$(( _s_shift_by + 1 ))
        fi

        shift_by=$_s_shift_by
        select_fields=$_s_spec
        ;;
    --expand|expand)# _FLAG
        # Lift a single nested object field to top level (applies to select clause)
        is_select_expand=true
        ;;
    --from|from)# FROM
        # Query a particular file (JSONL, CSV, TSV, or JSON). Defaults to /dev/stdin
        bu_parse_positional $# "${BU_AUTOCOMPLETE_SPEC_FILE[@]}" --hint "Input file (JSONL/CSV/TSV/JSON). Defaults to stdin"
        from_file=${!shift_by}
        ;;
    --where|where)# WHERE
        # Filter records. Two syntaxes:
        #   jq expression:  where '.type == "source"'
        #   Structured:     where type -eq "source"
        #     Operators: -eq -ne -gt -lt -ge -le -like -notlike -match
        #                -notmatch -contains -notcontains -in -notin
        #                -isnull -isnotnull
        #     Connect conditions with 'and' or 'or' inside one where:
        #       where type -eq source and name -like get-*
        # Repeatable; multiple where clauses are ANDed together.
        # Save shift_by BEFORE bu_parse_positional to detect early return.
        local _w_saved_shift_by=$shift_by
        bu_parse_positional $# --hint "Field name, or jq expression" --pipeline-fields pipeline-fields--
        local where_raw=${!shift_by}
        if [[ "$where_raw" == .* || "$where_raw" == \(* || "$where_raw" == select\(* ]]; then
            where_exprs+=("$where_raw")
        elif (( shift_by == _w_saved_shift_by )); then
            # bu_parse_positional returned early — no positional arg to
            # consume.  where_raw is bogus (resolved to the flag itself).
            # Force field-name completions.
            autocompletion=(--hint "Field name" --pipeline-fields pipeline-fields--)
            :
        else
            # Structured comparison with optional and/or chaining.
            # Grammar: field -op [val] { and|or field -op [val] }*
            local -a _w_segments=()   # jq expressions for each condition
            local -a _w_connectors=() # "and" or "or" between segments
            local _w_extra=0          # extra args consumed (beyond field name)
            local _w_field=$where_raw
            local _w_complete=false   # last condition is fully parsed
            local _w_value_is_last=false # parsed value token is the cursor word
            local -A _w_in_used=()
            local _w_in_active=
            local _w_in_prefix=

            while true; do
                # --- Parse operator for current field ---
                local _w_op= _w_val= _w_cond_consume=0
                local _w_o_idx=$(( shift_by + _w_extra + 1 ))
                if (( _w_o_idx <= $# )); then
                    local _w_o_arg=${!_w_o_idx}
                    case "$_w_o_arg" in
                    -eq|-ne|-gt|-lt|-ge|-le|-like|-notlike|-match|-notmatch|-contains|-notcontains)
                        _w_op=$_w_o_arg; _w_cond_consume=1
                        local _w_v_idx=$(( shift_by + _w_extra + 2 ))
                        if (( _w_v_idx <= $# )); then
                            local _w_v_arg=${!_w_v_idx}
                            if [[ "$_w_v_arg" != -* ]] || [[ "$_w_v_arg" =~ ^-[0-9] ]]; then
                                _w_val=$_w_v_arg; _w_cond_consume=2
                                (( _w_v_idx == $# )) && _w_value_is_last=true
                            fi
                        fi
                        ;;
                    -in|-notin)
                        _w_op=$_w_o_arg; _w_cond_consume=1
                        local _w_v_idx=$(( shift_by + _w_extra + 2 ))
                        if (( _w_v_idx <= $# )); then
                            local -a _w_in_words=()
                            local _w_ii
                            for (( _w_ii = _w_v_idx; _w_ii <= $#; _w_ii++ )); do
                                _w_in_words+=("${!_w_ii}")
                            done
                            local -a _w_in_stop=(and or "${__bu_out_query_object_clause_keywords[@]}")
                            local _w_in_spec= _w_in_consumed=0 _w_in_continues=false
                            __bu_query_object_parse_comma_list _w_in_words 0 _w_in_stop _w_in_spec _w_in_consumed _w_in_used _w_in_continues
                            _w_val=$_w_in_spec
                            _w_value_is_last=$_w_in_continues
                            _w_cond_consume=$(( 1 + _w_in_consumed ))
                            "$_w_in_continues" && _w_cond_consume=$(( _w_cond_consume + 1 ))
                            _w_in_active=${_w_in_words[-1]##*,}
                            _w_in_prefix=${_w_in_words[-1]%"$_w_in_active"}
                        fi
                        ;;
                    -isnull|-isnotnull)
                        _w_op=$_w_o_arg; _w_cond_consume=1
                        ;;
                    -*)
                        # Partial / unknown operator — don't consume.
                        # Let the autocomplete section show operators, and
                        # the tail cleanup below will eat this arg.
                        :
                        ;;
                    esac
                fi
                _w_extra=$((_w_extra + _w_cond_consume))

                if [[ -n "$_w_op" ]]; then
                    # Have a condition (possibly with value missing)
                    if [[ "$_w_op" != -isnull && "$_w_op" != -isnotnull && -z "$_w_val" ]]; then
                        if ! bu_env_is_in_autocomplete; then
                            error_msg="Missing value after operator[$_w_op] for field[$_w_field]"
                            bu_autohelp; bu_scope_pop_function; return 1
                        fi
                        _w_complete=false
                        break
                    fi
                    local _w_seg_jq
                    _w_seg_jq=$(__bu_query_object_translate_op "$_w_field" "$_w_op" "$_w_val") || {
                        error_msg="Invalid where clause: $_w_field $_w_op $_w_val"
                        bu_autohelp; bu_scope_pop_function; return 1
                    }
                    _w_segments+=("$_w_seg_jq")
                    _w_complete=true
                else
                    _w_complete=false
                    break
                fi

                # --- Check for and/or connector ---
                local _w_c_idx=$(( shift_by + _w_extra + 1 ))
                if (( _w_c_idx > $# )); then break; fi
                local _w_c_arg=${!_w_c_idx}
                case "$_w_c_arg" in
                and|or)
                    _w_connectors+=("$_w_c_arg")
                    _w_extra=$((_w_extra + 1))
                    ;;
                *)
                    break  # next arg is not a connector
                    ;;
                esac

                # --- Parse next field name ---
                local _w_f_idx=$(( shift_by + _w_extra + 1 ))
                if (( _w_f_idx > $# )); then
                    _w_complete=false  # waiting for field after connector
                    break
                fi
                _w_field=${!_w_f_idx}
                if [[ "$_w_field" == -* ]]; then
                    # Backtrack: connector had no field after it.
                    # This is an error in non-autocomplete mode.
                    if ! bu_env_is_in_autocomplete; then
                        error_msg="Expected field name after '${_w_connectors[-1]}', got flag[$_w_field]"
                        bu_autohelp; bu_scope_pop_function; return 1
                    fi
                    _w_extra=$((_w_extra - 1))       # un-consume connector
                    unset '_w_connectors[-1]'         # remove last connector
                    _w_complete=true
                    break
                fi
                _w_extra=$((_w_extra + 1))
                _w_complete=false  # need to parse operator for new field
            done

            : $((shift_by += _w_extra))

            # Remember whether cursor is past the field (before tail
            # cleanup consumes the operator-position empty arg).
            local _w_cursor_past_field=false
            (( $# > shift_by )) && _w_cursor_past_field=true

            # Consume any trailing empty or partial-operator arg that
            # belongs to the where clause (avoids a bogus second loop
            # iteration that would overwrite autocompletion with flags).
            if (( shift_by < $# )); then
                local _w_tail_idx=$(( shift_by + 1 ))
                local _w_tail=${!_w_tail_idx}
                if [[ -z "$_w_tail" || ( "$_w_tail" == -* && "$_w_tail" != --* ) ]]; then
                    : $((shift_by++))
                elif bu_env_is_in_autocomplete && [[ "$_w_complete" == true ]] && (( _w_tail_idx == $# )); then
                    # A non-empty prefix of a connector at the cursor is a
                    # connector-in-progress, not a new clause keyword; consume
                    # it so the and/or enum survives to bu_autocomplete.
                    case "$_w_tail" in
                    a|an|and|o|or)
                        : $((shift_by++))
                        ;;
                    esac
                fi
            fi

            # --- Set autocomplete for the current position ---
            if [[ -z "$_w_op" && -n "$_w_field" ]] && "$_w_cursor_past_field"; then
                # Have a field name AND cursor past it → show operators
                autocompletion=(--enum -eq -ne -gt -lt -ge -le -like -notlike -match -notmatch -contains -notcontains -in -notin -isnull -isnotnull enum-- --hint "Comparison operator")
            elif [[ -z "$_w_op" && -z "$_w_field" ]] && ((${#_w_connectors[@]} > 0)); then
                # After and/or connector, waiting for next field name
                autocompletion=(--hint "Field name (after ${_w_connectors[-1]})" --pipeline-fields pipeline-fields--)
            elif [[ -n "$_w_op" && "$_w_op" != -isnull && "$_w_op" != -isnotnull && ( -z "$_w_val" || "$_w_value_is_last" == true ) ]]; then
                # Have field + operator. Fire when the value is still missing OR
                # when the cursor is on the value word itself (a partial value
                # being completed). In both cases complete the value, never the
                # and/or connector.
                case "$_w_op" in
                -eq|-ne)
                    if __bu_out_complete_field_values "$_w_field" && ((${#BU_RET[@]} > 0)); then
                        autocompletion=(--enum "${BU_RET[@]}" enum-- --hint "Values of $_w_field")
                    else
                        autocompletion=(--hint "Value for $_w_field $_w_op")
                    fi
                    ;;
                -in|-notin)
                    local -a _w_in_candidates=()
                    local _w_in_cand=
                    if __bu_out_complete_field_values "$_w_field" && ((${#BU_RET[@]} > 0)); then
                        for _w_in_cand in "${BU_RET[@]}"; do
                            [[ -n "${_w_in_used[$_w_in_cand]:-}" ]] && continue
                            [[ "$_w_in_cand" == "$_w_in_active"* ]] || continue
                            _w_in_candidates+=("${_w_in_prefix}${_w_in_cand}")
                        done
                    fi
                    if ((${#_w_in_candidates[@]} > 0)); then
                        autocompletion=(--enum "${_w_in_candidates[@]}" enum-- --hint "Values of $_w_field")
                    else
                        autocompletion=(--hint "Value for $_w_field $_w_op")
                    fi
                    ;;
                *)
                    autocompletion=(--hint "Value for $_w_field $_w_op")
                    ;;
                esac
            elif [[ "$_w_complete" == true ]]; then
                # Have a complete condition with the cursor past the value;
                # suggest the and/or connector.
                autocompletion=(--enum and or enum-- --hint "Logical connector (and/or)")
            fi
            if [[ -z "$_w_op" && -z "$_w_field" ]] && ((${#_w_connectors[@]} == 0)); then
                # Waiting for first field name — force field completions
                autocompletion=(--hint "Field name" --pipeline-fields pipeline-fields--)
            fi

            # --- Build combined jq expression ---
            if ((${#_w_segments[@]} > 0)); then
                local _w_combined="${_w_segments[0]}"
                local _w_i
                for (( _w_i = 1; _w_i < ${#_w_segments[@]}; _w_i++ )); do
                    _w_combined="($_w_combined) ${_w_connectors[_w_i-1]} (${_w_segments[_w_i]})"
                done
                where_exprs+=("$_w_combined")
            fi
        fi
        ;;
    --grep|grep)# GREP
        # Search a pattern across any field value of each record (a grep of
        # the row). Default is regex; -like/-ilike switch to glob (bare
        # pattern = substring); -i/-ilike make matching case-insensitive.
        local grep_mode=regex
        local grep_modifier=
        if (($# >= 2)); then
            case "$2" in
            -like)  grep_mode=glob;   grep_modifier=$2 ;;
            -ilike) grep_mode=iglob;  grep_modifier=$2 ;;
            -i)     grep_mode=iregex; grep_modifier=$2 ;;
            esac
        fi
        if [[ -n "$grep_modifier" ]]; then
            : $((shift_by++))
        fi
        local grep_hint=
        case "$grep_mode" in
        glob)   grep_hint="Glob pattern (matches any field value)" ;;
        iglob)  grep_hint="Glob pattern, case-insensitive (matches any field value)" ;;
        iregex) grep_hint="Regex pattern, case-insensitive (matches any field value)" ;;
        *)      grep_hint="Regex pattern (matches any field value)" ;;
        esac
        bu_parse_positional $# --hint "$grep_hint"
        local grep_pattern=${!shift_by}

        # When the token right after grep is a flag prefix but not a full
        # modifier, offer the mode flags instead of a pattern hint.
        if [[ -z "$grep_modifier" && "${2:-}" == -* && "${2:-}" != -- ]]; then
            autocompletion=(--enum -like -ilike -i enum-- --hint "Match mode")
        fi

        if ! bu_env_is_in_autocomplete && [[ -n "$grep_pattern" ]]; then
            local grep_jq
            grep_jq=$(__bu_query_object_translate_grep "$grep_mode" "$grep_pattern") || {
                error_msg="Invalid grep pattern[$grep_pattern]"
                bu_autohelp; bu_scope_pop_function; return 1
            }
            grep_exprs+=("$grep_jq")
        fi
        ;;
    --group-by|group-by)# GROUP_BY
        # Group records by key fields (comma-separated), collapsing each group
        # into one record. Use agg to add aggregates; no agg emits distinct keys.
        local -a _g_words=("$@")
        local -A _g_used=()
        local _g_spec= _g_consumed=0 _g_continues=false
        __bu_query_object_parse_comma_list _g_words 1 __bu_out_query_object_clause_keywords _g_spec _g_consumed _g_used _g_continues

        local _g_shift_by=$(( 1 + _g_consumed ))
        if bu_env_is_in_autocomplete && (( $# >= 2 )) && "$_g_continues"; then
            local _g_cur=${_g_words[-1]}
            local _g_active=${_g_cur##*,}
            local _g_prefix=${_g_cur%"$_g_active"}
            local -a _g_candidates=()
            local _g_cand=
            if __bu_out_complete_pipeline_fields "$_g_active"; then
                for _g_cand in "${BU_RET[@]}"; do
                    [[ -n "${_g_used[$_g_cand]:-}" ]] && continue
                    _g_candidates+=("${_g_prefix}${_g_cand}")
                done
            fi
            if ((${#_g_candidates[@]} > 0)); then
                autocompletion=(--enum "${_g_candidates[@]}" enum-- --hint "Group key fields")
            else
                autocompletion=(--hint "Group key fields")
            fi
            _g_shift_by=$(( _g_shift_by + 1 ))
        fi

        shift_by=$_g_shift_by
        group_keys=$_g_spec
        ;;
    --agg|agg)# AGG
        # Aggregates for group-by: [name=]func[:field], comma-separated and/or
        # repeatable. funcs: count, sum, avg, min, max, first, last, collect
        local -a _a_words=("$@")
        local -A _a_used=()
        local _a_spec= _a_consumed=0 _a_continues=false
        __bu_query_object_parse_comma_list _a_words 1 __bu_out_query_object_clause_keywords _a_spec _a_consumed _a_used _a_continues

        local _a_shift_by=$(( 1 + _a_consumed ))
        if bu_env_is_in_autocomplete && (( $# >= 2 )) && "$_a_continues"; then
            local _a_cur=${_a_words[-1]}
            local _a_active=${_a_cur##*,}
            local _a_prefix=${_a_cur%"$_a_active"}
            local -a _a_funcs=(count sum avg min max first last collect)
            local -a _a_candidates=()
            local _a_func=
            for _a_func in "${_a_funcs[@]}"; do
                [[ "$_a_func" == "$_a_active"* ]] || continue
                _a_candidates+=("${_a_prefix}${_a_func}")
            done
            if ((${#_a_candidates[@]} > 0)); then
                autocompletion=(--enum "${_a_candidates[@]}" enum-- --hint "Aggregates: [name=]func[:field]")
            else
                autocompletion=(--hint "Aggregates: [name=]func[:field]")
            fi
            _a_shift_by=$(( _a_shift_by + 1 ))
        fi

        shift_by=$_a_shift_by
        # Split the (possibly multi-word) spec into repeatable agg specs.
        local agg_spec
        local ifs=$IFS
        IFS=','
        # shellcheck disable=SC2206 # Intentional word splitting on commas
        for agg_spec in $_a_spec; do [[ -n "$agg_spec" ]] && agg_specs+=("$agg_spec"); done
        IFS=$ifs
        ;;
    --having|having)# HAVING
        # Filter groups after group-by. Accepts raw jq or structured comparison
        # (same operator syntax and and/or chaining as --where).
        # Repeatable; multiple expressions are ANDed together.
        local _h_saved_shift_by=$shift_by
        bu_parse_positional $# --hint "Field name, or jq expression (group fields)" --pipeline-fields pipeline-fields--
        local having_raw=${!shift_by}
        if [[ "$having_raw" == .* || "$having_raw" == \(* || "$having_raw" == select\(* ]]; then
            having_exprs+=("$having_raw")
        elif (( shift_by == _h_saved_shift_by )); then
            # bu_parse_positional returned early — no positional arg.
            autocompletion=(--hint "Field name" --pipeline-fields pipeline-fields--)
            :
            :
        else
            local -a _h_segments=()
            local -a _h_connectors=()
            local _h_extra=0
            local _h_field=$having_raw
            local _h_complete=false
            local _h_value_is_last=false # parsed value token is the cursor word
            local -A _h_in_used=()
            local _h_in_active=
            local _h_in_prefix=

            while true; do
                local _h_op= _h_val= _h_cond_consume=0
                local _h_o_idx=$(( shift_by + _h_extra + 1 ))
                if (( _h_o_idx <= $# )); then
                    local _h_o_arg=${!_h_o_idx}
                    case "$_h_o_arg" in
                    -eq|-ne|-gt|-lt|-ge|-le|-like|-notlike|-match|-notmatch|-contains|-notcontains)
                        _h_op=$_h_o_arg; _h_cond_consume=1
                        local _h_v_idx=$(( shift_by + _h_extra + 2 ))
                        if (( _h_v_idx <= $# )); then
                            local _h_v_arg=${!_h_v_idx}
                            if [[ "$_h_v_arg" != -* ]] || [[ "$_h_v_arg" =~ ^-[0-9] ]]; then
                                _h_val=$_h_v_arg; _h_cond_consume=2
                                (( _h_v_idx == $# )) && _h_value_is_last=true
                            fi
                        fi
                        ;;
                    -in|-notin)
                        _h_op=$_h_o_arg; _h_cond_consume=1
                        local _h_v_idx=$(( shift_by + _h_extra + 2 ))
                        if (( _h_v_idx <= $# )); then
                            local -a _h_in_words=()
                            local _h_ii
                            for (( _h_ii = _h_v_idx; _h_ii <= $#; _h_ii++ )); do
                                _h_in_words+=("${!_h_ii}")
                            done
                            local -a _h_in_stop=(and or "${__bu_out_query_object_clause_keywords[@]}")
                            local _h_in_spec= _h_in_consumed=0 _h_in_continues=false
                            __bu_query_object_parse_comma_list _h_in_words 0 _h_in_stop _h_in_spec _h_in_consumed _h_in_used _h_in_continues
                            _h_val=$_h_in_spec
                            _h_value_is_last=$_h_in_continues
                            _h_cond_consume=$(( 1 + _h_in_consumed ))
                            "$_h_in_continues" && _h_cond_consume=$(( _h_cond_consume + 1 ))
                            _h_in_active=${_h_in_words[-1]##*,}
                            _h_in_prefix=${_h_in_words[-1]%"$_h_in_active"}
                        fi
                        ;;
                    -isnull|-isnotnull)
                        _h_op=$_h_o_arg; _h_cond_consume=1
                        ;;
                    -*)
                        # Partial / unknown operator — don't consume.
                        :
                        ;;
                    esac
                fi
                _h_extra=$((_h_extra + _h_cond_consume))

                if [[ -n "$_h_op" ]]; then
                    if [[ "$_h_op" != -isnull && "$_h_op" != -isnotnull && -z "$_h_val" ]]; then
                        if ! bu_env_is_in_autocomplete; then
                            error_msg="Missing value after operator[$_h_op] for field[$_h_field]"
                            bu_autohelp; bu_scope_pop_function; return 1
                        fi
                        _h_complete=false; break
                    fi
                    local _h_seg_jq
                    _h_seg_jq=$(__bu_query_object_translate_op "$_h_field" "$_h_op" "$_h_val") || {
                        error_msg="Invalid having clause: $_h_field $_h_op $_h_val"
                        bu_autohelp; bu_scope_pop_function; return 1
                    }
                    _h_segments+=("$_h_seg_jq")
                    _h_complete=true
                else
                    _h_complete=false; break
                fi

                # Check for and/or connector
                local _h_c_idx=$(( shift_by + _h_extra + 1 ))
                if (( _h_c_idx > $# )); then break; fi
                local _h_c_arg=${!_h_c_idx}
                case "$_h_c_arg" in
                and|or)
                    _h_connectors+=("$_h_c_arg")
                    _h_extra=$((_h_extra + 1))
                    ;;
                *)
                    break
                    ;;
                esac

                # Parse next field name
                local _h_f_idx=$(( shift_by + _h_extra + 1 ))
                if (( _h_f_idx > $# )); then
                    _h_complete=false; break
                fi
                _h_field=${!_h_f_idx}
                if [[ "$_h_field" == -* ]]; then
                    if ! bu_env_is_in_autocomplete; then
                        error_msg="Expected field name after '${_h_connectors[-1]}', got flag[$_h_field]"
                        bu_autohelp; bu_scope_pop_function; return 1
                    fi
                    _h_extra=$((_h_extra - 1))
                    unset '_h_connectors[-1]'
                    _h_complete=true; break
                fi
                _h_extra=$((_h_extra + 1))
                _h_complete=false
            done

            : $((shift_by += _h_extra))

            local _h_cursor_past_field=false
            (( $# > shift_by )) && _h_cursor_past_field=true

            # Consume trailing empty/operator-like arg (same as --where)
            if (( shift_by < $# )); then
                local _h_tail_idx=$(( shift_by + 1 ))
                local _h_tail=${!_h_tail_idx}
                if [[ -z "$_h_tail" || ( "$_h_tail" == -* && "$_h_tail" != --* ) ]]; then
                    : $((shift_by++))
                elif bu_env_is_in_autocomplete && [[ "$_h_complete" == true ]] && (( _h_tail_idx == $# )); then
                    case "$_h_tail" in
                    a|an|and|o|or)
                        : $((shift_by++))
                        ;;
                    esac
                fi
            fi

            if [[ -z "$_h_op" && -n "$_h_field" ]] && "$_h_cursor_past_field"; then
                autocompletion=(--enum -eq -ne -gt -lt -ge -le -like -notlike -match -notmatch -contains -notcontains -in -notin -isnull -isnotnull enum-- --hint "Comparison operator")
            elif [[ -z "$_h_op" && -z "$_h_field" ]] && ((${#_h_connectors[@]} > 0)); then
                autocompletion=(--hint "Field name (after ${_h_connectors[-1]})" --pipeline-fields pipeline-fields--)
            elif [[ -n "$_h_op" && "$_h_op" != -isnull && "$_h_op" != -isnotnull && ( -z "$_h_val" || "$_h_value_is_last" == true ) ]]; then
                # Have field + operator. Fire when the value is still missing OR
                # when the cursor is on the value word itself (a partial value
                # being completed). In both cases complete the value, never the
                # and/or connector.
                case "$_h_op" in
                -eq|-ne)
                    if __bu_out_complete_field_values "$_h_field" && ((${#BU_RET[@]} > 0)); then
                        autocompletion=(--enum "${BU_RET[@]}" enum-- --hint "Values of $_h_field")
                    else
                        autocompletion=(--hint "Value for $_h_field $_h_op")
                    fi
                    ;;
                -in|-notin)
                    local -a _h_in_candidates=()
                    local _h_in_cand=
                    if __bu_out_complete_field_values "$_h_field" && ((${#BU_RET[@]} > 0)); then
                        for _h_in_cand in "${BU_RET[@]}"; do
                            [[ -n "${_h_in_used[$_h_in_cand]:-}" ]] && continue
                            [[ "$_h_in_cand" == "$_h_in_active"* ]] || continue
                            _h_in_candidates+=("${_h_in_prefix}${_h_in_cand}")
                        done
                    fi
                    if ((${#_h_in_candidates[@]} > 0)); then
                        autocompletion=(--enum "${_h_in_candidates[@]}" enum-- --hint "Values of $_h_field")
                    else
                        autocompletion=(--hint "Value for $_h_field $_h_op")
                    fi
                    ;;
                *)
                    autocompletion=(--hint "Value for $_h_field $_h_op")
                    ;;
                esac
            elif [[ "$_h_complete" == true ]]; then
                autocompletion=(--enum and or enum-- --hint "Logical connector (and/or)")
            fi
            if [[ -z "$_h_op" && -z "$_h_field" ]] && ((${#_h_connectors[@]} == 0)); then
                autocompletion=(--hint "Field name" --pipeline-fields pipeline-fields--)
            fi

            if ((${#_h_segments[@]} > 0)); then
                local _h_combined="${_h_segments[0]}"
                local _h_i
                for (( _h_i = 1; _h_i < ${#_h_segments[@]}; _h_i++ )); do
                    _h_combined="($_h_combined) ${_h_connectors[_h_i-1]} (${_h_segments[_h_i]})"
                done
                having_exprs+=("$_h_combined")
            fi
        fi
        ;;
    --order-by|order-by)# ORDER_BY
        # Field to sort by (refers to output field names, after any renames)
        bu_parse_positional $# --hint "Sort field" --pipeline-fields pipeline-fields--
        order_by=${!shift_by}
        ;;
    --outfile|outfile)# OUTFILE
        # Output query results to a file
        bu_parse_positional $# "${BU_AUTOCOMPLETE_SPEC_FILE[@]}" --hint "Output file. Defaults to stdout"
        out_file=${!shift_by}
        ;;
    --desc|desc)# _FLAG
        # Sort descending
        is_desc=true
        ;;
    --distinct|distinct)# _FLAG
        # Remove duplicate records (SELECT DISTINCT). Runs after select:
        # records are deduped as a whole, first occurrence wins.
        is_distinct=true
        ;;
    --first|first)# FIRST
        # Take only the first N records (after sorting)
        bu_parse_positional $# --hint "Number of records"
        first=${!shift_by}
        ;;
    --format)# FORMAT
        # Output format
        bu_parse_positional $# --enum ${BU_OUT_FORMATS[@]} enum-- --hint "Output format"
        bu_validate_positional "${!shift_by}"
        format=${!shift_by}
        ;;
    --columns)# COLUMNS
        # Display columns as key:Label (comma-separated). Forwarded to table/list/tsv.
        local -a _c_words=("$@")
        local -A _c_used=()
        local _c_spec= _c_consumed=0 _c_continues=false
        __bu_query_object_parse_comma_list _c_words 1 __bu_out_query_object_clause_keywords _c_spec _c_consumed _c_used _c_continues

        local _c_shift_by=$(( 1 + _c_consumed ))
        if bu_env_is_in_autocomplete && (( $# >= 2 )) && "$_c_continues"; then
            local _c_cur=${_c_words[-1]}
            local _c_active=${_c_cur##*,}
            local _c_prefix=${_c_cur%"$_c_active"}
            local -a _c_candidates=()
            local _c_cand=
            if __bu_out_complete_pipeline_fields "$_c_active"; then
                for _c_cand in "${BU_RET[@]}"; do
                    [[ -n "${_c_used[$_c_cand]:-}" ]] && continue
                    _c_candidates+=("${_c_prefix}${_c_cand}")
                done
            fi
            if ((${#_c_candidates[@]} > 0)); then
                autocompletion=(--enum "${_c_candidates[@]}" enum-- --hint "Comma-separated columns, key:Label renames headers")
            else
                autocompletion=(--hint "Comma-separated columns, key:Label renames headers")
            fi
            _c_shift_by=$(( _c_shift_by + 1 ))
        fi

        shift_by=$_c_shift_by
        columns=$_c_spec
        ;;
    -h|--help)# _FLAG
        # Print help
        is_help=true
        ;;
    --explain)# _FLAG
        # Describe execution without reading input or running the query.
        # --format json/jsonl emits a structured plan; otherwise show readable text.
        is_explain=true
        ;;
    --debug)# _FLAG
        # Output a JSON query plan describing what this query would do
        # (clauses and output field names) without reading stdin.
        # Used by the pipeline completion system for static analysis.
        is_debug=true
        ;;
    *)
        bu_parse_error_enum "$1"
        break
        ;;
    esac
    if "$is_help"
    then
        break
    fi
    if (( $# < shift_by ))
    then
        bu_parse_error_argn "$1" $#
        break
    fi
    shift "$shift_by"
done
local remaining_options=("$@")
if bu_env_is_in_autocomplete
then
    bu_autocomplete
    return 0
fi

if "$is_help"
then
    # Parsing errors also request help; they must not be reported as success.
    [[ -n "$error_msg" ]] && execution_status=1
    bu_autohelp \
        --description "
Query a JSONL stream with SQL-style clauses in a single command.
Clauses may be given in any order; execution always follows SQL logical
order: WHERE -> GROUP BY -> HAVING -> SELECT -> ORDER BY -> FIRST.

  where     Two syntaxes: raw jq expression ('.field == val') or structured
            comparison (field -op val). Structured operators:
              -eq -ne -gt -lt -ge -le   scalar comparisons
              -like -notlike            glob pattern matching (* and ?); no wildcard implies *pattern* (substring)
              -match -notmatch          regex matching (RLIKE)
              -contains -notcontains    array contains value
              -in -notin                value in comma-separated list
              -isnull -isnotnull        null checks
            Chain conditions with 'and'/'or' inside a single where:
              where type -eq source and name -like get-*
              where name -like command   # substring: matches get-command, set-module, ...
            Repeatable; multiple where clauses are ANDed.
  grep      search a pattern across any field value of each record (a grep of
            the row). Default is regex; -like/-ilike switch to glob (*/?)
            with bare-pattern substring semantics; -i/-ilike case-insensitive.
              grep get-            any field matches regex "get-"
              grep -like command   any field contains "command"
              grep -ilike get-*    any field starts with "get-" (any case)
            Repeatable; multiple grep clauses are ANDed.
  group-by  collapses records by key fields (comma-separated composite key)
  agg       aggregates per group: [name=]func[:field], repeatable and/or
            comma-separated. funcs: count, sum, avg, min, max, first, last, collect
  having    filters groups; same jq or structured syntax as where
  select    projects/reorders/renames fields (new=old)
  distinct  removes duplicate records after projection (SELECT DISTINCT)
  order-by  uses output field names  (after renames, like SQL aliases)
  first     takes the first N records (SQL LIMIT)
  from      reads records from a file instead of stdin (JSONL, CSV, TSV, or
            JSON, detected by extension)
  outfile   writes results to a file instead of stdout (defaults to JSONL
            there, since a file is not a terminal)

Each clause keyword works with or without dashes (select / --select).
Output ends at Out-Default: a table on a terminal, JSONL when piped.
BU_QUERY_EXECUTOR selects pipeline (default, separate processes) or combined
(one jq evaluator). Combined first stops reading once it has enough results;
upstream commands can still receive SIGPIPE under shell pipefail.
Use --explain for stages, buffering, and early-stop behavior without running
this query. --format json/jsonl emits a structured explanation. --debug keeps
its compact completion summary and takes precedence if both flags are used.
" \
        --example "Full query (structured)" "where type -eq source select name,verb order-by verb" \
        --example "Full query (jq)" "where '.type == \"source\"' select name,verb order-by verb" \
        --example "Glob pattern matching" "where name -like get-* select name,verb" \
        --example "Substring match (bare pattern)" "where name -like command select name,verb" \
        --example "Regex matching (RLIKE)" "where name -match '^get-' select name,verb" \
        --example "Multiple conditions (ANDed)" "where type -eq source where verb -ne help" \
        --example "And/or in one where" "where type -eq source and name -like get-*" \
        --example "Membership (comma-separated list)" "where type -in source,alias select name" \
        --example "Null check" "where version -isnotnull select name,version" \
        --example "Grep any field (regex)" "grep '^get-' select name,verb" \
        --example "Grep any field (glob/substring)" "grep -like command select name" \
        --example "Grep any field (case-insensitive glob)" "grep -ilike get-* select name" \
        --example "Any clause order" "order-by noun select name,noun where namespace -eq bu" \
        --example "Rename then order by the alias" "select name,ver=version order-by ver" \
        --example "Top 3" "order-by name first 3" \
        --example "Distinct projected fields" "select verb distinct" \
        --example "Group and count" "group-by verb agg count" \
        --example "Group with aggregates and having" "group-by verb agg count,avg:len having count -gt 1 order-by count desc" \
        --example "Dashed forms work too" "--where type -eq source --select name" \
        --example "Query a file instead of stdin" "from data.jsonl where type -eq source select name" \
        --example "Query a CSV file" "from data.csv where type -eq source select name" \
        --example "Query a TSV file" "from data.tsv select name,verb order-by name" \
        --example "Save results to a file" "select name,verb order-by name outfile verbs.jsonl"
    bu_scope_pop_function || cleanup_status=$?
    if (( execution_status == 0 )); then execution_status=$cleanup_status; fi
    return "$execution_status"
fi

# Normalize clauses once for either execution backend.
local where_expr=
if ((${#where_exprs[@]} > 0))
then
    where_expr="(${where_exprs[0]})"
    local w
    for w in "${where_exprs[@]:1}"
    do
        where_expr+=" and ($w)"
    done
fi

local grep_expr=
if ((${#grep_exprs[@]} > 0))
then
    grep_expr="(${grep_exprs[0]})"
    local g
    for g in "${grep_exprs[@]:1}"
    do
        grep_expr+=" and ($g)"
    done
fi

if [[ -n "$first" && ! "$first" =~ ^[0-9]+$ ]]
then
    error_msg="--first expects a non-negative integer, got[$first]"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

if [[ -z "$group_keys" ]] && ((${#agg_specs[@]} > 0))
then
    error_msg="agg requires group-by (e.g. bu query-object group-by verb agg count)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

local having_expr=
if ((${#having_exprs[@]} > 0))
then
    having_expr="(${having_exprs[0]})"
    local h
    for h in "${having_exprs[@]:1}"
    do
        having_expr+=" and ($h)"
    done
fi

# Resolve file paths against the invocation directory and validate them.
# Like the --first/agg validations above, this runs before --debug: a bad
# path simply fails plan generation and completion falls back gracefully.
if [[ -n "$from_file" ]]
then
    bu_realpath "$from_file" "$invocation_dir"
    from_file=$BU_RET
    if [[ ! -e "$from_file" ]]
    then
        error_msg="--from file does not exist[$from_file]"
    elif [[ -d "$from_file" ]]
    then
        error_msg="--from file is a directory[$from_file]"
    elif [[ ! -r "$from_file" ]]
    then
        error_msg="--from file is not readable[$from_file]"
    fi
fi

if [[ -z "$error_msg" && -n "$from_file" && "${from_file,,}" == *.csv ]] && ! command -v jc &>/dev/null
then
    error_msg="--from CSV file requires jc (pip install jc)"
fi

if [[ -z "$error_msg" && -n "$out_file" ]]
then
    bu_realpath "$out_file" "$invocation_dir"
    out_file=$BU_RET
    local -r out_file_dir=${out_file%/*}
    if [[ ! -d "$out_file_dir" ]]
    then
        error_msg="--outfile directory does not exist[$out_file_dir]"
    elif [[ -e "$out_file" && ! -w "$out_file" ]] || [[ ! -e "$out_file" && ! -w "$out_file_dir" ]]
    then
        error_msg="--outfile is not writable[$out_file]"
    fi
fi

if [[ -n "$error_msg" ]]
then
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

case "$executor" in
pipeline|combined) ;;
*)
    bu_log_err "Invalid BU_QUERY_EXECUTOR[$executor]. Expected pipeline or combined"
    bu_scope_pop_function
    return 1
    ;;
esac

__bu_query_object_build_plan()
{
    # Shared base for debug and explain. Keep the historical debug projection
    # byte-compatible, including clause order and null for unknown fields.
    local -a clauses=()
    local -a output_fields=()
    local sel_spec sel_new gk
    local ifs=$IFS
    local agg_spec agg_name agg_body agg_func agg_field
    local clauses_json fields_json base_plan

    [[ -n "$where_expr" ]] && clauses+=(where)
    [[ -n "$grep_expr" ]] && clauses+=(grep)
    [[ -n "$group_keys" ]] && clauses+=(group-by)
    ((${#agg_specs[@]} > 0)) && clauses+=(agg)
    [[ -n "$having_expr" ]] && clauses+=(having)
    [[ -n "$select_fields" ]] && clauses+=(select)
    "$is_distinct" && clauses+=(distinct)
    [[ -n "$order_by" ]] && clauses+=(order-by)

    # Compute output field names
    if [[ -n "$select_fields" ]]
    then
        # SELECT projects: output fields are the select spec names (after rename)
        IFS=','
        for sel_spec in $select_fields
        do
            [[ -z "$sel_spec" ]] && continue
            case "$sel_spec" in
            *=*) sel_new=${sel_spec%%=*} ;;
            *)   sel_new=$sel_spec ;;
            esac
            output_fields+=("$sel_new")
        done
        IFS=$ifs
    elif [[ -n "$group_keys" ]]
    then
        # GROUP BY without SELECT: output fields = group keys + aggregate names
        IFS=','
        for gk in $group_keys; do [[ -n "$gk" ]] && output_fields+=("$gk"); done
        IFS=$ifs
        for agg_spec in "${agg_specs[@]}"
        do
            case "$agg_spec" in
            *=*) agg_name=${agg_spec%%=*}; agg_body=${agg_spec#*=} ;;
            *)   agg_name=; agg_body=$agg_spec ;;
            esac
            agg_func=${agg_body%%:*}
            agg_field=${agg_body#*:}
            [[ "$agg_field" == "$agg_body" ]] && agg_field=
            [[ -z "$agg_name" ]] && agg_name=$agg_func${agg_field:+_$agg_field}
            output_fields+=("$agg_name")
        done
    fi

    clauses_json=$("$BU_OUT_JQ" -cn --args '$ARGS.positional' -- "${clauses[@]}") || return $?
    if ((${#output_fields[@]} > 0))
    then
        fields_json=$("$BU_OUT_JQ" -cn --args '$ARGS.positional' -- "${output_fields[@]}") || return $?
    else
        fields_json=null
    fi

    base_plan=$("$BU_OUT_JQ" -cn --argjson clauses "$clauses_json" --argjson fields "$fields_json" \
        '{clauses: $clauses, outputFields: $fields}') || return $?
    if "$is_explain" && ! "$is_debug"; then
        __bu_query_object_explain_plan "$base_plan"
    else
        printf '%s\n' "$base_plan"
    fi
}

__bu_query_object_explain_plan()
{
    local -r base_plan=$1
    local input_format=jsonl
    local resolved_format=$format
    local input_ext=${from_file##*.}

    if [[ -n "$from_file" && "$from_file" != /dev/stdin && "$from_file" != - ]]; then
        case "${input_ext,,}" in
        json|csv) input_format=${input_ext,,} ;;
        tsv|tab) input_format=tsv ;;
        esac
    fi
    # Resolve the query's eventual sink, without opening its output file.
    if [[ "$resolved_format" == auto ]]; then
        if [[ -n "$BU_OUTPUT_FORMAT" ]]; then
            resolved_format=$BU_OUTPUT_FORMAT
        elif [[ -z "$out_file" && -t 1 ]]; then
            resolved_format=table
        else
            resolved_format=jsonl
        fi
    fi

    "$BU_OUT_JQ" -cn --argjson base "$base_plan" \
        --arg executor "$executor" --arg source "${from_file:-stdin}" \
        --arg inputFormat "$input_format" --arg destination "${out_file:-stdout}" \
        --arg outputFormat "$resolved_format" --arg columns "$columns" \
        --arg where "$where_expr" --arg grep "$grep_expr" --arg group "$group_keys" \
        --arg having "$having_expr" --arg projection "$select_fields" \
        --arg order "$order_by" --arg first "$first" \
        --argjson expand "$is_select_expand" --argjson distinct "$is_distinct" \
        --argjson desc "$is_desc" --args '
        def stage($clause; $operation; $processing):
            {clause: $clause, operation: $operation, processing: $processing};
        ($first != "" and ($first | test("^0+$"))) as $zero
        | ($executor == "combined" and $zero) as $bypass
        | ($group != "" or $order != "" or $inputFormat == "csv") as $blocking
        | $base + {
            version: 1,
            executor: $executor,
            input: {source: $source, format: $inputFormat,
                processing: (if $bypass then "not-read"
                    elif $inputFormat == "csv" then "buffers-input"
                    elif $inputFormat == "json" then "buffers-json-value"
                    else "streaming" end)},
            output: {destination: $destination, format: $outputFormat, columns: $columns,
                processing: (if $outputFormat == "table" or $outputFormat == "json"
                    then "buffers-results" else "streaming" end)},
            stages: [
                if $where != "" then stage("where"; $where; "streaming") else empty end,
                if $grep != "" then stage("grep"; $grep; "streaming") else empty end,
                if $group != "" then
                    stage("group-by"; {keys: $group, aggregates: $ARGS.positional}; "buffers-input")
                else empty end,
                if $having != "" then stage("having"; $having; "streaming") else empty end,
                if $projection != "" then
                    stage("select"; {fields: $projection, expand: $expand}; "streaming")
                else empty end,
                if $distinct then stage("distinct"; "First occurrence of each projected value"; "retains-seen-values") else empty end,
                if $order != "" then
                    stage("order-by"; {field: $order, direction: (if $desc then "descending" else "ascending" end)}; "buffers-input")
                else empty end,
                if $first != "" then
                    stage("first"; ($first | tonumber); (if $executor == "combined" then "stops-requesting-records" else "closes-upstream-pipe" end))
                else empty end
            ],
            execution: (if $executor == "combined" then
                [if $inputFormat == "csv" and ($bypass | not) then "jc --csv" else empty end,
                 "jq (combined query)", "format " + $outputFormat]
            else
                ["input reader",
                 (if $where != "" or $grep != "" then "where/grep: jq" else "where: cat" end),
                 (if $group != "" then "group-by: jq" else "group-by: cat" end),
                 (if $having != "" then "having: jq" else "having: cat" end),
                 (if $projection != "" then "select: jq" else "select: cat" end),
                 (if $distinct then "distinct: jq" else "distinct: cat" end),
                 (if $order != "" then "order-by: jq" else "order-by: cat" end),
                 (if $first != "" then "head -n " + $first else "first: cat" end),
                 "format " + $outputFormat]
            end),
            notes: [
                if $bypass then "first 0 bypasses input and the other query stages."
                elif $first != "" and $blocking then "Grouping, sorting, or CSV conversion requires all input before results reach first."
                elif $first != "" then "The query can stop reading once enough matching results reach first."
                else "No first limit is set; normal processing continues to end of input." end,
                if $inputFormat == "json" and ($bypass | not) then "Each JSON value is parsed in full before array elements can be queried." else empty end,
                if $distinct then "Distinct retains seen values; memory grows with the number of unique results." else empty end,
                if $outputFormat == "table" or $outputFormat == "json" then "The formatter buffers query results, which may already be limited by first." else empty end,
                if $first != "" then "External upstream producers can receive SIGPIPE when reading stops." else empty end,
                if $executor == "pipeline" and $first != "" then "head closes internal pipes early; expected SIGPIPE is handled separately from real failures." else empty end,
                if $expand then "Expanded output field names cannot be inferred from the projection alone." else empty end,
                if $where != "" or $having != "" then "Raw jq expressions are not executed or analyzed for input consumption; input/inputs can change the behavior shown here." else empty end
            ]
        }
        | if $expand then .outputFields = null else . end
        ' -- "${agg_specs[@]}"
}

__bu_query_object_render_plan()
{
    # Render only the already-built plan. Never attach this to query input or
    # send it to outfile; outfile describes the eventual query destination.
    case "$format" in
    json) "$BU_OUT_JQ" . <<< "$query_plan" ;;
    jsonl) printf '%s\n' "$query_plan" ;;
    *)
        "$BU_OUT_JQ" -r '
            def operation:
                if .clause == "select" then .operation.fields + (if .operation.expand then " (expand)" else "" end)
                elif .clause == "group-by" then .operation.keys + (if (.operation.aggregates | length) > 0 then " agg " + (.operation.aggregates | join(",")) else " (distinct keys)" end)
                elif .clause == "order-by" then .operation.field + " " + .operation.direction
                else .operation | tostring end;
            "Executor: " + .executor,
            "Input:    " + .input.source + " (" + .input.format + "; " + .input.processing + ")",
            "Output:   " + .output.destination + " (" + .output.format + "; " + .output.processing + ")",
            "", "Stages (logical order):",
            (if (.stages | length) == 0 then "  Identity (no query clauses)"
             else .stages[] | "  " + (.clause | ascii_upcase) + "  "
                  + operation
                  + "  [" + .processing + "]" end),
            "", "Execution: " + (.execution | join(" → ")),
            "", (.notes[] | "- " + .)
        ' <<< "$query_plan"
        ;;
    esac
}

if "$is_debug" || "$is_explain"; then
    if query_plan=$(__bu_query_object_build_plan); then
        if "$is_debug"; then
            printf '%s\n' "$query_plan" || execution_status=$?
        else
            __bu_query_object_render_plan || execution_status=$?
        fi
    else
        execution_status=$?
    fi
    bu_scope_pop_function || cleanup_status=$?
    if (( execution_status == 0 )); then execution_status=$cleanup_status; fi
    return "$execution_status"
fi

# ```md
# Compile the enclosing query's parsed clauses into a jq stream expression.
# SQL order and shared core filters preserve the pipeline executor's semantics.
# Returns: BU_RET contains the program; nonzero for invalid field specifications.
# ```
__bu_query_object_compile()
{
    local program=inputs
    local prelude=
    local filter=
    local input_ext=${from_file##*.}

    # Read native files in the evaluator itself, without a forwarding process
    # that could receive SIGPIPE when limit() stops requesting records.
    if [[ -n "$from_file" && "$from_file" != /dev/stdin && "$from_file" != - ]]; then
        case "${input_ext,,}" in
        json|csv)
            program='inputs | if type == "array" then .[] else . end'
            ;;
        tsv|tab)
            program='(first(inputs) | select(. != "") | split("\t")) as $__bu_columns
                | inputs | select(. != "") | split("\t")
                | reduce to_entries[] as $e ({};
                    if $__bu_columns[$e.key] != null and $__bu_columns[$e.key] != ""
                    then .[$__bu_columns[$e.key]] = $e.value else . end)'
            ;;
        esac
    fi
    if [[ -n "$where_expr" && -n "$grep_expr" ]]; then
        program="($program) | select(($where_expr) and ($grep_expr))"
    elif [[ -n "$where_expr" ]]; then
        program="($program) | select($where_expr)"
    elif [[ -n "$grep_expr" ]]; then
        program="($program) | select($grep_expr)"
    fi
    if [[ -n "$group_keys" ]]; then
        __bu_out_group_filter "$group_keys" "${agg_specs[@]}" || return 1
        filter=$BU_RET
        program="[$program] | ($filter)"
    fi
    if [[ -n "$having_expr" ]]; then
        program="($program) | select($having_expr)"
    fi
    if [[ -n "$select_fields" ]]; then
        __bu_out_select_filter "$select_fields" "$is_select_expand" || return 1
        filter=$BU_RET
        program="($program) | ($filter)"
    fi
    if "$is_distinct"; then
        prelude=$__BU_OUT_JQ_DISTINCT
        program="__bu_distinct($program)"
    fi
    if [[ -n "$order_by" ]]; then
        __bu_out_validate_key "$order_by" || return 1
        program="[$program] | sort_by(.$order_by)"
        "$is_desc" && program+=' | reverse'
        program+=' | .[]'
    fi
    if [[ -n "$first" ]]; then
        # tonumber accepts leading zeros without treating the limit as octal.
        program="limit((\"$first\" | tonumber); $program)"
    fi
    BU_RET="$prelude $program"
}

# ```md
# Run the compiled query, reading stdin or a native file directly. CSV is
# handled by combined_pipeline so it can capture the converter status.
# Uses the enclosing combined_program and from_file locals.
# ```
__bu_query_object_combined_input()
{
    local input_ext=${from_file##*.}

    if [[ "$first" =~ ^0+$ ]]; then
        "$BU_OUT_JQ" -nc "$combined_program" </dev/null
    elif [[ -z "$from_file" || "$from_file" == /dev/stdin || "$from_file" == - ]]; then
        "$BU_OUT_JQ" -nc "$combined_program"
    else
        case "${input_ext,,}" in
        tsv|tab) "$BU_OUT_JQ" -Rnc "$combined_program" < "$from_file" ;;
        *) "$BU_OUT_JQ" -nc "$combined_program" < "$from_file" ;;
        esac
    fi
}

# Report stage failures and return the rightmost genuine failure. SIGPIPE from
# a writer before a successful FIRST stage is expected cancellation. SIGPIPE
# following a downstream failure is secondary; never hide other exit codes.
__bu_query_object_status()
{
    local -n stage_names=$1
    local -n stage_statuses=$2
    local -r first_index=${3:--1}
    local status=0
    local i code

    for (( i=${#stage_statuses[@]}-1; i>=0; i-- )); do
        code=${stage_statuses[i]}
        (( code == 0 )) && continue
        if (( code == 141 )); then
            if (( status != 0 )); then continue; fi
            if (( first_index >= 0 && i < first_index && stage_statuses[first_index] == 0 )); then
                continue
            fi
        fi
        bu_log_err "query-object [$executor]: ${stage_names[i]} stage failed (status $code)"
        if (( status == 0 || status == 141 )); then status=$code; fi
    done
    return "$status"
}

__bu_query_object_combined_pipeline()
{
    local -a statuses=()
    local -a stages=(query format)
    local input_ext=${from_file##*.}

    # Guard execution so errexit cannot bypass status capture and cleanup.
    if [[ "${input_ext,,}" == csv && ! "$first" =~ ^0+$ ]]; then
        stages=(csv-input query format)
        if jc --csv < "$from_file" | "$BU_OUT_JQ" -nc "$combined_program" | bu_out "${out_args[@]}"; then
            statuses=("${PIPESTATUS[@]}")
        else
            statuses=("${PIPESTATUS[@]}")
        fi
    else
        if __bu_query_object_combined_input | bu_out "${out_args[@]}"; then
            statuses=("${PIPESTATUS[@]}")
        else
            statuses=("${PIPESTATUS[@]}")
        fi
    fi
    __bu_query_object_status stages statuses
}

__bu_query_object_where()
{
    if [[ -n "$where_expr" && -n "$grep_expr" ]]
    then
        bu_out_where "($where_expr) and ($grep_expr)"
    elif [[ -n "$where_expr" ]]
    then
        bu_out_where "$where_expr"
    elif [[ -n "$grep_expr" ]]
    then
        bu_out_where "$grep_expr"
    else
        cat
    fi
}

__bu_query_object_group()
{
    if [[ -n "$group_keys" ]]
    then
        local -a group_args=(--keys "$group_keys")
        local spec
        for spec in "${agg_specs[@]}"
        do
            group_args+=(--agg "$spec")
        done
        bu_out_group_by "${group_args[@]}"
    else
        cat
    fi
}

__bu_query_object_having()
{
    if [[ -n "$having_expr" ]]
    then
        bu_out_where "$having_expr"
    else
        cat
    fi
}

__bu_query_object_select()
{
    if [[ -n "$select_fields" ]]
    then
        local -a _qs_args=()
        "$is_select_expand" && _qs_args+=(--expand)
        _qs_args+=("$select_fields")
        bu_out_select "${_qs_args[@]}"
    else
        cat
    fi
}

__bu_query_object_distinct()
{
    if "$is_distinct"
    then
        bu_out_distinct
    else
        cat
    fi
}

__bu_query_object_sort()
{
    if [[ -n "$order_by" ]]
    then
        local -a sort_args=("$order_by")
        "$is_desc" && sort_args+=(--desc)
        bu_out_sort_by "${sort_args[@]}"
    else
        cat
    fi
}

__bu_query_object_first()
{
    if [[ -n "$first" ]]
    then
        head -n "$first"
    else
        cat
    fi
}

__bu_query_object_pipeline()
{
    local -a statuses=()
    local -a stages=(input where group-by having select distinct order-by first format)
    local first_index=-1
    [[ -n "$first" ]] && first_index=7
    # Cmdlets implicitly end at Out-Default: a table on a terminal, JSONL when piped
    if __bu_query_object_input | __bu_query_object_where | __bu_query_object_group | __bu_query_object_having | __bu_query_object_select | __bu_query_object_distinct | __bu_query_object_sort | __bu_query_object_first | bu_out "${out_args[@]}"; then
        statuses=("${PIPESTATUS[@]}")
    else
        statuses=("${PIPESTATUS[@]}")
    fi
    __bu_query_object_status stages statuses "$first_index"
}

__bu_query_object_input()
{
    if [[ -z "$from_file" || "$from_file" == /dev/stdin || "$from_file" == - ]]
    then
        cat
    else
        __bu_out_read_file_jsonl "$from_file" "" true
    fi
}

local -a out_args=(--format "$format")
[[ -n "$columns" ]] && out_args+=(--columns "$columns")

if [[ "$executor" == combined ]]; then
    if __bu_query_object_compile; then
        combined_program=$BU_RET
        query_runner=__bu_query_object_combined_pipeline
    else
        execution_status=$?
        bu_log_err "query-object [$executor]: compile stage failed (status $execution_status)"
    fi
fi

if (( execution_status == 0 )); then
    if [[ -n "$out_file" ]]; then
        # A file is never a terminal, so auto resolves to JSONL there.
        "$query_runner" > "$out_file" || execution_status=$?
    else
        "$query_runner" || execution_status=$?
    fi
fi

bu_scope_pop_function || cleanup_status=$?
if (( cleanup_status != 0 )); then
    bu_log_err "query-object [$executor]: cleanup failed (status $cleanup_status)"
fi
if (( execution_status == 0 )); then execution_status=$cleanup_status; fi
return "$execution_status"
}

__bu_bu_query_object_main "$@"
