#!/usr/bin/env bash
# Pipeline: producer
# Dispatch: source
# Synopsis: List iptables firewall rules
# Fields: chain num pkts bytes target prot opt in out source destination
function __bu_bu_get_iptables_rule_main()
{
# --is-compatible: magic flag checked by the framework at registration time.
if [[ "$1" == "--is-compatible" ]]; then
    command -v iptables &>/dev/null || { echo "iptables is required" >&2; exit 1; }
    command -v jc &>/dev/null      || { echo "jc is required" >&2; exit 1; }
    exit 0
fi

local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local is_help=false
local format=auto
local table=filter
local chain=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --format)# FORMAT
        bu_parse_positional $# --enum ${BU_OUT_FORMATS[@]} enum-- --hint "Output format"
        format=${!shift_by}
        ;;
    -t|--table)# TABLE
        # iptables table (filter, nat, mangle, raw, security)
        bu_parse_positional $# --enum filter nat mangle raw security enum-- --hint "iptables table"
        table=${!shift_by}
        ;;
    --chain)# CHAIN
        # Specific chain to list (e.g. INPUT, OUTPUT, FORWARD)
        bu_parse_positional $# --hint "Chain name"
        chain=${!shift_by}
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
local remaining_options=("$@")
if bu_env_is_in_autocomplete; then bu_autocomplete; return 0; fi

if "$is_help"; then
    bu_autohelp \
        --description "List iptables firewall rules as structured records.

Wraps iptables -L -v -n and pipes through jc --iptables.  Works on any
Linux system with iptables installed (including Alpine)." \
        --example "Filter table (default)" "" \
        --example "NAT table" "--table nat" \
        --example "Specific chain" "--chain INPUT"
    return 0
fi

local -a cmd=(iptables -L -v -n -t "$table")
[[ -n "$chain" ]] && cmd+=("$chain")
if ((${#remaining_options[@]} > 0)); then cmd+=("${remaining_options[@]}"); fi

"${cmd[@]}" 2>/dev/null | jc --iptables 2>/dev/null \
    | jq -c 'if type == "array" then .[] else . end' 2>/dev/null \
    | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_get_iptables_rule_main "$@"
