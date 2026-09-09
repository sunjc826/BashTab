#!/usr/bin/env bash
# Pipeline: transform
# Requires-All: url
# Dispatch: source
# Synopsis: Make an HTTP REST API call
function __bu_bu_invoke_rest_method_main()
{
# --is-compatible: magic flag checked by the framework at registration time.
# Exit 0 if this command can run on the current system, non-zero otherwise.
# stderr becomes the reason shown in `bu` help.
if [[ "$1" == "--is-compatible" ]]; then
    command -v curl &>/dev/null || { echo "curl is required" >&2; exit 1; }
    exit 0
fi
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local url=
local method=GET
local -a headers=()
local data=
local timeout=
local format=auto
local is_help=false
local is_dry_run=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    -X|--method)# METHOD
        # HTTP method
        bu_parse_positional $# --enum GET POST PUT PATCH DELETE enum-- --hint "HTTP method"
        method=${!shift_by}
        ;;
    -H|--header)# HEADER
        # Request header in 'Name: value' form (repeatable)
        bu_parse_positional $# --hint "'Name: value'"
        headers+=("${!shift_by}")
        ;;
    -d|--data)# DATA
        # Request body; objects/arrays are sent as JSON
        bu_parse_positional $# --hint "Request body (JSON)"
        data=${!shift_by}
        ;;
    --timeout)# SECONDS
        # Max time for the whole request
        bu_parse_positional $# --hint "Seconds"
        timeout=${!shift_by}
        ;;
    --format)# FORMAT
        # Output format
        bu_parse_positional $# --enum ${BU_OUT_FORMATS[@]} enum-- --hint "Output format"
        format=${!shift_by}
        ;;
    --url)# URL
        # Target URL (also accepts pipeline input by structural typing)
        bu_parse_positional $# --hint "https://..."
        url=${!shift_by}
        ;;
    --dry-run|--what-if) # _FLAG
        is_dry_run=true
        ;;
    -h|--help)# _FLAG
        # Print help
        is_help=true
        ;;
    *)
        if [[ -z "$url" ]]
        then
            url=$1
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
Call a JSON API and emit the response body as records (PowerShell Invoke-RestMethod).
A JSON array response unrolls to one record per element; an object yields
a single record. Non-2xx responses and non-JSON bodies are errors (use
bu invoke-web-request for arbitrary content). When -d is given, a JSON
Content-Type header is added automatically.
" \
        --example "List API objects" "https://api.github.com/repos/kellyjonbrazil/jc/tags" \
        --example "POST JSON" "https://httpbin.org/post -X POST -d '{\"a\":1}'" \
        --example "Filter the response" ""
        --example "Pipeline input" ""
    return 0
fi

# Pipeline input: when no URL is given and stdin is a pipe, read JSONL
# records and extract .url via structural typing.
if [[ -z "$url" ]] && [[ ! -t 0 ]]
then
    url=$(jq -r '.url // empty' 2>/dev/null | head -1)
fi

if [[ -z "$url" ]]
then
    error_msg="Missing required URL (e.g. bu invoke-rest-method https://api.example.com/items)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

local body_file
body_file=$(mktemp)
bu_scope_add_cleanup rm -f "$body_file"

local -a curl_args=(-sS -X "$method" -o "$body_file" -w '%{response_code}' -H 'Accept: application/json')
[[ -n "$data" ]] && curl_args+=(-H 'Content-Type: application/json' --data "$data")
local h
for h in "${headers[@]}"
do
    curl_args+=(-H "$h")
done
[[ -n "$timeout" ]] && curl_args+=(--max-time "$timeout")

if "$is_dry_run"; then
    bu_out_record url="$url" method="$method" status="would-send" dry_run:=true | bu_out --format "$format"
    bu_scope_pop_function
    return 0
fi

local http_code
if ! http_code=$(curl "${curl_args[@]}" "$url")
then
    bu_scope_pop_function
    return 1
fi

if [[ "$http_code" -lt 200 || "$http_code" -ge 300 ]]
then
    error_msg="HTTP $http_code from $url"
    bu_autohelp
    bu_log_err "Response body follows (if any):"
    cat "$body_file" >&2
    bu_scope_pop_function
    return 1
fi

# Cmdlets implicitly end at Out-Default: a table on a terminal, JSONL when piped
if ! jq -c 'if type == "array" then .[] else . end' "$body_file" 2>/dev/null | bu_out --format "$format"
then
    error_msg="Response was not valid JSON (use bu invoke-web-request for arbitrary content)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

bu_scope_pop_function
}

__bu_bu_invoke_rest_method_main "$@"
