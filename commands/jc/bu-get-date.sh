#!/usr/bin/env bash
# Pipeline: producer
# Dispatch: source
# Synopsis: Display the current date and time
function __bu_bu_get_date_main()
{
# --is-compatible: magic flag checked by the framework at registration time.
# Exit 0 if this command can run on the current system, non-zero otherwise.
# stderr becomes the reason shown in `bu` help.
if [[ "$1" == "--is-compatible" ]]; then
    command -v date &>/dev/null || { echo "date is required" >&2; exit 1; }
    exit 0
fi
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local is_help=false
local format=auto
local is_utc=false
local date_format=
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
    --utc)# _FLAG
        # Report all fields in UTC instead of local time
        is_utc=true
        ;;
    -f|--date-format)# STRFTIME
        # Custom strftime format for the iso field (default: %Y-%m-%dT%H:%M:%S)
        bu_parse_positional $# --hint "strftime format"
        date_format=${!shift_by}
        ;;
    -h|--help)# _FLAG
        is_help=true
        ;;
    *)
        bu_parse_error_enum "$1"
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
if bu_env_is_in_autocomplete
then
    bu_autocomplete
    return 0
fi

if "$is_help"
then
    bu_autohelp \
        --description "Get the current date and time as a structured record (PowerShell Get-Date). No external dependencies beyond date(1)." \
        --example "Local time" "" \
        --example "UTC" "--utc" \
        --example "Custom format" "--date-format '%Y-%m-%d %H:%M:%S'"
    return 0
fi

local -a tz_flag=()
"$is_utc" && tz_flag=(-u)

local date_fmt='%Y-%m-%dT%H:%M:%S'
[[ -n "$date_format" ]] && date_fmt="$date_format"

# Single date invocation emitting TSV; epoch taken from EPOCHREALTIME (bash 5+)
local epoch=${EPOCHREALTIME%.*}
[[ -z "$epoch" ]] && epoch=$(date +%s)

local iso year month day hour minute second weekday tz_name tz_offset
iso=$(date "${tz_flag[@]}" +"$date_fmt")
IFS=$'\t' read -r year month day hour minute second weekday tz_name tz_offset < <(
    date "${tz_flag[@]}" '+%Y%t%m%t%d%t%H%t%M%t%S%t%A%t%Z%t%z'
)

{
    bu_out_record \
        iso="$iso" \
        epoch:="$epoch" \
        year:="$year" month:="$((10#$month))" day:="$((10#$day))" \
        hour:="$((10#$hour))" minute:="$((10#$minute))" second:="$((10#$second))" \
        day_of_week="$weekday" \
        timezone="$tz_name" timezone_offset="$tz_offset"
} | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_get_date_main "$@"
