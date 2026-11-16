# Column declarations and static lineage. Never execute a producer to describe it.
declare -g -a BU_COLUMN_TYPES=(string int float bool object array any)
declare -g -a BU_COLUMN_UNITS=(ns us ms s min h d bytes kb mb gb pct bps ticks)
declare -g -A BU_OUT_PRODUCER_COLUMNS=()
declare -g -A __BU_COLUMN_FILES=()
# Canonical command -> function mapping a stage's arguments to its columns.
declare -g -A BU_OUT_PRODUCER_COLUMNS_FROM=()
declare -g BU_OUT_COMPLETE_PRODUCER=

# *Description*:
# Parse a Column header value into BU_RET=(name type unit description).
# A missing name is an error; unrecognized type/unit tokens start the description.
__bu_column_parse_line()
{
    local _cp_text=$1 _cp_name='' _cp_type=any _cp_unit='' _cp_token='' _cp_item _cp_unit_item
    BU_RET=()
    _cp_text=${_cp_text#"${_cp_text%%[![:space:]]*}"}
    [[ -n "$_cp_text" ]] || return 1
    _cp_name=${_cp_text%%[[:space:]]*}
    _cp_text=${_cp_text#"$_cp_name"}
    _cp_text=${_cp_text#"${_cp_text%%[![:space:]]*}"}
    _cp_token=${_cp_text%%[[:space:]]*}
    for _cp_item in "${BU_COLUMN_TYPES[@]}"; do
        if [[ "$_cp_token" == "$_cp_item" ]]; then
            _cp_type=$_cp_token
            _cp_text=${_cp_text#"$_cp_token"}
            _cp_text=${_cp_text#"${_cp_text%%[![:space:]]*}"}
            _cp_token=${_cp_text%%[[:space:]]*}
            for _cp_unit_item in "${BU_COLUMN_UNITS[@]}"; do
                if [[ "$_cp_token" == "$_cp_unit_item" ]]; then
                    _cp_unit=$_cp_token
                    _cp_text=${_cp_text#"$_cp_token"}
                    _cp_text=${_cp_text#"${_cp_text%%[![:space:]]*}"}
                    break
                fi
            done
            break
        fi
    done
    _cp_text=${_cp_text%"${_cp_text##*[![:space:]]}"}
    BU_RET=("$_cp_name" "$_cp_type" "$_cp_unit" "$_cp_text")
}

# *Description*:
# Resolve a file's field list, preferring Fields (even an empty header) to Columns.
# *Params*:
# - `$1`: File; `$2`: output scalar name (space-separated field names).
__bu_command_fields_get()
{
    local -n _cfg_out=$2
    local -a _cfg_values=() _cfg_saved=("${BU_RET[@]}") _cfg_names=()
    local _cfg_value
    __bu_command_header_get_all "$1" Fields _cfg_values
    if ((${#_cfg_values[@]})); then
        _cfg_out=${_cfg_values[0]}
        return 0
    fi
    __bu_command_header_get_all "$1" Column _cfg_values
    for _cfg_value in "${_cfg_values[@]}"; do
        __bu_column_parse_line "$_cfg_value" || continue
        _cfg_names+=("${BU_RET[0]}")
    done
    _cfg_out=${_cfg_names[*]}
    BU_RET=("${_cfg_saved[@]}")
    return 0
}

# *Description*:
# Register columns for a function or alias, also registering its field names.
# *Params*:
# - `$1`: Canonical command (bu verb-noun); remaining arguments: Column values.
bu_register_output_columns()
{
    local _rc_cmd=${1:-} _rc_value _rc_rows='' _rc_row
    local -a _rc_names=()
    local IFS=' '
    [[ -n "$_rc_cmd" && $# -gt 1 ]] || return 1
    shift
    for _rc_value in "$@"; do
        __bu_column_parse_line "$_rc_value" || return 1
        _rc_names+=("${BU_RET[0]}")
        printf -v _rc_row '%s\x1f%s\x1f%s\x1f%s' "${BU_RET[@]}"
        _rc_rows+=${_rc_rows:+$'\n'}$_rc_row
    done
    BU_OUT_PRODUCER_COLUMNS[$_rc_cmd]=$_rc_rows
    BU_OUT_PRODUCER_FIELDS[$_rc_cmd]=${_rc_names[*]}
    unset '__BU_COLUMN_FILES[$_rc_cmd]'
}

# *Description*:
# Get newline-separated name/type/unit/description rows, separated by US (0x1f).
# *Params*:
# - `$1`: Command; `$2`: output scalar name. Returns 1 without declarations.
__bu_column_for_command()
{
    local -n _cfc_out=$2
    local _cfc_cmd=$1 _cfc_file _cfc_value _cfc_rows='' _cfc_row
    local -a _cfc_values=() _cfc_saved=("${BU_RET[@]}")
    local IFS=' '
    _cfc_out=
    __bu_out_canonicalize_stage "$_cfc_cmd"
    _cfc_cmd=${BU_CANONICAL_STAGE#bu }
    _cfc_cmd=${_cfc_cmd%%[[:space:]]*}
    _cfc_cmd="bu $_cfc_cmd"
    if [[ -v BU_OUT_PRODUCER_COLUMNS[$_cfc_cmd] ]]; then
        _cfc_out=${BU_OUT_PRODUCER_COLUMNS[$_cfc_cmd]}
    else
        _cfc_file=${BU_COMMANDS[${_cfc_cmd#bu }]:-}
        [[ -f "$_cfc_file" ]] || return 1
        __bu_command_header_get_all "$_cfc_file" Column _cfc_values
        for _cfc_value in "${_cfc_values[@]}"; do
            __bu_column_parse_line "$_cfc_value" || continue
            printf -v _cfc_row '%s\x1f%s\x1f%s\x1f%s' "${BU_RET[@]}"
            _cfc_rows+=${_cfc_rows:+$'\n'}$_cfc_row
        done
        BU_OUT_PRODUCER_COLUMNS[$_cfc_cmd]=$_cfc_rows
        __BU_COLUMN_FILES[$_cfc_cmd]=$_cfc_file
        _cfc_out=$_cfc_rows
    fi
    BU_RET=("${_cfc_saved[@]}")
    [[ -n "$_cfc_out" ]]
}

# *Description*:
# Name the function that declares a command's columns from its arguments, for
# a function or alias command (a script uses a `# Columns-From:` header).
#
# The function is called with the stage's arguments (the words after the
# command name, taken literally from the pipeline text: nothing is expanded
# or executed) and sets `BU_RET` to one entry per output column, in order.
# An entry is either a full declaration in the `# Column:` grammar
# (`name type [unit] description`) or a bare name, which takes its type, unit
# and description from the command's static `# Column:` declaration of that
# name. A non-zero return or an empty `BU_RET` falls back to the static
# declarations. It must not run the producer.
#
# *Params*:
# - `$1`: Canonical command (`bu verb-noun`)
# - `$2`: Function name
#
# *Example*:
# ```bash
# __my_volume_columns() {
#     BU_RET=(name size)
#     [[ " $* " == *' --inodes '* ]] && BU_RET=(name inodes)
#     return 0
# }
# bu_register_output_columns_from "bu get-volume" __my_volume_columns
# ```
bu_register_output_columns_from()
{
    [[ -n "${1:-}" && -n "${2:-}" ]] || return 1
    BU_OUT_PRODUCER_COLUMNS_FROM[$1]=$2
}

# *Description*:
# Name of a command's Columns-From function: the registry, then the script's
# `# Columns-From:` header. Empty when there is none or it is not defined.
#
# *Params*:
# - `$1`: Command name without the `bu ` prefix; `$2`: output scalar name.
__bu_column_from_function()
{
    local -n _cff_out=$2
    local _cff_file=${BU_COMMANDS[$1]:-}
    _cff_out=${BU_OUT_PRODUCER_COLUMNS_FROM[bu $1]:-}
    if [[ -z "$_cff_out" && -f "$_cff_file" ]]; then
        __bu_command_header_get "$_cff_file" Columns-From _cff_out
    fi
    if [[ -n "$_cff_out" ]] && ! declare -F -- "$_cff_out" >/dev/null; then _cff_out=; fi
    return 0
}

# *Description*:
# Columns of one stage as declared by its Columns-From function for these
# arguments: newline-separated name/type/unit/description rows joined by US.
#
# *Params*:
# - `$1`: Command name without the `bu ` prefix; `$2`: output scalar name;
#   remaining arguments: the stage's arguments.
#
# *Returns*:
# - 1 when the command has no Columns-From function or it declared nothing.
__bu_column_from_stage()
{
    local -n _cfs_out=$2
    local -r _cfs_cmd=$1
    local _cfs_func= _cfs_static= _cfs_line _cfs_row _cfs_rows= _cfs_name _cfs_rest
    local -a _cfs_lines=() _cfs_saved=("${BU_RET[@]}")
    local -A _cfs_known=()
    shift 2
    _cfs_out=
    __bu_column_from_function "$_cfs_cmd" _cfs_func
    [[ -n "$_cfs_func" ]] || return 1
    BU_RET=()
    if "$_cfs_func" "$@"; then _cfs_lines=("${BU_RET[@]}"); fi
    if ((${#_cfs_lines[@]})); then
        __bu_column_for_command "bu $_cfs_cmd" _cfs_static || true
        while IFS=$'\x1f' read -r _cfs_name _cfs_rest; do
            [[ -n "$_cfs_name" ]] && _cfs_known[$_cfs_name]=$_cfs_rest
        done <<< "$_cfs_static"
        for _cfs_line in "${_cfs_lines[@]}"; do
            __bu_column_parse_line "$_cfs_line" || continue
            _cfs_name=${BU_RET[0]}
            if [[ "${BU_RET[1]}" == any && -z "${BU_RET[2]}${BU_RET[3]}" && -n "${_cfs_known[$_cfs_name]:-}" ]]; then
                # A bare name: inherit the static declaration.
                _cfs_row=$_cfs_name$'\x1f'${_cfs_known[$_cfs_name]}
            else
                printf -v _cfs_row '%s\x1f%s\x1f%s\x1f%s' "${BU_RET[@]}"
            fi
            _cfs_rows+=${_cfs_rows:+$'\n'}$_cfs_row
        done
    fi
    BU_RET=("${_cfs_saved[@]}")
    _cfs_out=$_cfs_rows
    [[ -n "$_cfs_rows" ]]
}

# *Description*:
# Columns-From for `bu convert-from-tsv`: the names in `--columns a,b:Label`.
__bu_column_from_tsv_args()
{
    local _ct_spec= _ct_item
    local -a _ct_items=()
    BU_RET=()
    while (($#)); do
        if [[ "$1" == --columns ]]; then _ct_spec=${2:-}; fi
        shift
    done
    IFS=, read -r -a _ct_items <<< "$_ct_spec"
    for _ct_item in "${_ct_items[@]}"; do
        _ct_item=${_ct_item%%:*}
        [[ -n "$_ct_item" ]] && BU_RET+=("$_ct_item string")
    done
    return 0
}

# *Description*:
# Columns-From for `bu convert-from-lines`: the key named by `--column`.
__bu_column_from_lines_args()
{
    BU_RET=()
    while (($#)); do
        if [[ "$1" == --column && -n "${2:-}" ]]; then BU_RET=("$2 string"); fi
        shift
    done
    return 0
}

# *Description*:
# Columns-From for `bu new-record`: `key=value` is a string, `key:=value` is typed.
__bu_column_from_record_args()
{
    BU_RET=()
    while (($#)); do
        case "$1" in
        --format) shift ;;
        -*) ;;
        *:=*) BU_RET+=("${1%%:=*}") ;;
        *=*) BU_RET+=("${1%%=*} string") ;;
        esac
        (($#)) && shift
    done
    return 0
}

# *Description*:
# Split literal shell text into stages or words, respecting quotes and escapes.
# This lexer performs no expansions, substitutions, globbing, or execution.
# *Params*:
# - `$1`: stages|words; `$2`: text; `$3`: output array name.
__bu_column_split()
{
    local _cs_mode=$1 _cs_text=$2 _cs_char _cs_quote='' _cs_part='' _cs_escape=false _cs_started=false _cs_i
    local -n _cs_out=$3
    _cs_out=()
    for ((_cs_i=0; _cs_i<${#_cs_text}; _cs_i++)); do
        _cs_char=${_cs_text:_cs_i:1}
        if "$_cs_escape"; then
            _cs_part+=$_cs_char; _cs_escape=false
        elif [[ "$_cs_char" == \\ && "$_cs_quote" != "'" ]]; then
            [[ "$_cs_mode" == stages ]] && _cs_part+=$_cs_char
            _cs_escape=true; _cs_started=true
        elif [[ -n "$_cs_quote" ]]; then
            if [[ "$_cs_char" == "$_cs_quote" ]]; then
                _cs_quote=
                [[ "$_cs_mode" == stages ]] && _cs_part+=$_cs_char
            else
                _cs_part+=$_cs_char
            fi
        elif [[ "$_cs_char" == "'" || "$_cs_char" == '"' ]]; then
            _cs_quote=$_cs_char; _cs_started=true
            [[ "$_cs_mode" == stages ]] && _cs_part+=$_cs_char
        elif { [[ "$_cs_mode" == stages && "$_cs_char" == '|' ]] || [[ "$_cs_mode" == words && "$_cs_char" == [[:space:]] ]]; }; then
            if "$_cs_started"; then _cs_out+=("$_cs_part"); fi
            _cs_part=; _cs_started=false
        else
            _cs_part+=$_cs_char; _cs_started=true
        fi
    done
    [[ -z "$_cs_quote" && "$_cs_escape" == false ]] || return 1
    if "$_cs_started"; then _cs_out+=("$_cs_part"); fi
    return 0
}

# *Description*:
# Apply query clauses to ordered column names and their US-separated metadata.
# *Params*:
# - `$1`: words array; `$2`: names array; `$3`: metadata associative array.
__bu_column_query()
{
    local -n _cq_words=$1 _cq_names=$2 _cq_rows=$3
    local _cq_i _cq_word _cq_spec _cq_joined _cq_select='' _cq_group='' _cq_item _cq_old _cq_name
    local _cq_type _cq_unit _cq_desc _cq_source _cq_producer _cq_derived _cq_body _cq_func _cq_label _cq_suffix=
    local _cq_default_producer=
    local -a _cq_aggs=() _cq_specs=() _cq_next=() _cq_groups=()
    local -A _cq_new_rows=()
    local -r _cq_sep=$'\x1f'
    # Consume comparison values and grep patterns as data, never as clause names.
    for ((_cq_i=2; _cq_i<${#_cq_words[@]}; _cq_i++)); do
        _cq_word=${_cq_words[_cq_i]#--}
        case "$_cq_word" in
        where|having|and|or)
            : $((_cq_i+=1))
            if [[ "${_cq_words[_cq_i+1]:-}" == -[a-z]* ]]; then
                case "${_cq_words[_cq_i+1]}" in
                -isnull|-isnotnull) : $((_cq_i+=1)) ;;
                *) : $((_cq_i+=2)) ;;
                esac
            fi
            ;;
        grep)
            while [[ "${_cq_words[_cq_i+1]:-}" == -* ]]; do : $((_cq_i+=1)); done
            : $((_cq_i+=1))
            ;;
        select|group-by|agg)
            __bu_out_collect_comma_spec _cq_words $((_cq_i+1)) _cq_spec
            case "$_cq_word" in
            select) _cq_select=$_cq_spec ;;
            group-by) _cq_group=$_cq_spec ;;
            agg) _cq_aggs+=("$_cq_spec") ;;
            esac
            # Advance over the exact words collected by the shared query parser.
            _cq_joined=
            while [[ "$_cq_joined" != "$_cq_spec" ]] && ((_cq_i+1 < ${#_cq_words[@]})); do
                : $((_cq_i+=1))
                _cq_joined+=${_cq_words[_cq_i]}
            done
            ;;
        order-by|first|from|outfile|format|columns) : $((_cq_i+=1)) ;;
        esac
    done
    if ((${#_cq_names[@]})); then
        IFS=$_cq_sep read -r _cq_type _cq_unit _cq_desc _cq_source _cq_default_producer _cq_derived <<< "${_cq_rows[${_cq_names[0]}]}"
    fi
    if [[ -n "$_cq_group" ]] || ((${#_cq_aggs[@]})); then
        IFS=, read -r -a _cq_groups <<< "$_cq_group"
        for _cq_name in "${_cq_groups[@]}"; do
            [[ -n "$_cq_name" ]] || continue
            _cq_next+=("$_cq_name")
            _cq_new_rows[$_cq_name]=${_cq_rows[$_cq_name]:-"$_cq_sep$_cq_sep${_cq_sep}none$_cq_sep$_cq_sep"}
        done
        [[ -n "$_cq_group" ]] && _cq_suffix=" per $_cq_group"
        for _cq_spec in "${_cq_aggs[@]}"; do
            IFS=, read -r -a _cq_specs <<< "$_cq_spec"
            for _cq_item in "${_cq_specs[@]}"; do
                [[ -n "$_cq_item" ]] || continue
                _cq_name=; _cq_body=$_cq_item
                if [[ "$_cq_item" == *=* ]]; then _cq_name=${_cq_item%%=*}; _cq_body=${_cq_item#*=}; fi
                _cq_func=${_cq_body%%:*}; _cq_old=${_cq_body#*:}
                [[ "$_cq_old" == "$_cq_body" ]] && _cq_old=
                [[ -n "$_cq_name" ]] || _cq_name=$_cq_func${_cq_old:+_$_cq_old}
                _cq_type=any; _cq_unit=; _cq_desc=; _cq_producer=$_cq_default_producer
                if [[ -n "$_cq_old" && -n "${_cq_rows[$_cq_old]:-}" ]]; then
                    IFS=$_cq_sep read -r _cq_type _cq_unit _cq_desc _cq_source _cq_producer _cq_derived <<< "${_cq_rows[$_cq_old]}"
                fi
                case "$_cq_func" in
                count) _cq_type=int; _cq_unit=; _cq_desc="Number of records$_cq_suffix" ;;
                sum) _cq_label=Sum ;;
                avg) _cq_type=float; _cq_label=Average ;;
                min) _cq_label=Minimum ;;
                max) _cq_label=Maximum ;;
                first) _cq_label=First ;;
                last) _cq_label=Last ;;
                collect) _cq_type=array; _cq_unit=; _cq_label=Collection ;;
                *) return 1 ;;
                esac
                if [[ "$_cq_func" != count ]]; then
                    _cq_desc="$_cq_label of $_cq_old$_cq_suffix${_cq_desc:+ ($_cq_old: $_cq_desc)}"
                fi
                _cq_next+=("$_cq_name")
                _cq_new_rows[$_cq_name]="$_cq_type$_cq_sep$_cq_unit$_cq_sep$_cq_desc${_cq_sep}derived$_cq_sep$_cq_producer$_cq_sep$_cq_body"
            done
        done
        _cq_names=("${_cq_next[@]}"); _cq_rows=()
        for _cq_name in "${_cq_names[@]}"; do _cq_rows[$_cq_name]=${_cq_new_rows[$_cq_name]}; done
    fi
    if [[ -n "$_cq_select" ]]; then
        _cq_next=(); _cq_new_rows=()
        IFS=, read -r -a _cq_specs <<< "$_cq_select"
        for _cq_item in "${_cq_specs[@]}"; do
            [[ -n "$_cq_item" ]] || continue
            _cq_name=${_cq_item%%=*}; _cq_old=${_cq_item#*=}
            IFS=$_cq_sep read -r _cq_type _cq_unit _cq_desc _cq_source _cq_producer _cq_derived <<< "${_cq_rows[$_cq_old]:-"$_cq_sep$_cq_sep${_cq_sep}none$_cq_sep$_cq_sep"}"
            if [[ "$_cq_item" == *=* ]]; then _cq_source=derived; _cq_derived="renamed from $_cq_old"; fi
            _cq_next+=("$_cq_name")
            _cq_new_rows[$_cq_name]="$_cq_type$_cq_sep$_cq_unit$_cq_sep$_cq_desc$_cq_sep$_cq_source$_cq_sep$_cq_producer$_cq_sep$_cq_derived"
        done
        _cq_names=("${_cq_next[@]}"); _cq_rows=()
        for _cq_name in "${_cq_names[@]}"; do _cq_rows[$_cq_name]=${_cq_new_rows[$_cq_name]}; done
    fi
    return 0
}

# *Description*:
# Trace column lineage without executing stages. Emit JSONL or fill a hint map.
# *Params*:
# - `[--map ASSOCVAR] PIPELINE`: Map values are type/unit/description joined by US.
__bu_column_explain_pipeline()
{
    local _ce_map=
    if [[ "${1:-}" == --map ]]; then _ce_map=$2; shift 2; fi
    local _ce_pipeline=${1:-} _ce_stage _ce_cmd _ce_effect _ce_decl _ce_fields _ce_name
    local _ce_type _ce_unit _ce_desc _ce_source _ce_producer _ce_derived _ce_arg _ce_pos
    local -a _ce_stages=() _ce_words=() _ce_alias_words=() _ce_expanded=() _ce_names=()
    local -A _ce_rows=() _ce_seen=() _ce_declarations=()
    local -n _ce_out=${_ce_map:-_ce_rows}
    local -r _ce_sep=$'\x1f'
    __bu_column_split stages "$_ce_pipeline" _ce_stages || return 1
    ((${#_ce_stages[@]})) || return 1
    for _ce_stage in "${_ce_stages[@]}"; do
        __bu_column_split words "$_ce_stage" _ce_words || return 1
        ((${#_ce_words[@]})) || continue
        __bu_out_canonicalize_stage "${_ce_words[0]} "
        if [[ "$BU_CANONICAL_STAGE" == 'bu ' ]]; then _ce_words[0]=bu; fi
        if [[ "${_ce_words[0]}" != bu ]]; then _ce_words=(bu "${_ce_words[@]}"); fi
        _ce_seen=()
        while :; do
            _ce_cmd=${_ce_words[1]:-}
            if [[ -z "$_ce_cmd" || -z "${BU_COMMANDS[$_ce_cmd]:-}" || -n "${_ce_seen[$_ce_cmd]:-}" ]]; then
                bu_log_err "Cannot trace stage: $_ce_stage"; return 1
            fi
            _ce_seen[$_ce_cmd]=1
            [[ "${BU_COMMAND_PROPERTIES[$_ce_cmd,type]:-}" == alias ]] || break
            # An alias may itself declare a producer schema.
            [[ -n "${BU_OUT_PRODUCER_COLUMNS[bu $_ce_cmd]:-}" ]] && break
            [[ -n "${BU_OUT_PRODUCER_COLUMNS_FROM[bu $_ce_cmd]:-}" ]] && break
            __bu_column_split words "${BU_COMMANDS[$_ce_cmd]}" _ce_alias_words || return 1
            _ce_expanded=(bu); _ce_pos=2
            for _ce_arg in "${_ce_alias_words[@]}"; do
                case "$_ce_arg" in
                '{...}') _ce_expanded+=("${_ce_words[@]:_ce_pos}"); _ce_pos=${#_ce_words[@]} ;;
                '{}') _ce_expanded+=("${_ce_words[_ce_pos]:-}"); : $((_ce_pos+=1)) ;;
                '{?}') ((_ce_pos < ${#_ce_words[@]})) || break ;;
                *) _ce_expanded+=("$_ce_arg") ;;
                esac
            done
            _ce_words=("${_ce_expanded[@]}")
        done
        # A schema that depends on the stage's arguments (Columns-From) wins
        # over the static declarations, whatever the stage's effect.
        if __bu_column_from_stage "$_ce_cmd" _ce_decl "${_ce_words[@]:2}"; then
            _ce_names=(); _ce_rows=()
            while IFS=$_ce_sep read -r _ce_name _ce_type _ce_unit _ce_desc; do
                [[ -n "$_ce_name" ]] || continue
                [[ -v _ce_rows[$_ce_name] ]] || _ce_names+=("$_ce_name")
                _ce_rows[$_ce_name]="$_ce_type$_ce_sep$_ce_unit$_ce_sep$_ce_desc${_ce_sep}declared${_ce_sep}bu $_ce_cmd$_ce_sep"
            done <<< "$_ce_decl"
            continue
        fi
        __bu_out_stage_effect_lookup "$_ce_cmd" _ce_effect
        case "$_ce_effect" in
        producer|transform)
            _ce_names=(); _ce_rows=(); _ce_declarations=()
            _ce_decl=
            __bu_column_for_command "bu $_ce_cmd" _ce_decl || true
            while IFS=$_ce_sep read -r _ce_name _ce_type _ce_unit _ce_desc; do
                [[ -n "$_ce_name" ]] || continue
                _ce_declarations[$_ce_name]="$_ce_type$_ce_sep$_ce_unit$_ce_sep$_ce_desc"
            done <<< "$_ce_decl"
            _ce_fields=${BU_OUT_PRODUCER_FIELDS[bu $_ce_cmd]:-}
            if [[ -z "$_ce_fields" && -f "${BU_COMMANDS[$_ce_cmd]}" ]]; then
                __bu_command_fields_get "${BU_COMMANDS[$_ce_cmd]}" _ce_fields
            fi
            read -r -a _ce_names <<< "$_ce_fields"
            for _ce_name in "${_ce_names[@]}"; do
                if [[ -v _ce_declarations[$_ce_name] ]]; then
                    _ce_rows[$_ce_name]="${_ce_declarations[$_ce_name]}${_ce_sep}declared${_ce_sep}bu $_ce_cmd$_ce_sep"
                else
                    _ce_rows[$_ce_name]="$_ce_sep$_ce_sep${_ce_sep}none${_ce_sep}bu $_ce_cmd$_ce_sep"
                fi
            done
            ;;
        query) __bu_column_query _ce_words _ce_names _ce_rows || return 1 ;;
        passthrough|sink|consume) ;;
        *) bu_log_err "Cannot trace stage: $_ce_stage"; return 1 ;;
        esac
    done
    if [[ -n "$_ce_map" ]]; then
        _ce_out=()
        for _ce_name in "${_ce_names[@]}"; do
            IFS=$_ce_sep read -r _ce_type _ce_unit _ce_desc _ce_source _ce_producer _ce_derived <<< "${_ce_rows[$_ce_name]}"
            _ce_out[$_ce_name]="$_ce_type$_ce_sep$_ce_unit$_ce_sep$_ce_desc"
        done
    else
        {
            for _ce_name in "${_ce_names[@]}"; do printf '%s\x1f%s\n' "$_ce_name" "${_ce_rows[$_ce_name]}"; done
        } | jq -Rc 'split("\u001f") | {column:.[0],type:.[1],unit:.[2],description:.[3],source:.[4],producer:.[5],derived:.[6]}'
        return $?
    fi
    return 0
}

# *Description*:
# Attach lineage hints to field candidates before ANSI wrapping; preserve BU_RET.
__bu_column_attach_hints()
{
    local _ch_base=$1 _ch_candidate _ch_name _ch_type _ch_unit _ch_desc
    local -a _ch_saved=("${BU_RET[@]}")
    local -A _ch_map=()
    shift
    [[ -n "$BU_OUT_COMPLETE_PRODUCER" ]] || return 0
    __bu_column_explain_pipeline --map _ch_map "$BU_OUT_COMPLETE_PRODUCER" 2>/dev/null || true
    for _ch_candidate in "$@"; do
        _ch_name=${_ch_candidate##*,}; _ch_name=${_ch_name#.}
        if [[ -n "$_ch_name" && -n "${_ch_map[$_ch_name]:-}" ]]; then
            IFS=$'\x1f' read -r _ch_type _ch_unit _ch_desc <<< "${_ch_map[$_ch_name]}"
            if [[ -n "$_ch_desc" ]]; then
                BU_COMPREPLY_METADATA[_ch_base]="$_ch_type${_ch_unit:+ $_ch_unit}  $_ch_desc"
            fi
        fi
        : $((_ch_base+=1))
    done
    BU_RET=("${_ch_saved[@]}")
    return 0
}

# *Description*:
# Render declared columns for autohelp, padded by the widest column name.
__bu_column_help()
{
    local _ch_rows='' _ch_name _ch_type _ch_unit _ch_desc _ch_width=0 _ch_from= _ch_cmd=
    __bu_out_canonicalize_stage "$1"
    _ch_cmd=${BU_CANONICAL_STAGE#bu }
    _ch_cmd=${_ch_cmd%%[[:space:]]*}
    __bu_column_from_function "$_ch_cmd" _ch_from
    if ! __bu_column_for_command "$1" _ch_rows; then
        [[ -n "$_ch_from" ]] || return 0
        printf '\n%s\n\n%s%s\n' "${BU_TPUT_BOLD}OUTPUT COLUMNS${BU_TPUT_RESET}" "$2" \
            "Depend on the arguments: $BU_CLI_COMMAND_NAME get-column '$_ch_cmd ARGS...'"
        return 0
    fi
    while IFS=$'\x1f' read -r _ch_name _ch_type _ch_unit _ch_desc; do
        ((${#_ch_name} > _ch_width)) && _ch_width=${#_ch_name}
    done <<< "$_ch_rows"
    printf '\n%s\n\n' "${BU_TPUT_BOLD}OUTPUT COLUMNS${BU_TPUT_RESET}"
    while IFS=$'\x1f' read -r _ch_name _ch_type _ch_unit _ch_desc; do
        printf '%s%s%-*s%s  %s%s%s  %s\n' "$2" "$BU_TPUT_BOLD" "$_ch_width" "$_ch_name" "$BU_TPUT_RESET" "$BU_TPUT_GREY" "$_ch_type${_ch_unit:+ $_ch_unit}" "$BU_TPUT_RESET" "$_ch_desc"
    done <<< "$_ch_rows"
    if [[ -n "$_ch_from" ]]; then
        printf '\n%s%s\n' "$2" "Which of these appear depends on the arguments: $BU_CLI_COMMAND_NAME get-column '$_ch_cmd ARGS...'"
    fi
}
