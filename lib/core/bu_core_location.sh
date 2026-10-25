# MARK: Named location registry
# PowerShell-flavored named directory targets ("goto shortcuts").
#
# A location is a name → target, where the target is either a lazily-expanded
# path expression (`--path '$MY_PROJECT_DIR/build'`, single-quoted by the
# caller) or a resolver function (`--resolver FN`, the escape hatch for
# computed/validated targets).  Entries are registered by core code, module
# preinits, and the user-local file (see bu_location_source_local_file).
#
# The repo registry (bu_core_repo.sh) layers on top: a repo IS a location
# plus git identity, stored in the same property table.

# These three arrays are re-initialized every time the entrypoint sources
# this file (bu_core_location.sh is intentionally sourced WITHOUT --__bu-once
# so re-activation starts from a clean slate before preinits and the local
# file re-register everything).
declare -A -g BU_LOCATION_REGISTRY=()      # name -> kind (dir|file|multi)
declare -A -g BU_LOCATION_PROPERTIES=()    # [name,path] [name,resolver] [name,description]
                                           # [name,tags] [name,on_enter] [name,source]
                                           # [name,param_complete] [name,param_resolve] [name,param_hint]
                                           # [name,repo_*] (see bu_core_repo.sh)
declare -A -g BU_LOCATION_ALIASES=()       # alias -> canonical name/key

# First BASH_SOURCE frame OUTSIDE the location/repo registry core files.
# Used to record provenance ([name,source]) so a delegating wrapper (e.g.
# bu_repo_register) records the actual registrant (module preinit, local file).
#
# @set BU_RET source file path
# bash-ide parse-func-sig
__bu_location_provenance()
{
    local i file base
    for (( i = 0; i < ${#BASH_SOURCE[@]}; i++ ))
    do
        file=${BASH_SOURCE[$i]}
        base=${file##*/}
        [[ "$base" == bu_core_location.sh || "$base" == bu_core_repo.sh ]] && continue
        BU_RET=("$file")
        return 0
    done
    BU_RET=("${BASH_SOURCE[0]}")
    return 0
}

# True when `tag` appears in the comma-separated tags CSV.
# bash-ide parse-func-sig
__bu_location_tag_match()
{
    local tags_csv=$1
    local tag=$2
    local ifs=$IFS t
    IFS=','
    for t in $tags_csv
    do
        [[ "$t" == "$tag" ]] && { IFS=$ifs; return 0; }
    done
    IFS=$ifs
    return 1
}

# Reject path expressions that could become code execution at resolve time.
# A path typo must never run a command.  Plain $VAR / ${VAR} expansion is
# allowed; command substitution ($(...) and backticks) and shell metachars
# are not.
#
# @returns
# - 0 if safe, 1 if the expression contains a forbidden sequence
# bash-ide parse-func-sig
__bu_location_validate_path_expr()
{
    local expr=$1
    if [[ "$expr" == *'$('* || "$expr" == *'`'* || "$expr" == *';'* \
       || "$expr" == *'&'* || "$expr" == *'|'* || "$expr" == *'<'* \
       || "$expr" == *'>'* || "$expr" == *$'\n'* ]]
    then
        return 1
    fi
    return 0
}

# Expand a stored path expression at resolve time.  The expansion is
# double-quoted so a value containing spaces stays ONE path.  A leading
# `~`/`~/` is converted to `$HOME` first (quoting suppresses tilde
# expansion).  Validation (__bu_location_validate_path_expr) is the security
# boundary: only $VAR/parameter expansion survives to this point.
#
# @arg $1 {string} expr unexpanded path expression
# @set BU_RET expanded path (scalar)
#
# @returns
# - 0 on success, 1 if expansion fails
__bu_location_expand_path()
{
    local expr=$1
    case "$expr" in
    '~')   expr='$HOME' ;;
    '~/')  expr='$HOME/' ;;
    '~/'*) expr='$HOME'/"${expr#~/}" ;;
    esac

    local resolved
    if ! eval "resolved=\"$expr\"" 2>/dev/null
    then
        bu_log_err "Could not expand location path expression: $1"
        return 1
    fi
    BU_RET=("$resolved")
    return 0
}

# Resolve a name (and optional kind) to its storage key in BU_LOCATION_REGISTRY.
# Alias-aware.  A --kind mismatch is an error unless a kind:name sibling of the
# requested kind exists.
#
# @arg $1 {string} name name or alias
# @option --kind KIND: (optional)
# @set BU_RET storage key
# @set BU_RET_MAP[param] value after the first @ (empty for bare names or NAME@)
#
# @returns
# - 0 on success, 1 on unknown name / kind mismatch / invalid parameter use
# bash-ide parse-func-sig
__bu_location_resolve_key()
{
    local name=$1
    shift
    local kind=
    while (($#))
    do
        case "$1" in
        --kind) kind=$2; shift 2 ;;
        *) shift ;;
        esac
    done

    local head=${name%%@*}
    local param=
    BU_RET_MAP[param]=
    [[ "$name" == *@* ]] && param=${name#*@}
    if [[ -z "$head" ]]; then
        bu_log_err "Unknown location[$name] (list with: bu get-location-registry)"
        return 1
    fi
    local canonical=${BU_LOCATION_ALIASES[$head]:-$head}
    local key=$canonical
    local entry_kind=${BU_LOCATION_REGISTRY[$key]:-}

    if [[ -z "$entry_kind" ]]
    then
        bu_log_err "Unknown location[$name] (list with: bu get-location-registry)"
        return 1
    fi

    if [[ -n "$kind" && "$entry_kind" != "$kind" ]]
    then
        local sibling="$kind:$canonical"
        if [[ -n "${BU_LOCATION_REGISTRY[$sibling]:-}" ]]
        then
            key=$sibling
        else
            bu_log_err "location[$name] is kind[$entry_kind], not [$kind]"
            return 1
        fi
    fi

    if [[ -n "$param" && -z "${BU_LOCATION_PROPERTIES[$key,param_resolve]:-}" ]]; then
        bu_log_err "location[$head] takes no parameter (given [$name])"
        return 1
    fi
    if [[ -z "$param" && -z "${BU_LOCATION_PROPERTIES[$key,path]:-}" && -z "${BU_LOCATION_PROPERTIES[$key,resolver]:-}" ]]; then
        bu_log_err "location[$head] needs a parameter: $head@<${BU_LOCATION_PROPERTIES[$key,param_hint]:-value}>"
        return 1
    fi
    BU_RET_MAP[param]=$param
    BU_RET=("$key")
    return 0
}

# Map a name or alias head to its canonical storage key, stripping @VALUE.
# Empty heads return the input unchanged. Identity for
# non-aliases and for names that are not registered at all.
#
# Unlike `__bu_location_resolve_key`, this NEVER errors: embedders use it to
# probe properties of a name that may legitimately be unregistered (e.g.
# `BU_LOCATION_PROPERTIES[$canonical,tags]` before deciding whether to
# resolve). An unknown name maps to itself so the subsequent property lookup
# simply yields empty rather than emitting an "Unknown location" error.
#
# @arg $1 {string} name name or alias
# @set BU_RET canonical storage key (identity for non-aliases/unknown names)
#
# @returns
# - Always 0
# bash-ide parse-func-sig
bu_location_canonical_name()
{
    local name=$1
    local head=${name%%@*}
    if [[ -z "$head" ]]; then
        BU_RET=$name
    else
        BU_RET=${BU_LOCATION_ALIASES[$head]:-$head}
    fi
    return 0
}

# Clear an entry's registry slot, all its properties, and every alias that
# points at it.  Used by overwrite and unregister so stale resolver/path/alias
# data never lingers.
#
# @arg $1 {string} key storage key
# bash-ide parse-func-sig
__bu_location_clear_entry()
{
    local key=$1
    local prop
    for prop in path resolver description tags on_enter source param_complete param_resolve param_hint \
                repo_remote repo_gh_host repo_gh_slug repo_default_branch \
                repo_gh_slug_cached repo_gh_host_cached
    do
        unset "BU_LOCATION_PROPERTIES[$key,$prop]"
    done
    unset "BU_LOCATION_REGISTRY[$key]"
    local a
    for a in "${!BU_LOCATION_ALIASES[@]}"
    do
        if [[ "${BU_LOCATION_ALIASES[$a]}" == "$key" ]]
        then
            unset "BU_LOCATION_ALIASES[$a]"
        fi
    done
}

# Register a named location.
#
# @arg $1 {string} name name
# @option --kind dir|file|multi: (default dir)
# @option --path 'EXPR': unexpanded path expression (mutually exclusive with --resolver)
# @option --resolver FN: resolver function (returns BU_RET scalar/array)
# @option --param-complete FN: KEY -> BU_RET values (dir only, paired with --param-resolve)
# @option --param-resolve FN: KEY VALUE -> BU_RET directory, nonzero on failure
# @option --param-hint TEXT: value description for parameter-only errors
# @option --alias A: repeatable
# @option --description TEXT
# @option --tags CSV
# @option --on-enter FN: dir kind only
# @set BU_RET storage key (name, or kind:name sibling)
#
# @returns
# - 0 on success, 1 on invalid registration
# bash-ide parse-func-sig
bu_location_register()
{
    local name=$1
    shift
    local kind=dir
    local path_expr=
    local resolver=
    local param_complete= param_resolve= param_hint=
    local a
    local on_enter=
    local description=
    local tags=
    local -a aliases=()
    while (($#))
    do
        case "$1" in
        --kind)        kind=$2; shift 2 ;;
        --path)        path_expr=$2; shift 2 ;;
        --resolver)    resolver=$2; shift 2 ;;
        --param-complete) param_complete=$2; shift 2 ;;
        --param-resolve) param_resolve=$2; shift 2 ;;
        --param-hint) param_hint=$2; shift 2 ;;
        --alias)       aliases+=("$2"); shift 2 ;;
        --description) description=$2; shift 2 ;;
        --tags)        tags=$2; shift 2 ;;
        --on-enter)    on_enter=$2; shift 2 ;;
        *) bu_log_err "bu_location_register: unknown option[$1]"; return 1 ;;
        esac
    done

    if [[ -z "$name" ]]
    then
        bu_log_err "bu_location_register: empty name"
        return 1
    fi

    for a in "$name" "${aliases[@]}"; do
        if [[ -z "$a" || "$a" == *@* ]]; then
            bu_log_err "bu_location_register: name/alias [$a] must be nonempty and cannot contain @"
            return 1
        fi
    done
    if [[ -n "$param_complete" && -z "$param_resolve" || -z "$param_complete" && -n "$param_resolve" ]]; then
        bu_log_err "bu_location_register[$name]: --param-complete and --param-resolve must be given together"
        return 1
    fi
    if [[ "$kind" != dir && -n "$param_complete$param_resolve$param_hint" ]]; then
        bu_log_err "bu_location_register[$name]: parameters are only valid for kind dir"
        return 1
    fi

    case "$kind" in
    dir|file|multi) ;;
    *) bu_log_err "bu_location_register: invalid kind[$kind] for [$name]"; return 1 ;;
    esac

    if [[ -n "$path_expr" && -n "$resolver" ]]
    then
        bu_log_err "bu_location_register[$name]: --path and --resolver are mutually exclusive"
        return 1
    fi
    if [[ -z "$path_expr" && -z "$resolver" && -z "$param_resolve" ]]
    then
        bu_log_err "bu_location_register[$name]: a base target (--path or --resolver) or parameter pair is required"
        return 1
    fi

    if [[ -n "$on_enter" && "$kind" != dir ]]
    then
        bu_log_err "bu_location_register[$name]: --on-enter is only valid for kind dir"
        return 1
    fi

    if [[ -n "$path_expr" ]] && ! __bu_location_validate_path_expr "$path_expr"
    then
        bu_log_err "bu_location_register[$name]: path expression contains forbidden characters (\$(, backtick, ;, &, |, <, >, newline): $path_expr"
        return 1
    fi

    # Same name + same kind → overwrite.  Different kind → kind:name sibling.
    local existing_kind=${BU_LOCATION_REGISTRY[$name]:-}
    local key=$name
    if [[ -n "$existing_kind" && "$existing_kind" != "$kind" ]]
    then
        key="$kind:$name"
    fi

    if [[ -n "${BU_LOCATION_REGISTRY[$key]:-}" ]]
    then
        __bu_location_clear_entry "$key"
    fi

    BU_LOCATION_REGISTRY[$key]=$kind
    BU_LOCATION_PROPERTIES[$key,param_complete]=$param_complete
    BU_LOCATION_PROPERTIES[$key,param_resolve]=$param_resolve
    BU_LOCATION_PROPERTIES[$key,param_hint]=$param_hint
    BU_LOCATION_PROPERTIES[$key,path]=$path_expr
    BU_LOCATION_PROPERTIES[$key,resolver]=$resolver
    BU_LOCATION_PROPERTIES[$key,description]=$description
    BU_LOCATION_PROPERTIES[$key,tags]=$tags
    BU_LOCATION_PROPERTIES[$key,on_enter]=$on_enter

    __bu_location_provenance
    BU_LOCATION_PROPERTIES[$key,source]=$BU_RET

    for a in "${aliases[@]}"
    do
        BU_LOCATION_ALIASES[$a]=$key
    done

    BU_RET=("$key")
    return 0
}

# Resolve a location to its target path(s).
#
# @arg $1 {string} name name or alias
# @option --kind KIND: (optional)
# @option --no-verify: skip the existence check (dir/file kinds)
# @set BU_RET resolved path (scalar for dir/file, array for multi)
#
# @returns
# - 0 on success, 1 on error
# bash-ide parse-func-sig
bu_location_resolve()
{
    local name=$1
    shift
    local kind=
    local no_verify=false
    while (($#))
    do
        case "$1" in
        --kind)      kind=$2; shift 2 ;;
        --no-verify) no_verify=true; shift ;;
        *) bu_log_err "bu_location_resolve: unknown option[$1]"; return 1 ;;
        esac
    done

    __bu_location_resolve_key "$name" ${kind:+--kind "$kind"} || return 1
    local key=$BU_RET
    local entry_kind=${BU_LOCATION_REGISTRY[$key]}

    local resolver=${BU_LOCATION_PROPERTIES[$key,resolver]:-}
    local param=${BU_RET_MAP[param]:-}
    if [[ -n "$param" ]]; then
        BU_RET=()
        "${BU_LOCATION_PROPERTIES[$key,param_resolve]}" "$key" "$param" || return 1
    elif [[ -n "$resolver" ]]
    then
        BU_RET=()
        if ! "$resolver" "$name"
        then
            return 1
        fi
    else
        local path_expr=${BU_LOCATION_PROPERTIES[$key,path]:-}
        __bu_location_expand_path "$path_expr" || return 1
    fi

    if ! "$no_verify"
    then
        local src=${BU_LOCATION_PROPERTIES[$key,source]:-?}
        case "$entry_kind" in
        dir)
            if [[ ! -d "${BU_RET[0]}" ]]
            then
                bu_log_err "location[$name] directory missing[${BU_RET[0]}] (registered in $src)"
                return 1
            fi
            ;;
        file)
            if [[ ! -f "${BU_RET[0]}" ]]
            then
                bu_log_err "location[$name] file missing[${BU_RET[0]}] (registered in $src)"
                return 1
            fi
            ;;
        esac
    fi

    return 0
}

# *Description*:
# List location names (newline on stdout — the completion feed).
# Kind-qualified siblings list under their plain name, deduplicated.
#
# *Params*:
# - `--kind K`        filter by kind
# - `--tag T`         filter by tag (comma-separated CSV)
# - `--with-aliases`  also include alias names
# - `--no-stubs`      omit family stubs in bare mode
# - final word       NAME@ queries live values; bare mode never calls completers
bu_location_names()
{
    local kind= tag= word= head= key= k= display= a= value=
    local with_aliases=false no_stubs=false
    local -a out=()
    while (($#)); do
        case "$1" in
        --kind) kind=$2; shift 2 ;;
        --tag) tag=$2; shift 2 ;;
        --with-aliases) with_aliases=true; shift ;;
        --no-stubs) no_stubs=true; shift ;;
        *) word=$1; shift ;;
        esac
    done

    if [[ "$word" == *@* ]]; then
        head=${word%%@*}
        [[ -n "$head" ]] || return 0
        key=${BU_LOCATION_ALIASES[$head]:-$head}
        k=${BU_LOCATION_REGISTRY[$key]:-}
        if [[ -n "$kind" && "$k" != "$kind" && -n "${BU_LOCATION_REGISTRY[$kind:$key]:-}" ]]; then
            key=$kind:$key
            k=${BU_LOCATION_REGISTRY[$key]}
        fi
        [[ -n "$k" && ( -z "$kind" || "$kind" == "$k" ) ]] || return 0
        [[ -z "$tag" ]] || __bu_location_tag_match "${BU_LOCATION_PROPERTIES[$key,tags]:-}" "$tag" || return 0
        [[ -n "${BU_LOCATION_PROPERTIES[$key,param_complete]:-}" ]] || return 0
        BU_RET=()
        # Completion failures are silent; resolution still reports diagnostics.
        "${BU_LOCATION_PROPERTIES[$key,param_complete]}" "$key" 2>/dev/null || return 0
        for value in "${BU_RET[@]}"; do
            printf '%s@%s\n' "$head" "$value"
        done
        return 0
    fi

    for key in "${!BU_LOCATION_REGISTRY[@]}"; do
        k=${BU_LOCATION_REGISTRY[$key]}
        [[ -n "$kind" && "$k" != "$kind" ]] && continue
        [[ -z "$tag" ]] || __bu_location_tag_match "${BU_LOCATION_PROPERTIES[$key,tags]:-}" "$tag" || continue
        display=$key
        [[ "$key" == *:* ]] && display=${key#*:}
        if [[ -n "${BU_LOCATION_PROPERTIES[$key,path]:-}${BU_LOCATION_PROPERTIES[$key,resolver]:-}" ]]; then
            out+=("$display")
        fi
        if ! "$no_stubs" && [[ -n "${BU_LOCATION_PROPERTIES[$key,param_complete]:-}" ]]; then
            out+=("$display@")
        fi
        if "$with_aliases"; then
            for a in "${!BU_LOCATION_ALIASES[@]}"; do
                [[ "${BU_LOCATION_ALIASES[$a]}" == "$key" ]] || continue
                if [[ -n "${BU_LOCATION_PROPERTIES[$key,path]:-}${BU_LOCATION_PROPERTIES[$key,resolver]:-}" ]]; then
                    out+=("$a")
                fi
                if ! "$no_stubs" && [[ -n "${BU_LOCATION_PROPERTIES[$key,param_complete]:-}" ]]; then
                    out+=("$a@")
                fi
            done
        fi
    done
    if ((${#out[@]} > 0)); then
        printf '%s\n' "${out[@]}" | sort -u
    fi
    return 0
}

# Resolve a dir location, cd into it, and run its on-enter callback.  The
# goto primitive; callers must be source-dispatch so the cd takes effect.
#
# @arg $1 {string} name name or alias
# @option --no-enter-hook: skip the on-enter callback
# bash-ide parse-func-sig
bu_location_enter()
{
    local name=$1
    shift
    local no_enter_hook=false
    while (($#))
    do
        case "$1" in
        --no-enter-hook) no_enter_hook=true; shift ;;
        *) bu_log_err "bu_location_enter: unknown option[$1]"; return 1 ;;
        esac
    done

    __bu_location_resolve_key "$name" --kind dir || return 1
    local key=$BU_RET

    bu_location_resolve "$name" --kind dir || return 1
    local dir=${BU_RET[0]}

    cd "$dir" || return 1

    if ! "$no_enter_hook"
    then
        local hook=${BU_LOCATION_PROPERTIES[$key,on_enter]:-}
        if [[ -n "$hook" ]]
        then
            if ! "$hook" "$name" "$dir"
            then
                bu_log_warn "on-enter hook[$hook] failed for location[$name]"
            fi
        fi
    fi
    return 0
}

# Remove a location entry, its properties, and all aliases pointing at it.
# bash-ide parse-func-sig
bu_location_unregister()
{
    local name=$1
    if [[ -z "${BU_LOCATION_REGISTRY[$name]:-}" ]]
    then
        bu_log_warn "location[$name] is not registered"
        return 1
    fi
    __bu_location_clear_entry "$name"
    return 0
}

# Source the user-local location file.  Missing file is not an error and this
# never returns non-zero.  Called from bu_entrypoint.sh AFTER module preinits
# so user registrations override code defaults (last write wins).
# bash-ide parse-func-sig
bu_location_source_local_file()
{
    local file=${BU_LOCATION_LOCAL_FILE:-"$BU_DIR"/config/bu_locations_local.sh}
    if [[ ! -f "$file" ]]
    then
        return 0
    fi
    bu_scope_push
    bu_scoped_set +e
    source "$file" || bu_log_warn "Failed to source location file: $file"
    bu_scope_pop
    return 0
}
