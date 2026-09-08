#!/usr/bin/env bash
# Pipeline: producer
# Dispatch: source
# Synopsis: Query DNS records for a domain
# Fields: id opcode status flags query_num answer_num authority_num additional_num opt_pseudosection question answer query_time server when rcvd when_epoch when_epoch_utc
function __bu_bu_get_dns_main()
{
# --is-compatible: magic flag checked by the framework at registration time.
# Exit 0 if this command can run on the current system, non-zero otherwise.
# stderr becomes the reason shown in `bu` help.
if [[ "$1" == "--is-compatible" ]]; then
    command -v jc &>/dev/null || { echo "jc is required" >&2; exit 1; }
    command -v dig &>/dev/null || { echo "dig is required" >&2; exit 1; }
    exit 0
fi
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local is_help=false
local format=auto
local record_type=
local name=
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
    -t|--type)# TYPE
        # DNS record type (A, AAAA, MX, NS, TXT, CNAME, SOA, etc.)
        bu_parse_positional $# --enum A AAAA MX NS TXT CNAME SOA PTR SRV CAA enum-- --hint "Record type"
        record_type=${!shift_by}
        ;;
    --name)# NAME
        # Domain name to query
        bu_parse_positional $# --hint "Domain name"
        name=${!shift_by}
        ;;
    -h|--help)# _FLAG
        is_help=true
        ;;
    --)
        shift
        break
        ;;
    *)
        # Any unrecognized arg: pass through to the underlying command, replacing the default
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
        --description "Query DNS records (jc dig parser wrapper)." \
        --example "Root hints" "" \
        --example "A record" "--name example.com --type A" \
        --example "MX records" "--name example.com --type MX" \
        --example "With extra flags" "-- -la /var/log"
    return 0
fi

if ! command -v jc &>/dev/null
then
    error_msg="jc is required. Install with: pip install jc"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

# Build the command: use provided args if any, otherwise the default
local -a cmd=()
if [[ -n "$name" ]] || [[ -n "$record_type" ]] || ((${#remaining_options[@]} > 0))
then
    cmd=(dig)
    [[ -n "$record_type" ]] && cmd+=(-t "$record_type")
    [[ -n "$name" ]] && cmd+=("$name")
    ((${#remaining_options[@]} > 0)) && cmd+=("${remaining_options[@]}")
else
    cmd=(dig)
fi

"${cmd[@]}" 2>/dev/null | jc --dig 2>/dev/null | jq -c 'if type == "array" then .[] else . end' 2>/dev/null | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_get_dns_main "$@"
