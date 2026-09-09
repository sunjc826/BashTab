#!/usr/bin/env bash
# Pipeline: producer
# Dispatch: source
# Synopsis: Display TLS certificate information for a domain
function __bu_bu_get_certificate_main()
{
# --is-compatible: magic flag checked by the framework at registration time.
# Exit 0 if this command can run on the current system, non-zero otherwise.
# stderr becomes the reason shown in `bu` help.
if [[ "$1" == "--is-compatible" ]]; then
    command -v jc &>/dev/null || { echo "jc is required" >&2; exit 1; }
    command -v openssl &>/dev/null || { echo "openssl is required" >&2; exit 1; }
    exit 0
fi
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local is_help=false
local format=auto
local target=
local host=
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
    --host)# HOST
        # Fetch the certificate from a remote host[:port] over TLS (default port 443)
        bu_parse_positional $# --hint "host[:port]"
        host=${!shift_by}
        ;;
    -h|--help)# _FLAG
        is_help=true
        ;;
    *)
        if bu_env_is_in_autocomplete
        then
            # Certificate file positional: complete files
            autocompletion=("${BU_AUTOCOMPLETE_SPEC_FILE[@]}")
        fi
        if [[ -z "$target" ]]
        then
            target=$1
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
        --description "Decode an X.509 certificate (PowerShell Get-PfxCertificate analog). Accepts a local PEM file or --host to fetch a server's TLS certificate." \
        --example "Local PEM file" "./server.crt" \
        --example "Remote server" "--host example.com" \
        --example "Remote server, custom port" "--host example.com:8443"
    return 0
fi

if ! command -v jc &>/dev/null
then
    error_msg="jc is required. Install with: pip install jc"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

if [[ -n "$host" ]]
then
    # Remote mode: pull the server certificate over TLS
    local connect=$host servername=${host%%:*}
    [[ "$host" != *:* ]] && connect=$host:443
    openssl s_client -connect "$connect" -servername "$servername" </dev/null 2>/dev/null \
        | openssl x509 2>/dev/null \
        | jc --x509-cert 2>/dev/null \
        | jq -c 'if type == "array" then .[] else . end' 2>/dev/null \
        | bu_out --format "$format"
elif [[ -n "$target" ]]
then
    # Local PEM file mode
    if [[ ! -r "$target" ]]
    then
        error_msg="Cannot read certificate file: $target"
        bu_autohelp
        bu_scope_pop_function
        return 1
    fi
    cat -- "$target" 2>/dev/null \
        | jc --x509-cert 2>/dev/null \
        | jq -c 'if type == "array" then .[] else . end' 2>/dev/null \
        | bu_out --format "$format"
else
    error_msg="Provide a certificate file or --host host[:port]"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

bu_scope_pop_function
}

__bu_bu_get_certificate_main "$@"
