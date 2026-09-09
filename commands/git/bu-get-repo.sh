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

local name=
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
    --format)# FORMAT
        # Output format
        bu_parse_positional $# --enum ${BU_OUT_FORMATS[@]} enum-- --hint "Output format"
        format=${!shift_by}
        ;;
    -h|--help)# _FLAG
        # Print help
        is_help=true
        ;;
    *)
        if bu_env_is_in_autocomplete && [[ "$1" != -* ]]
        then
            autocompletion=(--stdout bu_repo_names stdout-- --hint "Repo name")
        fi
        if [[ -z "$name" ]]
        then
            name=$1
        else
            bu_parse_error_enum "$1"
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
        --example "Skip status probes" "--no-status"
    return 0
fi

# Collect the repo keys to report.
local -a keys=()
local key k
if [[ -n "$name" ]]
then
    __bu_location_resolve_key "$name" --kind dir 2>/dev/null || {
        error_msg="Unknown repo[$name]"
        bu_autohelp
        bu_scope_pop_function
        return 1
    }
    keys=("$BU_RET")
else
    for key in "${!BU_LOCATION_REGISTRY[@]}"
    do
        k=${BU_LOCATION_REGISTRY[$key]}
        [[ "$k" == dir ]] || continue
        __bu_location_tag_match "${BU_LOCATION_PROPERTIES[$key,tags]:-}" repo || continue
        keys+=("$key")
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
}

__bu_bu_get_repo_main "$@"
