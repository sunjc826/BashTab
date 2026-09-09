#!/usr/bin/env bash
# Pipeline: producer
# Dispatch: source
# Synopsis: List systemd units and their status
# Fields: unit load active sub description
function __bu_bu_get_systemd_unit_main()
{
# --is-compatible: magic flag checked by the framework at registration time.
if [[ "$1" == "--is-compatible" ]]; then
    command -v systemctl &>/dev/null || { echo "systemctl is required (systemd)" >&2; exit 1; }
    command -v jc &>/dev/null       || { echo "jc is required" >&2; exit 1; }
    exit 0
fi

local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local is_help=false
local format=auto
local type_filter=
local state_filter=
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
    -t|--type)# TYPE
        # Filter by unit type (service, mount, socket, device, etc.)
        bu_parse_positional $# --enum service mount socket device automount swap target path timer slice scope enum-- --hint "Unit type"
        type_filter=${!shift_by}
        ;;
    --state)# STATE
        # Filter by load/active/sub state (e.g. active, inactive, failed, running)
        bu_parse_positional $# --enum active inactive failed running dead exited listening waiting plugged mounted enum-- --hint "Unit state"
        state_filter=${!shift_by}
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
        --description "List systemd units (services, mounts, sockets, etc.) as structured records.

Wraps systemctl list-units and pipes through jc --systemctl." \
        --example "Default" "" \
        --example "Services only" "--type service" \
        --example "Active services" "--type service --state active" \
        --example "Failed units" "--state failed"
    return 0
fi

local -a cmd=(systemctl list-units --all)
[[ -n "$type_filter" ]] && cmd+=(--type "$type_filter")
[[ -n "$state_filter" ]] && cmd+=(--state "$state_filter")
if ((${#remaining_options[@]} > 0)); then cmd+=("${remaining_options[@]}"); fi

"${cmd[@]}" 2>/dev/null | jc --systemctl 2>/dev/null \
    | jq -c 'if type == "array" then .[] else . end' 2>/dev/null \
    | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_get_systemd_unit_main "$@"
