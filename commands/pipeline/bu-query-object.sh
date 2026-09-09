#!/usr/bin/env bash
# Pipeline: query
# Dispatch: source
# Synopsis: Apply SQL-style clauses (where, group-by, select, order-by) to a JSONL stream
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
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --select|select)# SELECT
        # Fields to keep, in order (comma-separated; new=old renames)
        bu_parse_positional $# --hint "Fields, new=old renames" --pipeline-fields pipeline-fields--
        select_fields=${!shift_by}
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

            while true; do
                # --- Parse operator for current field ---
                local _w_op= _w_val= _w_cond_consume=0
                local _w_o_idx=$(( shift_by + _w_extra + 1 ))
                if (( _w_o_idx <= $# )); then
                    local _w_o_arg=${!_w_o_idx}
                    case "$_w_o_arg" in
                    -eq|-ne|-gt|-lt|-ge|-le|-like|-notlike|-match|-notmatch|-contains|-notcontains|-in|-notin)
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
                    if __bu_out_complete_field_values "$_w_field" && ((${#BU_RET[@]} > 0)); then
                        autocompletion=(--delimited "${BU_RET[@]}" delimited-- --hint "Values of $_w_field")
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
        bu_parse_positional $# --hint "Group key fields" --pipeline-fields pipeline-fields--
        group_keys=${!shift_by}
        ;;
    --agg|agg)# AGG
        # Aggregates for group-by: [name=]func[:field], comma-separated and/or
        # repeatable. funcs: count, sum, avg, min, max, first, last, collect
        bu_parse_positional $# --enum count sum avg min max first last collect enum-- --hint "Aggregates: [name=]func[:field]"
        local agg_spec
        local ifs=$IFS
        IFS=','
        # shellcheck disable=SC2206 # Intentional word splitting on commas
        for agg_spec in ${!shift_by}; do [[ -n "$agg_spec" ]] && agg_specs+=("$agg_spec"); done
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

            while true; do
                local _h_op= _h_val= _h_cond_consume=0
                local _h_o_idx=$(( shift_by + _h_extra + 1 ))
                if (( _h_o_idx <= $# )); then
                    local _h_o_arg=${!_h_o_idx}
                    case "$_h_o_arg" in
                    -eq|-ne|-gt|-lt|-ge|-le|-like|-notlike|-match|-notmatch|-contains|-notcontains|-in|-notin)
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
                    if __bu_out_complete_field_values "$_h_field" && ((${#BU_RET[@]} > 0)); then
                        autocompletion=(--delimited "${BU_RET[@]}" delimited-- --hint "Values of $_h_field")
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
        bu_parse_positional $# --hint "Comma-separated columns, key:Label renames headers" --pipeline-fields pipeline-fields--
        columns=${!shift_by}
        ;;
    -h|--help)# _FLAG
        # Print help
        is_help=true
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
    return 0
fi

# Compose the clauses into a pipeline in SQL logical order, using identity
# stages (cat) for absent clauses so no eval or string assembly is needed.
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

if "$is_debug"
then
    # --debug: emit a JSON query plan describing clauses and output fields.
    # Used by the pipeline completion system for static field analysis.
    # Does not read stdin.
    local -a clauses=()
    local -a output_fields=()

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
        local sel_spec sel_new
        local ifs=$IFS
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
        local gk
        local ifs=$IFS
        IFS=','
        for gk in $group_keys; do [[ -n "$gk" ]] && output_fields+=("$gk"); done
        IFS=$ifs
        local agg_spec agg_name agg_body agg_func agg_field
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

    local clauses_json
    clauses_json=$("$BU_OUT_JQ" -cn --args '$ARGS.positional' -- "${clauses[@]}")
    local fields_json
    if ((${#output_fields[@]} > 0))
    then
        fields_json=$("$BU_OUT_JQ" -cn --args '$ARGS.positional' -- "${output_fields[@]}")
    else
        fields_json=null
    fi

    "$BU_OUT_JQ" -cn --argjson clauses "$clauses_json" --argjson fields "$fields_json" \
        '{clauses: $clauses, outputFields: $fields}'
    bu_scope_pop_function
    return 0
fi

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

local -a out_args=(--format "$format")
[[ -n "$columns" ]] && out_args+=(--columns "$columns")

__bu_query_object_pipeline()
{
    # Cmdlets implicitly end at Out-Default: a table on a terminal, JSONL when piped
    __bu_query_object_where | __bu_query_object_group | __bu_query_object_having | __bu_query_object_select | __bu_query_object_distinct | __bu_query_object_sort | __bu_query_object_first | bu_out "${out_args[@]}"
}

__bu_query_object_input()
{
    if [[ -z "$from_file" || "$from_file" == /dev/stdin || "$from_file" == - ]]
    then
        cat
    else
        __bu_out_read_file_jsonl "$from_file"
    fi
}

if [[ -n "$out_file" ]]
then
    # A file is never a terminal, so --format auto resolves to JSONL there
    __bu_query_object_input | __bu_query_object_pipeline > "$out_file"
else
    __bu_query_object_input | __bu_query_object_pipeline
fi

bu_scope_pop_function
}

__bu_bu_query_object_main "$@"
