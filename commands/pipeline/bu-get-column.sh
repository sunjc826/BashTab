#!/usr/bin/env bash
# Dispatch: source
# Pipeline: producer
# Synopsis: Describe output columns and their lineage without executing commands
# Column: column string Output column name
# Column: type string Column value type
# Column: unit string Unit of measurement
# Column: description string Meaning of the column
# Column: source string Origin of the column description
# Column: producer string Command that produced the column
# Column: derived string How the column was derived
# Column: observed string Pipe form only: value types seen on stdin, or absent when a declared column never appeared
function __bu_bu_get_column_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local pipeline=
local format=auto
local columns=
local traced=
local status=0
local first=
local has_first=true
local pipe_status=
local pipe_reason=
local -a out_args=()
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
        bu_parse_positional $# --enum "${BU_OUT_FORMATS[@]}" enum-- --hint "Output format"
        bu_validate_positional "${!shift_by}"
        format=${!shift_by}
        ;;
    --columns)# COLUMNS
        # Display columns as key:Label (comma-separated)
        bu_parse_positional $# --hint "Comma-separated columns"
        columns=${!shift_by}
        ;;
    -h|--help)# _FLAG
        # Print help
        is_help=true
        ;;
    *)
        if [[ -n "$pipeline" ]]
        then
            bu_parse_error_enum "$1"
            break
        fi
        pipeline=$1
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
    bu_autohelp --description "Describe the output columns of a command or quoted pipeline without executing it.

Pipe form: with no argument and records on stdin, describe the pipeline that produced them. Each bu stage records what it is next to the pipe it writes (BU_OUT_PIPE_METADATA), so the declared columns and their lineage are recovered, and the 'observed' column adds the value types actually seen on stdin ('absent' for a declared column that never appeared). Fields nobody declared are appended with source 'inferred'. When the chain cannot be recovered (a grep or jq stage in the middle, a file on stdin) every column is inferred from the records." \
        --example "Trace a renamed column" "bu get-column 'get-module | select name,r=rank'" \
        --example "Describe a live pipe" "bu get-command | bu where verb -eq get | bu explain-column"
    return 0
fi

out_args=(--format "$format")
[[ -n "$columns" ]] && out_args+=(--columns "$columns")

if [[ -z "$pipeline" ]] && [[ -p /dev/stdin || -f /dev/stdin ]]
then
    # Pipe form. Read a line first: by then every upstream sidecar is on disk.
    IFS= read -r first || [[ -n "$first" ]] || has_first=false
    __bu_pipemeta_resolve
    pipeline=${BU_RET[0]}
    pipe_status=${BU_RET[1]}
    case "$pipe_status" in
    resolved)
        if ! traced=$(__bu_column_explain_pipeline "$pipeline" 2>/dev/null)
        then
            traced=
            pipe_reason="Cannot trace '$pipeline'"
        fi
        ;;
    broken)
        pipe_reason="Pipeline metadata stops before a producer (after '$pipeline': a stage that is not a $BU_CLI_COMMAND_NAME command?)"
        ;;
    *)
        pipe_reason="No pipeline metadata for stdin"
        ;;
    esac
    if [[ -n "$pipe_reason" ]]
    then
        bu_log_info "$pipe_reason; inferring columns from the records"
    fi
    # One pass over stdin: the record count, then per field (first-seen
    # order) the value types seen, merged into the declared columns.
    {
        if "$has_first"; then printf '%s\n' "$first"; fi
        cat
    } | jq -Rnc --arg decl "$traced" '
        def vtype:
            type as $t
            | if $t == "number" then (if . == floor then "int" else "float" end)
              elif $t == "boolean" then "bool"
              else $t end;
        ($decl | split("\n") | map(select(length > 0) | fromjson)) as $d
        | (reduce (inputs | fromjson? | objects) as $r ({n: 0, order: [], types: {}};
            .n += 1
            | reduce ($r | to_entries[]) as $e (.;
                ($e.value | vtype) as $t
                | if (.types | has($e.key) | not) then .order += [$e.key] | .types[$e.key] = [$t]
                  elif (.types[$e.key] | index($t)) != null then .
                  else .types[$e.key] += [$t] end))) as $s
        | ($d | map({key: .column, value: true}) | from_entries) as $known
        | ($d[]
            | .column as $c
            | .observed = (if $s.n == 0 then null
                           elif ($s.types | has($c)) then ($s.types[$c] | join(","))
                           else "absent" end)),
          ($s.order[]
            | select($known[.] | not)
            | . as $k
            | $s.types[$k] as $ts
            | ($ts - ["null"]) as $nn
            | {column: $k,
               type: (if ($nn | length) == 1 then $nn[0] else "any" end),
               unit: null, description: null, source: "inferred",
               producer: null, derived: null,
               observed: ($ts | join(","))})
    ' | bu_out "${out_args[@]}"
    bu_scope_pop_function
    return 0
fi

if [[ -z "$pipeline" ]]
then
    error_msg="Expected a command or quoted pipeline (bu get-column 'get-module | select name')"
    bu_autohelp
    return 1
fi

# Capture only metadata so a tracing failure survives the output pipeline.
traced=$(__bu_column_explain_pipeline "$pipeline") || status=$?
if ((status == 0)) && [[ -n "$traced" ]]; then
    printf '%s\n' "$traced" | bu_out "${out_args[@]}"
    status=$?
fi
bu_scope_pop_function
return "$status"
}

__bu_bu_get_column_main "$@"
