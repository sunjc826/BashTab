#!/usr/bin/env bash
# Pipeline: producer
# Dispatch: source
# Synopsis: Dashboard of registered git repositories
# Help-Topic: locations
# Fields: name path exists is_repo branch dirty ahead behind remote_url gh_slug gh_host default_branch
function __bu_bu_get_repo_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local -a names=()
local -a excludes=()
local no_status=false
local format=auto
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --no-status)# _FLAG
        # Skip slow status probes (branch/dirty/ahead/behind)
        no_status=true
        ;;
    --exclude)# PATTERN
        # Leave out repos matching this name or pattern (repeatable)
        bu_parse_positional $# --glob --stdout bu_repo_names stdout-- --hint "Repo name or pattern"
        excludes+=("${!shift_by}")
        ;;
    --format)# FORMAT
        # Output format
        bu_parse_positional $# --enum ${BU_OUT_FORMATS[@]} enum-- --hint "Output format"
        format=${!shift_by}
        ;;
    -h|--help)# _FLAG
        # Print help
        is_help=true
        ;;
    *)# NAME
        # Repo name or pattern (repeatable); none lists every repo. Patterns
        # are matched before the status probes run, so only matches pay for them.
        if bu_env_is_in_autocomplete && [[ "$1" != -* ]]
        then
            autocompletion=(--glob --stdout bu_repo_names stdout-- --hint "Repo name or pattern")
        fi
        if [[ "$1" == -* ]]
        then
            bu_parse_error_enum "$1"
        else
            names+=("$1")
        fi
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

if bu_env_is_in_autocomplete
then
    bu_autocomplete
    return 0
fi

if "$is_help"
then
    bu_autohelp \
        --description "
Dashboard of registered repositories (locations tagged 'repo'). Live fields
(branch, dirty, ahead/behind) are best-effort: a missing path still lists with
exists=false. Use --no-status to skip the slow git status/upstream probes.
" \
        --example "All repos" "" \
        --example "One repo" "myrepo" \
        --example "Service repos, except the legacy one" "'svc-*' --exclude svc-legacy" \
        --example "Skip status probes" "--no-status"
    return 0
fi

# Collect the repo keys to report. A plain name goes through the location
# resolver (aliases, qualified names); a pattern matches the display name or
# the qualified key of every repo.
local -a keys=()
local -a candidates=()
local -a patterns=()
local -A is_selected=()
local key k pattern
local exit_code=0
for key in "${!BU_LOCATION_REGISTRY[@]}"
do
    k=${BU_LOCATION_REGISTRY[$key]}
    [[ "$k" == dir ]] || continue
    __bu_location_tag_match "${BU_LOCATION_PROPERTIES[$key,tags]:-}" repo || continue
    candidates+=("$key")
done
for pattern in "${names[@]}"
do
    if bu_glob_has_wildcard "$pattern"
    then
        patterns+=("$pattern")
    elif __bu_location_resolve_key "$pattern" --kind dir 2>/dev/null
    then
        if [[ -z "${is_selected[$BU_RET]:-}" ]]
        then
            is_selected[$BU_RET]=1
            keys+=("$BU_RET")
        fi
    else
        bu_log_err "No repo named '$pattern'"
        exit_code=1
    fi
done
if ((${#patterns[@]})) || ! ((${#names[@]}))
then
    for key in "${candidates[@]}"
    do
        [[ -z "${is_selected[$key]:-}" ]] || continue
        if ((${#patterns[@]}))
        then
            bu_glob_match "${key#*:}" "${patterns[@]}" || bu_glob_match "$key" "${patterns[@]}" || continue
        fi
        is_selected[$key]=1
        keys+=("$key")
    done
fi
if ((${#excludes[@]}))
then
    candidates=("${keys[@]}")
    keys=()
    for key in "${candidates[@]}"
    do
        bu_glob_excludes "${key#*:}" "${excludes[@]}" || bu_glob_excludes "$key" "${excludes[@]}" || keys+=("$key")
    done
fi

{
    local display path exists is_repo branch dirty ahead behind remote_url gh_slug gh_host default_branch
    local remote src
    for key in "${keys[@]}"
    do
        display=$key
        [[ "$key" == *:* ]] && display=${key#*:}

        # Resolve the path best-effort (empty if resolver fails / env unset).
        path=
        bu_location_resolve "$key" --no-verify 2>/dev/null && path=${BU_RET[0]}

        exists=false
        is_repo=false
        branch=
        dirty=false
        ahead=
        behind=
        remote_url=
        gh_slug=
        gh_host=
        default_branch=${BU_LOCATION_PROPERTIES[$key,repo_default_branch]:-}

        if [[ -n "$path" && -d "$path" ]]
        then
            exists=true
            if git -C "$path" rev-parse --git-dir >/dev/null 2>&1
            then
                is_repo=true
                remote=${BU_LOCATION_PROPERTIES[$key,repo_remote]:-origin}
                remote_url=$(git -C "$path" remote get-url "$remote" 2>/dev/null || true)
                if ! "$no_status"
                then
                    branch=$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
                    if [[ -n "$(git -C "$path" status --porcelain --untracked-files=no 2>/dev/null)" ]]
                    then
                        dirty=true
                    fi
                    local counts
                    counts=$(git -C "$path" rev-list --left-right --count '@{upstream}...@' 2>/dev/null) || counts=
                    if [[ -n "$counts" ]]
                    then
                        ahead=${counts%%$'\t'*}
                        behind=${counts#*$'\t'}
                    fi
                fi
            fi
        fi

        # GitHub slug/host: registered wins, else derive from remote (best-effort).
        if [[ -n "${BU_LOCATION_PROPERTIES[$key,repo_gh_slug]:-}" ]]
        then
            gh_slug=${BU_LOCATION_PROPERTIES[$key,repo_gh_slug]}
        elif "$is_repo"
        then
            if bu_repo_resolve_slug "$display" 2>/dev/null
            then
                gh_slug=$BU_RET
                gh_host=${BU_RET_MAP[host]}
            fi
        fi
        [[ -n "${BU_LOCATION_PROPERTIES[$key,repo_gh_host]:-}" ]] && gh_host=${BU_LOCATION_PROPERTIES[$key,repo_gh_host]}

        bu_out_record \
            name="$display" path="$path" exists:="$exists" is_repo:="$is_repo" \
            branch="$branch" dirty:="$dirty" \
            ahead:="${ahead:-null}" behind:="${behind:-null}" \
            remote_url="$remote_url" gh_slug="$gh_slug" gh_host="$gh_host" \
            default_branch="$default_branch"
    done
} | bu_out --format "$format"

bu_scope_pop_function
return "$exit_code"
}

__bu_bu_get_repo_main "$@"
