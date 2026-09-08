#!/usr/bin/env bash
# Pipeline: consume
# Requires-All: key
# Dispatch: source
# Synopsis: Set a Git configuration value
function __bu_bu_set_git_config_main()
{
# --is-compatible: magic flag checked by the framework at registration time.
if [[ "$1" == "--is-compatible" ]]; then
    command -v git &>/dev/null || { echo "git is required" >&2; exit 1; }
    exit 0
fi
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local key=
local value=
local scope=local
local is_unset=false
local is_dry_run=false
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --key)# KEY
        # Config key (e.g. user.name, core.editor)
        bu_parse_positional $# --hint "Config key"
        key=${!shift_by}
        ;;
    --value)# VALUE
        # Config value
        bu_parse_positional $# --hint "Config value"
        value=${!shift_by}
        ;;
    --scope)# SCOPE
        # Config scope: local (repo), global (user), system
        bu_parse_positional $# --enum local global system enum-- --hint "Config scope"
        scope=${!shift_by}
        ;;
    --unset)# _FLAG
        # Remove the config key instead of setting it
        is_unset=true
        ;;
    --dry-run|--what-if)# _FLAG
        # Show what would be set without doing it
        is_dry_run=true
        ;;
    -h|--help)# _FLAG
        is_help=true
        ;;
    --)
        shift
        break
        ;;
    *)
        break
        ;;
    esac
    if "$is_help"; then break; fi
    if (( $# < shift_by )); then bu_parse_error_argn "$1" $#; break; fi
    shift "$shift_by"
done
if bu_env_is_in_autocomplete; then bu_autocomplete; return 0; fi

if "$is_help"; then
    bu_autohelp \
        --description "
Set or unset a git configuration value (git config).

Also accepts JSONL piped input with .key and .value fields for bulk setting:

  echo '{\"key\":\"user.name\",\"value\":\"Alice\"}' | bu set-git-config

Output record fields: key, value, scope, action
" \
        --example "Set config" "--key user.name --value 'Jane Doe'" \
        --example "Set globally" "--scope global --key core.editor --value vim" \
        --example "Unset config" "--key old.setting --unset" \
        --example "Bulk from pipeline" "(echo JSONL records with .key and .value)"
    return 0
fi

# Read key=value pairs from stdin pipeline if no key given and stdin has data.
# Use read -t 0 to check for available data without blocking.
local -a pipeline_records=()
if [[ -z "$key" ]] && read -t 0 2>/dev/null; then
    local line
    while IFS= read -r line; do
        pipeline_records+=("$line")
    done
fi

if ((${#pipeline_records[@]} > 0)); then
    local record k v
    for record in "${pipeline_records[@]}"; do
        k=$(jq -r '.key // empty' <<<"$record" 2>/dev/null) || true
        v=$(jq -r '.value // empty' <<<"$record" 2>/dev/null) || true
        if [[ -n "$k" ]]; then
            if "$is_dry_run"; then
                bu_out_record key="$k" value="$v" scope="$scope" action="would-set" | bu_out --format jsonl
            else
                git config --"$scope" "$k" "$v" 2>/dev/null && {
                    bu_out_record key="$k" value="$v" scope="$scope" action="set" | bu_out --format jsonl
                } || {
                    bu_out_record key="$k" scope="$scope" action="error" error="failed to set" | bu_out --format jsonl
                }
            fi
        fi
    done
    bu_scope_pop_function
    return 0
fi

if [[ -z "$key" ]]; then
    error_msg="--key is required (or pipe records with .key and .value)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

if "$is_dry_run"; then
    if "$is_unset"; then
        bu_out_record key="$key" scope="$scope" action="would-unset" | bu_out --format jsonl
    else
        bu_out_record key="$key" value="$value" scope="$scope" action="would-set" | bu_out --format jsonl
    fi
    bu_scope_pop_function
    return 0
fi

if "$is_unset"; then
    git config --"$scope" --unset "$key" 2>/dev/null && {
        bu_out_record key="$key" scope="$scope" action="unset" | bu_out --format jsonl
    } || {
        error_msg="Failed to unset: $key"
        bu_autohelp
        bu_scope_pop_function
        return 1
    }
else
    git config --"$scope" "$key" "$value" 2>/dev/null && {
        bu_out_record key="$key" value="$value" scope="$scope" action="set" | bu_out --format jsonl
    } || {
        error_msg="Failed to set: $key = $value"
        bu_autohelp
        bu_scope_pop_function
        return 1
    }
fi

bu_scope_pop_function
}

__bu_bu_set_git_config_main "$@"
