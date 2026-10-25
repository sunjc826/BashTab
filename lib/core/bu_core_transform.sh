# bash-ide source=./bu_core_base.sh
# bash-ide source=./bu_core_autocomplete.sh

# MARK: Command-line transforms
#
# A transform is a `match -> replace` rewrite rule over READLINE_LINE.
# Both directions are just transforms — "unwrap" is a transform whose match
# recognizes an already-wrapped line — so there is no toggle and no detection
# heuristic.  See docs/line_transforms.md for the spec.

# Decompose a template into literal and placeholder segments.
#
# @arg $1 {string} template template string
# @set BU_RET array of segments, each `LIT<text>` or `PH:<kind>` where kind is
#   one of `line`, `prog`, `args`, or `unknown:<inner>`
# bash-ide parse-func-sig
__bu_transform_tokenize()
{
    local -r template=$1
    local -a segs=()
    local rest=$template
    local pre inner kind
    while [[ "$rest" == *'{'*'}'* ]]
    do
        pre=${rest%%'{'*}
        [[ -n "$pre" ]] && segs+=("LIT$pre")
        rest=${rest#"$pre"}
        rest=${rest#'{'}
        inner=${rest%%'}'*}
        rest=${rest#"$inner"}
        rest=${rest#'}'}
        if [[ "$inner" == line || "$inner" == all ]]
        then
            kind=line
        elif [[ "$inner" == prog ]]
        then
            kind=prog
        elif [[ "$inner" == args || "$inner" == @ || "$inner" == ... ]]
        then
            kind=args
        else
            kind="unknown:$inner"
        fi
        segs+=("PH:$kind")
    done
    [[ -n "$rest" ]] && segs+=("LIT$rest")
    BU_RET=("${segs[@]}")
}

# Return 0 if the template places a known placeholder inside quotes
# (the only invalid quoting — literals may contain quotes freely).
#
# @arg $1 {string} template template string
# bash-ide parse-func-sig
__bu_transform_quoted_placeholder_present()
{
    local -r template=$1
    local -i i n=${#template}
    local in_sq=0 in_dq=0 ch inner
    for ((i = 0; i < n; i++))
    do
        ch=${template:i:1}
        if ((in_dq))
        then
            if [[ "$ch" == '"' ]]
            then
                in_dq=0
            elif [[ "$ch" == '{' ]]
            then
                inner=${template:i+1}
                inner=${inner%%'}'*}
                case "$inner" in
                line|all|prog|args|@|...) return 0 ;;
                esac
            fi
            continue
        elif ((in_sq))
        then
            if [[ "$ch" == "'" ]]
            then
                in_sq=0
            elif [[ "$ch" == '{' ]]
            then
                inner=${template:i+1}
                inner=${inner%%'}'*}
                case "$inner" in
                line|all|prog|args|@|...) return 0 ;;
                esac
            fi
            continue
        fi
        case "$ch" in
        "'") in_sq=1 ;;
        '"') in_dq=1 ;;
        esac
    done
    return 1
}

# Validate a transform rule against the grammar from docs/line_transforms.md.
#
# @arg $1 {string} name transform name (for error messages)
# @arg $2 {string} match match template
# @arg $3 {string} replace replace template
#
# @returns
# - 0 if valid, 1 otherwise (with a bu_log_err explaining why)
__bu_transform_validate()
{
    local -r name=$1 match=$2 replace=$3
    local -r quiet=${4:-}
    _transform_err()
    {
        [[ -n "$quiet" ]] || bu_log_err "$1"
    }
    local -a msegs=() rsegs=()
    __bu_transform_tokenize "$match"
    msegs=("${BU_RET[@]}")
    __bu_transform_tokenize "$replace"
    rsegs=("${BU_RET[@]}")

    # Rule 1: whitelist.
    local s
    for s in "${msegs[@]}" "${rsegs[@]}"
    do
        if [[ "$s" == PH:unknown:* ]]
        then
            _transform_err "transform[$name]: unknown placeholder {${s#PH:unknown:}}"
            return 1
        fi
    done

    # Rule 4: no placeholder inside quotes.
    if __bu_transform_quoted_placeholder_present "$match" || __bu_transform_quoted_placeholder_present "$replace"
    then
        _transform_err "transform[$name]: placeholder inside quotes"
        return 1
    fi

    # Count placeholders per side.
    local m_line=0 m_prog=0 m_args=0
    local r_line=0 r_prog=0 r_args=0
    for s in "${msegs[@]}"
    do
        case "$s" in
        PH:line) m_line=$((m_line + 1)) ;;
        PH:prog) m_prog=$((m_prog + 1)) ;;
        PH:args) m_args=$((m_args + 1)) ;;
        esac
    done
    for s in "${rsegs[@]}"
    do
        case "$s" in
        PH:line) r_line=$((r_line + 1)) ;;
        PH:prog) r_prog=$((r_prog + 1)) ;;
        PH:args) r_args=$((r_args + 1)) ;;
        esac
    done

    # Rule 2: arity.
    if ((m_line > 1 || m_prog > 1 || m_args > 1 || r_line > 1 || r_prog > 1 || r_args > 1))
    then
        _transform_err "transform[$name]: at most one of each placeholder per side"
        return 1
    fi
    if ((m_line > 0 && m_args > 0)) || ((r_line > 0 && r_args > 0))
    then
        _transform_err "transform[$name]: {line} and {args} are mutually exclusive on a side"
        return 1
    fi

    # Rule 3: position (match side). A token rest must be trailing; a raw
    # {line} must be trailing when combined with {prog} (mixed mode).
    local m_last=${msegs[${#msegs[@]} - 1]:-}
    if ((m_args > 0)) && [[ "$m_last" != PH:args ]]
    then
        _transform_err "transform[$name]: {args} must be trailing in the match template"
        return 1
    fi
    if ((m_line > 0 && m_prog > 0)) && [[ "$m_last" != PH:line ]]
    then
        _transform_err "transform[$name]: {line} must be trailing when combined with {prog}"
        return 1
    fi

    # Rule 5: replace-side references must be available from the match side.
    for s in "${rsegs[@]}"
    do
        case "$s" in
        PH:line)
            ((m_line > 0)) || { _transform_err "transform[$name]: replace uses {line} but match does not capture it"; return 1; }
            ;;
        PH:prog)
            ((m_prog > 0 || m_line > 0)) || { _transform_err "transform[$name]: replace uses {prog} but match does not capture {prog}/{line}"; return 1; }
            ;;
        PH:args)
            ((m_args > 0 || m_line > 0)) || { _transform_err "transform[$name]: replace uses {args} but match does not capture {args}/{line}"; return 1; }
            ;;
        esac
    done

    return 0
}

# Strip the first N whitespace-delimited tokens from a line, returning the
# raw remainder (interior spacing preserved; leading whitespace dropped).
#
# @arg $1 {string} line line
# @arg $2 {string} n number of tokens to strip
# @set BU_RET raw remainder
# bash-ide parse-func-sig
__bu_transform_raw_rest_after_tokens()
{
    local -r line=$1 n=$2
    local rest=${line#"${line%%[![:space:]]*}"}
    local -i i
    for ((i = 0; i < n; i++))
    do
        if [[ "$rest" == *[[:space:]]* ]]
        then
            rest=${rest#*[[:space:]]}
        else
            rest=
        fi
    done
    BU_RET=$rest
}

# String-mode match: `P {line} S` with {line} the only placeholder.
# bash-ide parse-func-sig
__bu_transform_match_string()
{
    local -r template=$1 line=$2
    local -n _caps=$3
    local -a segs=()
    __bu_transform_tokenize "$template"
    segs=("${BU_RET[@]}")
    local prefix= suffix= s seen_ph=0
    for s in "${segs[@]}"
    do
        case "$s" in
        PH:line)
            seen_ph=1
            ;;
        LIT*)
            if ((seen_ph))
            then
                suffix=${s#LIT}
            else
                prefix=${s#LIT}
            fi
            ;;
        esac
    done
    if [[ "$line" == "$prefix"* && "$line" == *"$suffix" ]]
    then
        local mid=${line#"$prefix"}
        mid=${mid%"$suffix"}
        _caps[line]=$mid
        return 0
    fi
    return 1
}

# Token-mode match: literal words + {prog} + optional trailing {args}.
# bash-ide parse-func-sig
__bu_transform_match_tokens()
{
    local -r template=$1 line=$2
    local -n _caps=$3
    local -a ttoks=() ltoks=()
    read -r -a ttoks <<< "$template"
    read -r -a ltoks <<< "$line"
    local -i i j=0
    for ((i = 0; i < ${#ttoks[@]}; i++))
    do
        case "${ttoks[i]}" in
        '{prog}')
            [[ -n "${ltoks[j]:-}" ]] || return 1
            _caps[prog]=${ltoks[j]}
            ((j++))
            ;;
        '{args}'|'{@}'|'{...}')
            _caps[args]=${ltoks[*]:j}
            j=${#ltoks[@]}
            ;;
        *)
            [[ "${ltoks[j]:-}" == "${ttoks[i]}" ]] || return 1
            ((j++))
            ;;
        esac
    done
    ((j == ${#ltoks[@]})) || return 1
    return 0
}

# Mixed-mode match: token-sequence + trailing raw {line}.
# bash-ide parse-func-sig
__bu_transform_match_mixed()
{
    local -r template=$1 line=$2
    local -n _caps=$3
    local -a segs=()
    __bu_transform_tokenize "$template"
    segs=("${BU_RET[@]}")
    local prefix= s
    for s in "${segs[@]}"
    do
        [[ "$s" == PH:line ]] && break
        case "$s" in
        LIT*)   prefix+="${s#LIT}" ;;
        PH:prog) prefix+='{prog}' ;;
        esac
    done
    local -a ptoks=() ltoks=()
    read -r -a ptoks <<< "$prefix"
    read -r -a ltoks <<< "$line"
    local -i i j=0
    for ((i = 0; i < ${#ptoks[@]}; i++))
    do
        case "${ptoks[i]}" in
        '{prog}')
            [[ -n "${ltoks[j]:-}" ]] || return 1
            _caps[prog]=${ltoks[j]}
            ((j++))
            ;;
        *)
            [[ "${ltoks[j]:-}" == "${ptoks[i]}" ]] || return 1
            ((j++))
            ;;
        esac
    done
    __bu_transform_raw_rest_after_tokens "$line" "$j"
    _caps[line]=$BU_RET
    return 0
}

# Match a line against a template, capturing placeholders.
#
# @arg $1 {string} template match template
# @arg $2 {string} line line
# @arg $3 {var} _caps nameref to an associative array to fill with captures
__bu_transform_match()
{
    local -r template=$1 line=$2
    local -n _caps=$3
    _caps=()
    local -a segs=()
    __bu_transform_tokenize "$template"
    segs=("${BU_RET[@]}")
    local has_line=0 has_prog=0 has_args=0 s
    for s in "${segs[@]}"
    do
        case "$s" in
        PH:line) has_line=1 ;;
        PH:prog) has_prog=1 ;;
        PH:args) has_args=1 ;;
        esac
    done
    if ((has_line && has_prog))
    then
        __bu_transform_match_mixed "$template" "$line" "$3"
    elif ((has_line))
    then
        __bu_transform_match_string "$template" "$line" "$3"
    else
        __bu_transform_match_tokens "$template" "$line" "$3"
    fi
}

# Render a replace template from captured placeholders.
#
# @arg $1 {string} template replace template
# @arg $2 {var} _caps nameref to the captures map
# @arg $3 {var} _out nameref to an output variable
# bash-ide parse-func-sig
__bu_transform_render()
{
    local -r template=$1
    local -n _caps=$2
    local -n _out=$3
    local -a segs=()
    __bu_transform_tokenize "$template"
    segs=("${BU_RET[@]}")
    local result= s
    for s in "${segs[@]}"
    do
        case "$s" in
        LIT*)    result+="${s#LIT}" ;;
        PH:line) result+="${_caps[line]:-}" ;;
        PH:prog) result+="${_caps[prog]:-}" ;;
        PH:args) result+="${_caps[args]:-}" ;;
        esac
    done
    _out=$result
}

# Apply a registered transform to a line.
#
# @arg $1 {string} name transform name
# @arg $2 {string} line input line
# @arg $3 string nameref to an output variable
#
# @returns
# - 0 on match, 1 on no match (output untouched on failure)
__bu_transform_apply()
{
    local -r name=$1 line=$2
    local match=${BU_LINE_TRANSFORM_PROPERTIES[$name,match]:-}
    local replace=${BU_LINE_TRANSFORM_PROPERTIES[$name,replace]:-}
    [[ -n "$match" && -n "$replace" ]] || return 1
    local -A _caps_map=()
    if ! __bu_transform_match "$match" "$line" _caps_map
    then
        return 1
    fi
    # Projections: when only {line} was captured, derive {prog}/{args}.
    if [[ -n "${_caps_map[line]+set}" ]]
    then
        if [[ -z "${_caps_map[prog]+set}" ]]
        then
            local -a _wtoks=()
            read -r -a _wtoks <<< "${_caps_map[line]}"
            _caps_map[prog]=${_wtoks[0]:-}
        fi
        if [[ -z "${_caps_map[args]+set}" ]]
        then
            local -a _wtoks=()
            read -r -a _wtoks <<< "${_caps_map[line]}"
            _caps_map[args]=${_wtoks[*]:1}
        fi
    fi
    __bu_transform_render "$replace" _caps_map "$3"
    return 0
}

# Readline binding: apply a named transform to the current line.
# No-op when the transform does not match.
#
# @arg $1 {string} name transform name
# bash-ide parse-func-sig
__bu_bind_transform()
{
    local -r name=$1
    local out
    if __bu_transform_apply "$name" "$READLINE_LINE" out
    then
        READLINE_LINE=$out
        READLINE_POINT=${#out}
    fi
}

# fzf preview helper for the transform selector.  Exported so fzf's preview
# subshell (a child bash) can call it.
__bu_bind_transform_preview_display()
{
    printf '%s\n' "$1"
}
export -f __bu_bind_transform_preview_display

# Readline binding: open an fzf selector over all registered transforms and
# apply the chosen one to the current line.
# bash-ide parse-func-sig
__bu_bind_transform_selector()
{
    command -v fzf &>/dev/null || return 0
    local -a names=()
    local key
    for key in "${!BU_LINE_TRANSFORM_PROPERTIES[@]}"
    do
        [[ "$key" == *,match ]] || continue
        names+=("${key%,match}")
    done
    ((${#names[@]})) || return 0

    local delim=$'\x01'
    local -a rows=()
    local name desc out
    for name in "${names[@]}"
    do
        desc=${BU_LINE_TRANSFORM_PROPERTIES[$name,description]:-}
        if __bu_transform_apply "$name" "$READLINE_LINE" out
        then
            rows+=("$name${delim}${desc}${delim}${out}")
        else
            rows+=("$name${delim}${desc}${delim}(no match)")
        fi
    done

    local selected
    selected=$(printf '%s\n' "${rows[@]}" | __bu_fzf \
        --exit-0 \
        --reverse \
        --height 20% --min-height 8 \
        --delimiter "$delim" \
        --nth 1,2 \
        --with-nth 1,2 \
        --preview '__bu_bind_transform_preview_display {3}' \
        --preview-window=:40:wrap \
        --header 'Command-line transforms')
    [[ -n "$selected" ]] || return 0
    selected=${selected%%"$delim"*}
    __bu_bind_transform "$selected"
}
