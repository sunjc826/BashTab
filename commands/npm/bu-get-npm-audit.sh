#!/usr/bin/env bash
# Pipeline: producer
# Dispatch: source
# Synopsis: Show npm security audit results
# Fields: name severity is_direct title url range fix_version fix_is_breaking via
function __bu_bu_get_npm_audit_main()
{
# --is-compatible: magic flag checked by the framework at registration time.
# Exit 0 if this command can run on the current system, non-zero otherwise.
# stderr becomes the reason shown in `bu` help.
if [[ "$1" == "--is-compatible" ]]; then
    command -v npm &>/dev/null || { echo "npm is required" >&2; exit 1; }
    exit 0
fi
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local project_path=.
local is_help=false
local format=auto
local is_production=false
local level=
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --format)# FORMAT
        # Output format
        bu_parse_positional $# --enum ${BU_OUT_FORMATS[@]} enum-- --hint "Output format"
        format=${!shift_by}
        ;;
    --production)# _FLAG
        # Skip devDependencies
        is_production=true
        ;;
    --level)# LEVEL
        # Minimum severity level (low, moderate, high, critical)
        bu_parse_positional $# --enum low moderate high critical enum-- --hint "Severity threshold"
        level=${!shift_by}
        ;;
    -h|--help)# _FLAG
        is_help=true
        ;;
    --cwd)# CWD
        bu_parse_positional $# --hint "Project directory path"
        project_path=${!shift_by}
        ;;
    --)
        shift
        break
        ;;
    *)
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
List npm audit vulnerabilities as flat JSONL records (npm audit --json wrapper).
Emits one record per vulnerable package. The via field is normalized: advisory
objects are extracted from the via array and string references are resolved.

Fields: name, severity, is_direct, title, url, range, fix_version, fix_is_breaking, via
" \
        --example "Current project" "" \
        --example "Production only" "--production" \
        --example "Critical only" "--level critical" \
        --example "Direct deps only" "| bu where '.is_direct'"
    return 0
fi

if ! command -v npm &>/dev/null
then
    error_msg="npm is required. Install Node.js from https://nodejs.org"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

# Run npm audit --json. npm exits non-zero when vulnerabilities are found,
# which is expected. Capture stdout, ignore exit code.
local npm_output
local -a audit_args=(audit --json)
"$is_production" && audit_args+=(--production)
[[ -n "$level" ]] && audit_args+=(--audit-level "$level")
if ((${#remaining_options[@]} > 0)); then audit_args+=("${remaining_options[@]}"); fi
npm_output=$(cd "$project_path" && npm "${audit_args[@]}" 2>/dev/null) || true

if [[ -z "$npm_output" ]]
then
    bu_scope_pop_function
    return 0
fi

# Flatten the vulnerabilities map into records, normalizing the via field.
# The via array can contain strings (refs to other vulns) or objects (advisories).
# We extract the first advisory object for title/url, and join all via values
# into a comma-separated dependency chain.
jq -c '
    .vulnerabilities // {} | to_entries[] | .value as $v |
    {
        name: $v.name,
        severity: $v.severity,
        is_direct: $v.isDirect,
        range: $v.range,
        fix_version: (if $v.fixAvailable and ($v.fixAvailable | type) == "object" then $v.fixAvailable.version else null end),
        fix_is_breaking: (if $v.fixAvailable and ($v.fixAvailable | type) == "object" then $v.fixAvailable.isSemVerMajor else false end),
        title: (
            [$v.via[]? | select(type == "object") | .title][0] // null
        ),
        url: (
            [$v.via[]? | select(type == "object") | .url][0] // null
        ),
        via: (
            [$v.via[]? | if type == "string" then . elif type == "object" then .name // .title else empty end] | join(", ")
        )
    }
' <<<"$npm_output" 2>/dev/null | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_get_npm_audit_main "$@"
