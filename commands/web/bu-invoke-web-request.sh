#!/usr/bin/env bash
# Pipeline: transform
# Requires-All: url
# Dispatch: source
# Synopsis: Make an HTTP request and return the response
function __bu_bu_invoke_web_request_main()
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
local out_file=
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
        bu_parse_positional $# --enum GET POST PUT PATCH DELETE HEAD OPTIONS enum-- --hint "HTTP method"
        method=${!shift_by}
        ;;
    -H|--header)# HEADER
        # Request header in 'Name: value' form (repeatable)
        bu_parse_positional $# --hint "'Name: value'"
        headers+=("${!shift_by}")
        ;;
    -d|--data)# DATA
        # Request body (implies content to send with the method)
        bu_parse_positional $# --hint "Request body"
        data=${!shift_by}
        ;;
    -o|--out-file)# FILE
        # Save the response body to this file instead of embedding it in the record
        bu_parse_positional $# "${BU_AUTOCOMPLETE_SPEC_FILE[@]}" --hint "Output file"
        out_file=${!shift_by}
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
Make an HTTP request and get response metadata plus content as a record (PowerShell Invoke-WebRequest).
The record carries curl's transfer metadata (response_code, content_type,
size_download, time_total, redirect_url, ...) plus a content field with
the body text. Use --out-file for large/binary downloads (content is
then null). For JSON APIs, bu invoke-rest-method parses the body into
records directly.
" \
        --example "GET a page" "https://example.com" \
        --example "POST a form body" "https://httpbin.org/post -X POST -d 'a=1'" \
        --example "Download to disk" "https://example.com/big.iso --out-file big.iso"
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
    error_msg="Missing required URL (e.g. bu invoke-web-request https://example.com)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

local body_file
body_file=$(mktemp)
bu_scope_add_cleanup rm -f "$body_file"

local -a curl_args=(-sS -X "$method" -w '%{json}')
local h
for h in "${headers[@]}"
do
    curl_args+=(-H "$h")
done
[[ -n "$data" ]] && curl_args+=(--data "$data")
[[ -n "$timeout" ]] && curl_args+=(--max-time "$timeout")
if [[ -n "$out_file" ]]
then
    curl_args+=(-o "$out_file")
else
    curl_args+=(-o "$body_file")
fi

local meta
if "$is_dry_run"; then
    bu_out_record url="$url" method="$method" status="would-send" dry_run:=true | bu_out --format "$format"
    bu_scope_pop_function
    return 0
fi

if ! meta=$(curl "${curl_args[@]}" "$url")
then
    bu_scope_pop_function
    return 1
fi

if [[ -n "$out_file" ]]
then
    # Body went to disk; report metadata with a null content
    jq -cn --argjson meta "$meta" --arg out_file "$out_file" \
        '$meta + {content: null, out_file: $out_file}' | bu_out --format "$format"
else
    # Embed the body as text; drop to null if it is not valid JSON-string material
    if ! jq -cn --argjson meta "$meta" --rawfile body "$body_file" \
        '$meta + {content: $body}' 2>/dev/null | bu_out --format "$format"
    then
        jq -cn --argjson meta "$meta" \
            '$meta + {content: null}' | bu_out --format "$format"
        bu_log_warn "Response body could not be embedded as text (binary?); retry with --out-file"
    fi
fi

bu_scope_pop_function
}

__bu_bu_invoke_web_request_main "$@"
