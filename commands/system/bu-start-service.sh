#!/usr/bin/env bash
# Pipeline: consume
# Requires-Any: unit name
# Dispatch: source
# Synopsis: Start a system service
# Completion helper: unit names from the live system (units + service unit files).
__bu_bu_start_service_complete_units()
{
    BU_RET=()
    local u
    while IFS= read -r u
    do
        [[ -n "$u" ]] && BU_RET+=("$u")
    done < <( { systemctl list-units --all --no-legend --plain 2>/dev/null | awk '{print $1}'
                systemctl list-unit-files --no-legend --plain 2>/dev/null | awk '{print $1}' | grep '\.service$'
              } | awk '!seen[$1]++' )
}

function __bu_bu_start_service_main()
{
# --is-compatible: magic flag checked by the framework at registration time.
# Exit 0 if this command can run on the current system, non-zero otherwise.
# stderr becomes the reason shown in `bu` help.
if [[ "$1" == "--is-compatible" ]]; then
    command -v systemctl &>/dev/null || { echo "systemctl is required (systemd)" >&2; exit 1; }
    exit 0
fi
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local -a units=()
local is_user=false
local is_what_if=false
local format=auto
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --user)# _FLAG
        # Operate on the user service manager (systemctl --user)
        is_user=true
        ;;
    --what-if)# _FLAG
        # Show what would happen without changing anything
        is_what_if=true
        ;;
    --format)# FORMAT
        # Output format
        bu_parse_positional $# --enum ${BU_OUT_FORMATS[@]} enum-- --hint "Output format"
        format=${!shift_by}
        ;;
    --unit)# UNIT
        # Service unit name (repeatable; also accepts pipeline input by structural typing)
        bu_parse_positional $# --ret __bu_bu_start_service_complete_units ret-- --hint "Unit name"
        units+=("${!shift_by}")
        ;;
    -h|--help)# _FLAG
        # Print help
        is_help=true
        ;;
    *)
        if bu_env_is_in_autocomplete
        then
            # Unit positional: complete from live unit names
            autocompletion=(--ret __bu_bu_start_service_complete_units ret-- --hint "Unit name")
        fi
        units+=("$1")
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
Start systemd service units (PowerShell Start-Service analog, structured systemctl start).
Emits one record per unit: unit, action, started (boolean); failures carry
an error field. Needs sufficient privileges for system units (root or
polkit); --user targets the per-user manager and needs no elevation.
" \
        --example "One unit" "sshd" \
        --example "User unit" "--user pipewire" \
        --example "Dry run" "nginx --what-if"
        --example "Pipeline input" ""
    return 0
fi

# Pipeline input: when no unit names are given as arguments and stdin is a pipe,
# read JSONL records and extract .unit (or .name) via structural typing.
if ((${#units[@]} == 0)) && [[ ! -t 0 ]]
then
    local _u
    while IFS= read -r _u
    do
        [[ -n "$_u" ]] && units+=("$_u")
    done < <(__bu_out_strict_guard "start-service" | jq -r '.unit // .name // empty' 2>/dev/null)
fi

if ((${#units[@]} == 0))
then
    error_msg="Missing required unit name (e.g. bu start-service sshd)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

local -a systemctl_args=()
"$is_user" && systemctl_args+=(--user)

# Records go to a temp file (not a pipeline) so the loop runs in the current
# shell and the per-unit failure status survives in rc.
local records_file
records_file=$(mktemp)
bu_scope_add_cleanup rm -f "$records_file"

local rc=0
local unit err
{
    for unit in "${units[@]}"
    do
        if "$is_what_if"
        then
            bu_log_info "What if: systemctl ${systemctl_args[*]} start $unit"
            continue
        fi
        if err=$(systemctl "${systemctl_args[@]}" start -- "$unit" 2>&1)
        then
            bu_out_record unit="$unit" action=start started:=true
        else
            bu_out_record unit="$unit" action=start started:=false error="$err"
            rc=1
        fi
    done
} > "$records_file"

bu_out --format "$format" < "$records_file"

bu_scope_pop_function
return $rc
}

__bu_bu_start_service_main "$@"
