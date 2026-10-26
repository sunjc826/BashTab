# bash-ide source=./bu_core_base.sh

# MARK: --help / man-page parsing for option descriptions
# Extracts option descriptions from a command's --help or man page, caching
# results so the fzf preview pane can show option descriptions for external
# command completions.
#
# Strategy registry: maps command name → parse strategy.
# Strategies:
#   gnu    – run --help, parse GNU-style "  -o, --option  DESC" lines
#   usage  – run --help, parse "usage: cmd [-o] [--option ARG]" synopsis
#            lines for bare option tokens (no descriptions available)
#   man    – run "man <cmd>", parse OPTIONS section (future)
#
# When a command has no registered strategy and no Fig spec, strategies are
# tried in order: gnu, then usage as fallback.  The first that yields results wins.
declare -A -g __BU_HELP_PARSE_STRATEGY=()

# Directory for cached parse results.  Derived from BU_CACHE_DIR at source
# time; callers can override.
declare -g __BU_HELP_PARSE_CACHE_DIR="${BU_CACHE_DIR}/help-parse"
bu_mkdir "$__BU_HELP_PARSE_CACHE_DIR"

# Global associative array populated by strategy functions.  Declared here
# so that all strategies (which may be called before __bu_help_parse_get
# runs its declare) write to an associative array, not an indexed one.
declare -A -g __BU_HELP_PARSE_CACHE_MAP=()

# Register a parse strategy for a command.  Modules and preinit scripts
# should call this to declare how a particular command's help should be
# parsed.
#
# @arg $1 {string} cmd Command name (e.g. "git", "docker")
# @arg $2 {string} strategy Strategy: gnu, usage, or man
#
# @example
# ```bash
# bu_register_help_strategy git usage
# bu_register_help_strategy find man
# ```
# bash-ide parse-func-sig
bu_register_help_strategy()
{
    local -r cmd=$1
    local -r strategy=$2
    case "$strategy" in
    gnu|usage|man) ;;
    *)
        bu_log_err "Unknown help parse strategy[$strategy]. Expected: gnu, usage, man"
        return 1
        ;;
    esac
    __BU_HELP_PARSE_STRATEGY[$cmd]=$strategy
}

# Normalize a command name into a cache key (path → basename, slashes → dashes).
#
# @arg $1 {string} key Command name (e.g. "git", "docker-compose", "/usr/bin/tar")
# @stdout Cache-safe key
# bash-ide parse-func-sig
__bu_help_parse_cache_key()
{
    local key=$1
    key=${key##*/}
    key=${key//\//-}
    printf '%s' "$key"
}

# ═══════════════════════════════════════════════════════════════════════
# Strategy: gnu — parse "  -o, --option  DESC" lines from --help
# ═══════════════════════════════════════════════════════════════════════

# bash-ide parse-func-sig
__bu_help_parse_gnu()
{
    local -r cmd=$1
    local help_text

    if ! help_text=$("$cmd" --help 2>/dev/null) || [[ -z "$help_text" ]]
    then
        return 1
    fi

    local -A parsed=()
    local current_opt=
    local current_desc=
    local in_options_section=false
    local saw_options_header=false

    while IFS= read -r line
    do
        # Detect OPTIONS section header
        if [[ "$line" =~ ^[[:space:]]*OPTIONS?$ || "$line" =~ ^[A-Z][A-Z[:space:]]+OPTIONS?$ ]]
        then
            saw_options_header=true
            in_options_section=true
            continue
        fi

        # End of OPTIONS section: a new all-caps section header
        if "$in_options_section" && [[ "$line" =~ ^[[:space:]]*[A-Z][A-Z[:space:]]{2,}$ ]] && [[ ! "$line" =~ OPTIONS? ]]
        then
            in_options_section=false
            continue
        fi

        "$saw_options_header" && ! "$in_options_section" && continue

        local opt_tokens=()
        local desc_rest=

        # GNU style: -o, --option[=VAL]  DESC  or  --option[=VAL]  DESC
        if [[ "$line" =~ ^[[:space:]]+(-[a-zA-Z0-9?],?[[:space:]]*)?(--?[a-zA-Z0-9][-a-zA-Z0-9]*)([=][[:space:]]*[A-Za-z0-9_-]*)?[[:space:]]{2,}(.*) ]]
        then
            local short_opt=${BASH_REMATCH[1]}
            short_opt=${short_opt//,/}
            short_opt=${short_opt## }
            short_opt=${short_opt%% }
            local long_opt=${BASH_REMATCH[2]}
            desc_rest=${BASH_REMATCH[4]}

            [[ -n "$short_opt" ]] && opt_tokens+=("$short_opt")
            opt_tokens+=("$long_opt")
        elif [[ "$line" =~ ^[[:space:]]+(-[a-zA-Z0-9?])[[:space:]]+[A-Z][A-Z_]*[[:space:]]{2,}(.*) ]]
        then
            # BSD style: -o  ARG  DESC
            opt_tokens+=("${BASH_REMATCH[1]}")
            desc_rest=${BASH_REMATCH[2]}
        elif [[ "$line" =~ ^[[:space:]]+(--?[a-zA-Z0-9][-a-zA-Z0-9]*)[[:space:]]{2,}(.*) ]]
        then
            # Simple: --option  DESC or -o  DESC
            opt_tokens+=("${BASH_REMATCH[1]}")
            desc_rest=${BASH_REMATCH[2]}
        fi

        if ((${#opt_tokens[@]}))
        then
            if [[ -n "$current_opt" ]]
            then
                for _o in $current_opt; do
                    parsed[$_o]=${current_desc#"${current_desc%%[![:space:]]*}"}
                done
            fi
            current_opt="${opt_tokens[*]}"
            current_desc=$desc_rest
        elif [[ -n "$current_opt" ]] && [[ "$line" =~ ^[[:space:]]{4,}([^ ].*) ]]
        then
            current_desc+=" ${BASH_REMATCH[1]}"
        else
            if [[ -n "$current_opt" ]]
            then
                for _o in $current_opt; do
                    parsed[$_o]=${current_desc#"${current_desc%%[![:space:]]*}"}
                done
                current_opt=
                current_desc=
            fi
        fi
    done <<< "$help_text"

    if [[ -n "$current_opt" ]]
    then
        for _o in $current_opt; do
            parsed[$_o]=${current_desc#"${current_desc%%[![:space:]]*}"}
        done
    fi

    ((${#parsed[@]})) || return 1

    local _opt
    for _opt in "${!parsed[@]}"; do
        __BU_HELP_PARSE_CACHE_MAP[$_opt]=${parsed[$_opt]}
    done
    return 0
}

# ═══════════════════════════════════════════════════════════════════════
# Strategy: usage — parse "usage: cmd [-o] [--option ARG]" lines
# Extracts option tokens from bracket-delimited synopsis lines.
# No descriptions are available; options get an empty-string value.
# ═══════════════════════════════════════════════════════════════════════

# bash-ide parse-func-sig
__bu_help_parse_usage()
{
    local -r cmd=$1
    local help_text

    if ! help_text=$("$cmd" --help 2>/dev/null) || [[ -z "$help_text" ]]
    then
        return 1
    fi

    local -A parsed=()
    local usage_lines=()

    # Collect all usage/synopsis lines
    while IFS= read -r line
    do
        # Match "usage:" or "Usage:" prefix
        if [[ "$line" =~ ^[[:space:]]*[Uu]sage: ]]
        then
            usage_lines+=("$line")
        elif ((${#usage_lines[@]})) && [[ "$line" =~ ^[[:space:]]{6,}[^A-Za-z] ]]
        then
            # Continuation line: indented continuation of the usage block
            usage_lines+=("$line")
        else
            # Stop collecting once we hit non-continuation after usage block
            ((${#usage_lines[@]})) && break
        fi
    done <<< "$help_text"

    ((${#usage_lines[@]})) || return 1

    # Join all usage lines, strip "usage: cmd" prefix, then extract option
    # tokens from bracket-delimited groups like [-o], [--option ARG], etc.
    local joined="${usage_lines[*]}"
    # Strip "usage: " prefix and the command name
    joined=${joined#*[Uu]sage: }
    joined=${joined#"$cmd"}   # strip the command name itself
    joined=${joined## }       # trim leading space

    # Extract tokens that look like options from bracket-enclosed groups.
    # We process the joined text character by character to handle nested
    # brackets and alternation (|).
    local token=
    local -a tokens=()
    local in_bracket=false
    local in_angle=false
    local i ch

    for (( i = 0; i < ${#joined}; i++ ))
    do
        ch=${joined:i:1}
        case "$ch" in
        '[')
            in_bracket=true
            token=
            ;;
        ']')
            in_bracket=false
            # Process the accumulated token inside brackets
            if [[ -n "$token" ]]
            then
                # Split on | for alternation: [-v | --version]
                local -a alts=()
                local _alt _ifs=$IFS
                IFS='|'
                for _t in $token; do
                    _t=${_t## }
                    _t=${_t%% }
                    [[ -n "$_t" ]] && alts+=("$_t")
                done
                IFS=$_ifs
                for _alt in "${alts[@]}"
                do
                    # Only keep tokens starting with - (skip ARG placeholders
                    # like <path>, <name>, etc.)
                    if [[ "$_alt" == -* ]]
                    then
                        # Strip trailing =VALUE from --option=VALUE
                        _alt=${_alt%%=*}
                        # Strip [...] suffix from --option[=VALUE]
                        _alt=${_alt%%[*}
                        # Trim leading/trailing whitespace
                        _alt=${_alt## }
                        _alt=${_alt%% }
                        parsed[$_alt]=
                    fi
                done
            fi
            ;;
        '<')
            in_angle=true
            ;;
        '>')
            in_angle=false
            ;;
        *)
            "$in_bracket" && ! "$in_angle" && token+=$ch
            ;;
        esac
    done

    ((${#parsed[@]})) || return 1

    local _opt
    for _opt in "${!parsed[@]}"; do
        __BU_HELP_PARSE_CACHE_MAP[$_opt]=
    done
    return 0
}

# ═══════════════════════════════════════════════════════════════════════
# Strategy: fig — extract options from a Fig completion spec JSON file
# Reads the spec __bu_fig_spec_path finds (BU_FIG_SPEC_DIRS, then the
# bundled fig_specs/build/<cmd>.json), walks the subcommand tree using the
# provided tokens, and extracts option descriptions.
# ═══════════════════════════════════════════════════════════════════════

# bash-ide parse-func-sig
__bu_help_parse_fig()
{
    local -r cmd=$1
    shift
    local -a subpath=("$@")

    __bu_fig_spec_path "$cmd" || return 1
    local spec_path=$BU_RET

    # Walk the subcommand tree to find the right node, then extract
    # option definitions as name→description pairs.
    local tokens_json
    if ((${#subpath[@]}))
    then
        tokens_json=$("$BU_OUT_JQ" -cn --args '$ARGS.positional' -- "${subpath[@]}" 2>/dev/null) || return 1
    else
        tokens_json='[]'
    fi

    local entries_json
    entries_json=$("$BU_OUT_JQ" -c --argjson tokens "$tokens_json" '
    def walk($node; $tokens):
        if ($tokens | length) == 0 then $node
        else
            ($node.subcommands // []) as $subs
            | ($subs | map(select(.name == $tokens[0]))) as $matches
            | if ($matches | length) > 0 then
                walk($matches[0]; $tokens[1:])
              else $node end
        end;

    walk(.; $tokens)
    | [.options[]? // empty
       | {key: (.name | if type == "array" then .[] else . end),
          desc: (.description // "")}]
    | .[]
    ' "$spec_path" 2>/dev/null) || return 1

    [[ "$entries_json" != '[]' && -n "$entries_json" ]] || return 1

    # Parse jq output: one JSON object per option name
    while IFS= read -r entry
    do
        local _key _desc
        _key=$("$BU_OUT_JQ" -r '.key' <<<"$entry" 2>/dev/null)
        _desc=$("$BU_OUT_JQ" -r '.desc' <<<"$entry" 2>/dev/null)
        [[ -n "$_key" ]] && __BU_HELP_PARSE_CACHE_MAP[$_key]=$_desc
    done <<< "$entries_json"

    ((${#__BU_HELP_PARSE_CACHE_MAP[@]})) || return 1
    return 0
}

# ═══════════════════════════════════════════════════════════════════════
# Strategy: man — parse "man <cmd>" OPTIONS section (stub / future)
# ═══════════════════════════════════════════════════════════════════════

# bash-ide parse-func-sig
__bu_help_parse_man()
{
    local -r cmd=$1
    # Future: run "man <cmd> 2>/dev/null | col -bx" and parse the OPTIONS
    # section using man-page heuristics.
    return 1
}

# ═══════════════════════════════════════════════════════════════════════
# Dispatcher + caching layer
# ═══════════════════════════════════════════════════════════════════════

# Resolve the effective strategy for a command.  Checks:
# 1. Explicit registration (__BU_HELP_PARSE_STRATEGY)
# 2. Fig spec existence (if spec file exists, use fig)
# 3. Default to gnu (with usage fallback)
#
# @arg $1 {string} cmd Command name
# @stdout Strategy name (fig, gnu, usage, or man), or empty
# bash-ide parse-func-sig
__bu_help_parse_resolve_strategy()
{
    local -r cmd=$1

    # Explicit registration takes priority
    if [[ -n "${__BU_HELP_PARSE_STRATEGY[$cmd]:-}" ]]
    then
        printf '%s' "${__BU_HELP_PARSE_STRATEGY[$cmd]}"
        return 0
    fi

    # Check for Fig spec
    if __bu_fig_spec_path "$cmd"
    then
        printf 'fig'
        return 0
    fi

    # No explicit registration and no Fig spec — don't enrich.
    # Defaulting to gnu is too dangerous: --help can be destructive
    # or hang on arbitrary binaries.
    return 1
}

# Compute the cache hash for a command + strategy combination.  We hash the
# strategy name together with the command's help output so that switching
# strategies for a command invalidates the old cache.
#
# @arg $1 {string} cmd Command to run
# @arg $2 {string} strategy Strategy name (gnu, usage, man)
# @arg $3 {var} _out Output variable for the hash (empty on failure)
# bash-ide parse-func-sig
__bu_help_parse_hash()
{
    local -r cmd=$1
    local -r strategy=$2
    local -n _out=$3
    _out=

    local help_text
    case "$strategy" in
    fig)
        __bu_fig_spec_path "$cmd" || return 1
        local spec_path=$BU_RET
        # Hash the spec file path + mtime so updates invalidate cache
        local _mtime
        _mtime=$(stat -c %Y "$spec_path" 2>/dev/null || stat -f %m "$spec_path" 2>/dev/null)
        _out=$(printf '%s\n%s' "$spec_path" "${_mtime:-0}" | sha256sum 2>/dev/null | cut -d' ' -f1)
        ;;
    gnu|usage)
        help_text=$("$cmd" --help 2>/dev/null) || return 1
        ;;
    man)
        help_text=$(man "$cmd" 2>/dev/null | col -bx 2>/dev/null) || return 1
        ;;
    *) return 1 ;;
    esac

    if [[ "$strategy" != fig ]]
    then
        [[ -z "$help_text" ]] && return 1
        _out=$(printf '%s\n%s' "$strategy" "$help_text" | sha256sum 2>/dev/null | cut -d' ' -f1)
    fi

    [[ -n "$_out" ]]
}

# Run the appropriate strategy for a command and populate the global
# associative array __BU_HELP_PARSE_CACHE_MAP.
#
# @arg $1 {string} cmd Command to run (e.g. "grep", "git")
#
# @returns
# - 0 on success, 1 if no strategy produced results
# - Populates __BU_HELP_PARSE_CACHE_MAP assoc: option token → description
__bu_help_parse_run()
{
    local -r cmd=$1
    shift
    local -a subpath=("$@")
    local -r cache_key=$(__bu_help_parse_cache_key "$cmd")
    local -r strategy=$(__bu_help_parse_resolve_strategy "$cmd") || return 1
    # Include subpath in cache key for strategies that support subcommands
    local _subpath_key
    if ((${#subpath[@]}))
    then
        printf -v _subpath_key '---%s' "${subpath[@]}"
    else
        _subpath_key=
    fi
    local -r cache_file="$__BU_HELP_PARSE_CACHE_DIR/${cache_key}${_subpath_key}.${strategy}"

    # ── Cache hit check ──
    local help_hash
    if __bu_help_parse_hash "$cmd" "$strategy" help_hash && [[ -n "$help_hash" ]]
    then
        local cached_hash
        if cached_hash=$(head -1 "$cache_file" 2>/dev/null) && [[ "$cached_hash" == "$help_hash" ]]
        then
            local _line _opt _desc
            while IFS= read -r _line
            do
                [[ "$_line" == "$help_hash" ]] && continue
                _opt=${_line%%$'\t'*}
                _desc=${_line#*$'\t'}
                __BU_HELP_PARSE_CACHE_MAP[$_opt]=$_desc
            done < "$cache_file"
            return 0
        fi
    else
        return 1
    fi

    # ── Cache miss: run the strategy ──
    local -a strategies_to_try=("$strategy")
    # If fig: also try gnu as supplement (many Fig specs only have short
    # option names, missing long forms like --all for ls).  If gnu:
    # also try usage as fallback.
    if [[ "$strategy" == fig ]]
    then
        strategies_to_try+=(gnu)
    fi
    # If no explicit registration and fig is NOT the strategy,
    # also try usage as fallback after gnu
    if [[ "${strategy}" != fig && -z "${__BU_HELP_PARSE_STRATEGY[$cmd]:-}" ]]
    then
        strategies_to_try+=(usage)
    fi

    local _strat _ok=false
    for _strat in "${strategies_to_try[@]}"
    do
        case "$_strat" in
        fig)   __bu_help_parse_fig   "$cmd" "${subpath[@]}" && _ok=true ;;
        gnu)   __bu_help_parse_gnu   "$cmd" && _ok=true ;;
        usage) __bu_help_parse_usage "$cmd" && _ok=true ;;
        man)   __bu_help_parse_man   "$cmd" && _ok=true ;;
        esac
        # Continue to next strategy to merge results (fig + gnu fills gaps)
    done

    "$_ok" || return 1

    # ── Write cache (use the primary strategy name, not the last run) ──
    local _result_cache_file="$__BU_HELP_PARSE_CACHE_DIR/${cache_key}${_subpath_key}.${strategy}"
    __bu_help_parse_hash "$cmd" "$strategy" help_hash || return 1
    if ((${#__BU_HELP_PARSE_CACHE_MAP[@]}))
    then
        bu_mkdir "$__BU_HELP_PARSE_CACHE_DIR"
        {
            printf -- '%s\n' "$help_hash"
            local _opt
            for _opt in "${!__BU_HELP_PARSE_CACHE_MAP[@]}"
            do
                printf '%s\t%s\n' "$_opt" "${__BU_HELP_PARSE_CACHE_MAP[$_opt]}"
            done | sort
        } > "$_result_cache_file"
    fi

    return 0
}

# Get option descriptions for a command.  Runs --help / man on first call
# and caches the result; subsequent calls return instantly from cache.
#
# @arg $1 {string} cmd Command name or path (e.g. "grep", "/usr/bin/tar", "git")
# @arg $2 {var} _out Name of an associative array to populate (nameref)
#
# @returns
# - 0 on success (array may be empty if no options found)
# - 1 if no strategy produced results or command not found
# - Populates the nameref array: option token → description
__bu_help_parse_get()
{
    local -r cmd=$1
    local -n _out=$2
    shift 2 2>/dev/null || shift $#
    _out=()

    command -v "$cmd" &>/dev/null || return 1

    __BU_HELP_PARSE_CACHE_MAP=()
    __bu_help_parse_run "$cmd" "$@" || return 1

    local _opt
    for _opt in "${!__BU_HELP_PARSE_CACHE_MAP[@]}"
    do
        _out[$_opt]=${__BU_HELP_PARSE_CACHE_MAP[$_opt]}
    done
    return 0
}

# Enrich BU_COMPREPLY_METADATA with option descriptions for external
# commands, using Fig specs when available or --help parsing as fallback.
# Called during fzf autocomplete binding after completions are generated.
#
# @arg $1 {var} _comps COMPREPLY array of completion candidates
# @arg $2 {var} _meta BU_COMPREPLY_METADATA array to enrich
# @arg $@ {string} args... Full command-line tokens (e.g. "git" "commit" "-m")
#
# @returns
# - Sets BU_RET to "true" if preview should be shown, "false" otherwise
#
# @notes
# - The first token ($3) is the command name.  Remaining tokens before the
#   cursor (typically all but the last) are used to resolve the subcommand
#   path for Fig specs.
# bash-ide parse-func-sig
__bu_help_enrich_preview()
{
    local -n _comps=$1
    local -n _meta=$2
    shift 2
    local -a _tokens=("$@")
    BU_RET=false

    local _cmd=${_tokens[0]:-}
    [[ -n "$_cmd" ]] || return 0

    # Only process external commands (not BashTab built-ins and not the
    # CLI entry point itself — bu/activate are functions, not binaries)
    [[ -n "${BU_COMMANDS[$_cmd]:-}" ]] && return 0
    [[ "$_cmd" == "$BU_CLI_COMMAND_NAME" ]] && return 0

    # Only process if there are completions that look like options
    local has_options=false
    local _c
    for _c in "${_comps[@]}"
    do
        [[ "$_c" == -* ]] && { has_options=true; break; }
    done
    "$has_options" || return 0

    # Determine subcommand path: tokens between cmd and the cursor word
    # (the last token is the word being completed, skip it)
    local -a _subpath=()
    local _i
    for ((_i = 1; _i < ${#_tokens[@]} - 1; _i++))
    do
        [[ "${_tokens[_i]}" != -* ]] && _subpath+=("${_tokens[_i]}")
    done

    # Get parsed help — fig strategy gets the subcommand tokens
    declare -A _help_opts=()
    __bu_help_parse_get "$_cmd" _help_opts "${_subpath[@]}" 2>/dev/null || return 0

    ((${#_help_opts[@]})) || return 0

    # Build a lookup-friendly key set: space-padded so we can use [[ $set == *" key "* ]]
    local _key_set=" "
    local _k
    for _k in "${!_help_opts[@]}"; do
        _key_set+="$_k "
    done

    local _i _desc _clean _prefix _found
    local _enriched=false
    for ((_i = 0; _i < ${#_comps[@]}; _i++))
    do
        _c=${_comps[$_i]}
        _c="${_c%"${_c##*[![:space:]]}"}"  # rtrim — fig completions may have trailing spaces
        [[ "$_c" != -* ]] && continue

        _desc=
        _found=false

        # Exact match
        if [[ "$_key_set" == *" $_c "* ]]
        then
            _desc=${_help_opts[$_c]}
            _found=true
        # Strip trailing = for --option=ARG
        elif [[ "$_c" == *=* ]]
        then
            local _stripped=${_c%%=*}
            if [[ "$_key_set" == *" $_stripped "* ]]
            then
                _desc=${_help_opts[$_stripped]}
                _found=true
            fi
        fi

        # Prefix shortening: only for single-dash options (-verbose → -v).
        # Long options (--*) must match exactly or via = stripping above.
        if ! "$_found" && [[ "$_c" == -[^-]* ]]
        then
            _prefix=$_c
            while [[ ${#_prefix} -gt 1 ]]
            do
                if [[ "$_key_set" == *" $_prefix "* ]]
                then
                    _desc=${_help_opts[$_prefix]}
                    _found=true
                    break
                fi
                _prefix=${_prefix::-1}
            done
        fi

        if "$_found"
        then
            _clean=${_desc#"${_desc%%[![:space:]]*}"}
            if [[ -n "$_clean" ]]
            then
                if ((${#_meta[_i]} == 0))
                then
                    _meta[_i]="${BU_TPUT_GREY}${_clean}${BU_TPUT_RESET}"
                else
                    _meta[_i]+=" | ${BU_TPUT_GREY}${_clean}${BU_TPUT_RESET}"
                fi
            fi
            _enriched=true
        fi
    done

    "$_enriched" && BU_RET=true
}
