#!/usr/bin/env bash
# Pipeline: project
# Dispatch: source
# Synopsis: Compare two JSONL streams and show differences
function __bu_bu_compare_object_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local reference=
local key=
local is_include_equal=false
local format=auto
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --key)# KEY
        # Compare records by this key field instead of by whole-record equality
        bu_parse_positional $# --hint "key field" --pipeline-fields pipeline-fields--
        key=${!shift_by}
        ;;
    --include-equal)# _FLAG
        # Also emit records present on both sides (side == "==")
        is_include_equal=true
        ;;
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
        if bu_env_is_in_autocomplete
        then
            # Reference file positional: complete files
            autocompletion=("${BU_AUTOCOMPLETE_SPEC_FILE[@]}")
        fi
        if [[ -z "$reference" ]]
        then
            reference=$1
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
Compare two sets of JSONL records (PowerShell Compare-Object, diff for records).
The reference set comes from a file; the difference set is the stdin stream.
Each output record is tagged with a side: "<=" only in the reference,
"=>" only in the difference (stdin), "==" in both (with --include-equal).
By default records compare by whole-record equality; --key compares by a
single field. Requires both sets in full.
" \
        --example "Diff two snapshots" "before.jsonl" \
        --example "Compare by key field" "before.jsonl --key pid" \
        --example "Show matches too" "before.jsonl --key name --include-equal"
    return 0
fi

if [[ -z "$reference" ]]
then
    error_msg="Missing required reference file (e.g. bu get-process | bu compare-object before.jsonl --key pid)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

if [[ ! -r "$reference" ]]
then
    error_msg="Cannot read reference file: $reference"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

if [[ -n "$key" ]]
then
    __bu_out_validate_key "$key" || { bu_scope_pop_function; return 1; }
fi

# Slurp the difference (stdin) set to a temp file so jq can read both sides
local difference_file
difference_file=$(mktemp)
bu_scope_add_cleanup rm -f "$difference_file"
cat > "$difference_file"

jq -nc --slurpfile ref "$reference" --slurpfile dif "$difference_file" \
    --arg key "$key" --argjson include_equal "$is_include_equal" '
    $ref as $r | $dif as $d
    | if $key != "" then
        ([$d[] | .[$key]]) as $dk
        | ([$r[] | .[$key]]) as $rk
        | (  [$r[] | select(.[$key] as $k | ($dk | index($k)) | not) | . + {side: "<="}]
           + [$d[] | select(.[$key] as $k | ($rk | index($k)) | not) | . + {side: "=>"}]
           + (if $include_equal then [$r[] | select(.[$key] as $k | $dk | index($k)) | . + {side: "=="}] else [] end)
          )[]
      else
        (  (($r - $d) | map(. + {side: "<="}))
         + (($d - $r) | map(. + {side: "=>"}))
         + (if $include_equal then [$r[] | select(. as $x | $d | index($x)) | . + {side: "=="}] else [] end)
        )[]
      end
' | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_compare_object_main "$@"
