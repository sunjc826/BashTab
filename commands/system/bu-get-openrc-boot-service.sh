#!/usr/bin/env bash
# Pipeline: producer
# Dispatch: source
# Synopsis: List OpenRC services enabled at boot
# Fields: service runlevel
function __bu_bu_get_openrc_boot_service_main()
{
# --is-compatible: magic flag checked by the framework at registration time.
if [[ "$1" == "--is-compatible" ]]; then
    command -v rc-update &>/dev/null || { echo "rc-update is required (OpenRC)" >&2; exit 1; }
    exit 0
fi

local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local is_help=false
local format=auto
local runlevel=
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
    -r|--runlevel)# RUNLEVEL
        # Show services for a specific runlevel (e.g. default, boot, nonetwork)
        bu_parse_positional $# --hint "Runlevel name"
        runlevel=${!shift_by}
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
        --description "List OpenRC services enabled at boot and their runlevels.

Wraps rc-update show -v and parses the output.  Works on Alpine Linux,
Gentoo, and any OpenRC-based distribution." \
        --example "All runlevels" "" \
        --example "Specific runlevel" "--runlevel default"
    return 0
fi

# rc-update show output format:
#             bootmisc | boot
#               sshd | default
#             nginx | default
# Parse: service name is first field, runlevel is the last field separated by |
local -a rc_args=(rc-update show -v)
[[ -n "$runlevel" ]] && rc_args+=("$runlevel")
if ((${#remaining_options[@]} > 0)); then rc_args+=("${remaining_options[@]}"); fi
{
    "${rc_args[@]}" 2>/dev/null | while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        # Split on | — left is service (trimmed), right is runlevel
        local service runlevel
        service=$(echo "$line" | sed -E 's/^[[:space:]]*//; s/[[:space:]]*\|.*//')
        runlevel=$(echo "$line" | sed -E 's/.*\|[[:space:]]*//')
        [[ -z "$service" ]] && continue
        printf '%s\t%s\n' "$service" "$runlevel"
    done
} | bu_out_from_tsv --columns service,runlevel \
  | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_get_openrc_boot_service_main "$@"
