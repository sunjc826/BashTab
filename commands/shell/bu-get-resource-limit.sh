#!/usr/bin/env bash
# Pipeline: producer
# Fields: flag resource units value
# Dispatch: source
# Synopsis: Show shell resource limits
function __bu_bu_get_resource_limit_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local format=auto
local is_help=false
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
    -h|--help)# _FLAG
        # Print help
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
        --description "
List per-process resource limits (structured ulimit -a).
Each record joins the soft and hard limits for one resource: resource,
flag (the ulimit switch letter), units, soft, hard. Values are the live
limits of the current shell.
" \
        --example "All limits" ""
    return 0
fi

# Parse one 'ulimit -?a' stream into TSV: flag <TAB> resource <TAB> units <TAB> value
__bu_get_resource_limit_tsv()
{
    local line before rest paren value flag units
    while IFS= read -r line
    do
        [[ "$line" == *\(*\)* ]] || continue
        before=${line%%(*}
        # Trim trailing whitespace from the resource description
        before=${before%"${before##*[![:space:]]}"}
        rest=${line#*(}
        paren=${rest%%)*}
        value=${rest#*) }
        if [[ "$paren" == *,* ]]
        then
            units=${paren%,*}
            flag=${paren##*, }
        else
            units=
            flag=$paren
        fi
        printf '%s\t%s\t%s\t%s\n' "$flag" "$before" "$units" "$value"
    done
}

local soft_file hard_file
soft_file=$(mktemp)
hard_file=$(mktemp)
bu_scope_add_cleanup rm -f "$soft_file" "$hard_file"

ulimit -Sa | __bu_get_resource_limit_tsv | bu_out_from_tsv --columns flag,resource,units,value > "$soft_file"
ulimit -Ha | __bu_get_resource_limit_tsv | bu_out_from_tsv --columns flag,resource,units,value > "$hard_file"

jq -nc --slurpfile soft "$soft_file" --slurpfile hard "$hard_file" '
    ($soft | INDEX(.flag)) as $s
    | $hard[]
    | . as $h
    | ($s[$h.flag] // {}) as $x
    | {
        resource: ($h.resource),
        flag: $h.flag,
        units: (if ($h.units // $x.units) == "" then null else ($h.units // $x.units) end),
        soft: ($x.value // null),
        hard: $h.value
    }
' | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_get_resource_limit_main "$@"
