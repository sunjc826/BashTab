# MARK: Repo registry
# A repo IS a location (kind dir) plus git identity — not a parallel registry.
# All repo extras live in BU_LOCATION_PROPERTIES under [name,repo_*] keys.
#
#   bu_repo_register myrepo --path '$HOME/src/myrepo' --gh-slug owner/repo
#   bu get-repo               # fleet dashboard
#   bu get-pull-request myrepo --state open

# *Description*:
# Register a repo: delegates to bu_location_register (kind dir, tagged
# "repo") and stores git extras in the same property table.
#
# *Params*:
# - `$1`: name
# - `--path`/`--resolver`/`--alias`/`--description`/`--on-enter`: forwarded
# - `--param-*`     forwarded; any explicit option suppresses default worktrees
# - `--tags CSV`    extra tags appended after "repo"
# - `--remote NAME` (default origin)
# - `--gh-host HOST`
# - `--gh-slug OWNER/REPO`
# - `--default-branch BR`
#
# *Returns*:
# - BU_RET: storage key
# - 0 on success, 1 on error
bu_repo_register()
{
    local name=$1
    shift
    local custom_param=false
    local remote=origin
    local gh_host=
    local gh_slug=
    local default_branch=
    local -a loc_args=()
    local -a extra_tags=()
    while (($#))
    do
        case "$1" in
        --kind)
            bu_log_err "bu_repo_register: --kind is not allowed (repos are always dir)"
            return 1
            ;;
        --param-*)         custom_param=true; loc_args+=("$1" "$2"); shift 2 ;;
        --path)            loc_args+=(--path "$2"); shift 2 ;;
        --resolver)        loc_args+=(--resolver "$2"); shift 2 ;;
        --alias)           loc_args+=(--alias "$2"); shift 2 ;;
        --description)     loc_args+=(--description "$2"); shift 2 ;;
        --on-enter)        loc_args+=(--on-enter "$2"); shift 2 ;;
        --tags)            extra_tags+=("$2"); shift 2 ;;
        --remote)          remote=$2; shift 2 ;;
        --gh-host)         gh_host=$2; shift 2 ;;
        --gh-slug)         gh_slug=$2; shift 2 ;;
        --default-branch)  default_branch=$2; shift 2 ;;
        *) bu_log_err "bu_repo_register: unknown option[$1]"; return 1 ;;
        esac
    done

    local tags="repo"
    if ((${#extra_tags[@]} > 0))
    then
        tags+=",${extra_tags[*]}"
    fi

    if ! "$custom_param"; then
        loc_args+=(--param-complete __bu_repo_worktree_complete --param-resolve __bu_repo_worktree_resolve --param-hint worktree)
    fi
    bu_location_register "$name" --kind dir --tags "$tags" "${loc_args[@]}" || return 1
    local key=$BU_RET

    BU_LOCATION_PROPERTIES[$key,repo_remote]=$remote
    BU_LOCATION_PROPERTIES[$key,repo_gh_host]=$gh_host
    BU_LOCATION_PROPERTIES[$key,repo_gh_slug]=$gh_slug
    BU_LOCATION_PROPERTIES[$key,repo_default_branch]=$default_branch
    return 0
}

# *Description*:
# Names of registered repos (newline on stdout).
bu_repo_names()
{
    bu_location_names --tag repo --no-stubs
}

# ```md
# Read live worktree records into caller-local arrays. NUL-delimited porcelain
# preserves spaces, newlines, and git's otherwise quoted path characters.
# ```
__bu_repo_worktree_list()
{
    local key=$1 base= field= path= branch= primary= short=
    bu_location_resolve "$key" --kind dir || return 1
    base=${BU_RET[0]}
    if ! git -C "$base" rev-parse --git-dir >/dev/null 2>&1; then
        bu_log_err "repo[$key] is not a git repo: $base"
        return 1
    fi
    # Check command status before reading via process substitution.
    git -C "$base" worktree list --porcelain >/dev/null 2>&1 || return 1
    while IFS= read -r -d '' field; do
        case "$field" in
        'worktree '*) path=${field#worktree }; branch= ;;
        'branch '*) branch=${field#branch refs/heads/} ;;
        '')
            [[ -n "$path" ]] || continue
            [[ -n "$primary" ]] || primary=${path##*/}
            short=${path##*/}
            short=${short#"$primary-worktree-"}
            wt_paths+=("$path")
            wt_names+=("$short")
            wt_branches+=("$branch")
            # -ef compares device/inode, including symlinked registrations.
            if [[ "$path" -ef "$base" ]]; then
                wt_self+=(true)
            else
                wt_self+=(false)
            fi
            ;;
        esac
    done < <(git -C "$base" worktree list --porcelain -z)
    return 0
}

# ```md
# FN KEY -> BU_RET values, omitting the registered directory itself.
# ```
__bu_repo_worktree_complete()
{
    local -a wt_paths=() wt_names=() wt_branches=() wt_self=()
    local i
    __bu_repo_worktree_list "$1" || return 1
    BU_RET=()
    for i in "${!wt_paths[@]}"; do
        [[ "${wt_self[$i]}" == true ]] || BU_RET+=("${wt_names[$i]}")
    done
    return 0
}

# ```md
# FN KEY VALUE -> BU_RET directory. Prefer short names, then basenames,
# then branch names across the whole list (not per-record precedence).
# ```
__bu_repo_worktree_resolve()
{
    local key=$1 value=$2 i mode candidate
    local -a wt_paths=() wt_names=() wt_branches=() wt_self=()
    __bu_repo_worktree_list "$key" || return 1
    for mode in short basename branch; do
        for i in "${!wt_paths[@]}"; do
            case "$mode" in
            short) candidate=${wt_names[$i]} ;;
            basename) candidate=${wt_paths[$i]##*/} ;;
            branch) candidate=${wt_branches[$i]} ;;
            esac
            if [[ "$candidate" == "$value" ]]; then
                BU_RET=("${wt_paths[$i]}")
                return 0
            fi
        done
    done
    bu_log_err "repo[$key] has no worktree[$value]; available: ${wt_names[*]}"
    return 1
}

# *Description*:
# Resolve a repo location and verify it is a git worktree.
#
# *Params*:
# - `$1`: name or alias
#
# *Returns*:
# - BU_RET: repo path
# - 0 on success, 1 if missing or not a worktree
bu_repo_resolve()
{
    local name=$1
    bu_location_resolve "$name" --kind dir || return 1
    local path=${BU_RET[0]}
    if ! git -C "$path" rev-parse --git-dir >/dev/null 2>&1
    then
        bu_log_err "location[$name] is not a git worktree: $path"
        return 1
    fi
    return 0
}

# *Description*:
# Parse a git remote URL into owner/repo and host.
#
# *Params*:
# - `$1`: remote URL (ssh://, scp-like, or http(s))
#
# *Returns*:
# - BU_RET: owner/repo
# - BU_RET_MAP[host]: host
# - 0 on success, 1 if unparseable
bu_repo_parse_remote_url()
{
    local url=$1
    BU_RET=()
    BU_RET_MAP[host]=

    local rest hostpart host path

    # scp-like: [user@]host:owner/repo[.git]  (no scheme)
    if [[ "$url" != *'://'* && "$url" == *':'* ]]
    then
        hostpart=${url%%:*}
        path=${url#*:}
        hostpart=${hostpart##*@}
        path=${path%.git}
        if [[ "$path" == */* && "$path" != */*/* ]]
        then
            BU_RET_MAP[host]=$hostpart
            BU_RET=("$path")
            return 0
        fi
        bu_log_err "Could not parse remote URL: $url"
        return 1
    fi

    # ssh://[user@]host[:port]/owner/repo[.git]
    if [[ "$url" == ssh://* ]]
    then
        rest=${url#ssh://}
        hostpart=${rest%%/*}
        path=${rest#*/}
        hostpart=${hostpart##*@}
        hostpart=${hostpart%%:*}
        path=${path%.git}
        if [[ "$path" == */* && "$path" != */*/* ]]
        then
            BU_RET_MAP[host]=$hostpart
            BU_RET=("$path")
            return 0
        fi
        bu_log_err "Could not parse remote URL: $url"
        return 1
    fi

    # http(s)://host/owner/repo[.git]
    if [[ "$url" == http://* || "$url" == https://* ]]
    then
        rest=${url#*://}
        host=${rest%%/*}
        path=${rest#*/}
        host=${host%%:*}
        path=${path%.git}
        if [[ "$path" == */* && "$path" != */*/* ]]
        then
            BU_RET_MAP[host]=$host
            BU_RET=("$path")
            return 0
        fi
        bu_log_err "Could not parse remote URL: $url"
        return 1
    fi

    bu_log_err "Could not parse remote URL: $url"
    return 1
}

# *Description*:
# Resolve a repo's GitHub slug (OWNER/REPO) and host.
#
# *Params*:
# - `$1`: name or alias
#
# *Returns*:
# - BU_RET: owner/repo
# - BU_RET_MAP[host]: effective host (registered --gh-host beats derived)
# - 0 on success, 1 if no slug/remote is available
bu_repo_resolve_slug()
{
    local name=$1
    __bu_location_resolve_key "$name" --kind dir || return 1
    local key=$BU_RET

    local gh_host=${BU_LOCATION_PROPERTIES[$key,repo_gh_host]:-}
    local gh_slug=${BU_LOCATION_PROPERTIES[$key,repo_gh_slug]:-}

    # Registered slug wins outright.
    if [[ -n "$gh_slug" ]]
    then
        BU_RET=("$gh_slug")
        BU_RET_MAP[host]=${gh_host:-github.com}
        return 0
    fi

    # Session cache: already derived this slug (and host) once.
    local cached=${BU_LOCATION_PROPERTIES[$key,repo_gh_slug_cached]:-}
    if [[ -n "$cached" ]]
    then
        BU_RET=("$cached")
        BU_RET_MAP[host]=${gh_host:-${BU_LOCATION_PROPERTIES[$key,repo_gh_host_cached]:-github.com}}
        return 0
    fi

    bu_location_resolve "$name" --kind dir || return 1
    local path=${BU_RET[0]}
    local remote=${BU_LOCATION_PROPERTIES[$key,repo_remote]:-origin}

    local url
    url=$(git -C "$path" remote get-url "$remote" 2>/dev/null) || {
        bu_log_err "repo[$name] has no remote[$remote] (register --gh-slug to override)"
        return 1
    }

    bu_repo_parse_remote_url "$url" || return 1
    local derived_host=${BU_RET_MAP[host]:-github.com}
    local slug=$BU_RET

    BU_LOCATION_PROPERTIES[$key,repo_gh_slug_cached]=$slug
    BU_LOCATION_PROPERTIES[$key,repo_gh_host_cached]=$derived_host

    BU_RET=("$slug")
    BU_RET_MAP[host]=${gh_host:-$derived_host}
    return 0
}
