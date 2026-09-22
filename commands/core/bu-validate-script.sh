#!/usr/bin/env bash
# Pipeline: producer
# Dispatch: source
# Synopsis: Lint command scripts and core libraries against BashTab's own invariants
# Fields: file line rule severity message snippet
function __bu_bu_validate_script_main()
{
# --is-compatible: the rule engine is tree-sitter based (see lib/lint/bu_lint.js).
# This must exit BEFORE any entrypoint sourcing — the framework probes with
# `bash <script> --is-compatible`, and sourcing here would rescan every command.
if [[ "$1" == "--is-compatible" ]]; then
    command -v node &>/dev/null || { echo "node is required by the lint rule engine" >&2; exit 1; }
    [[ -d "${BU_DIR:-$(dirname -- "${BASH_SOURCE%/*}")/../..}/node_modules/tree-sitter-bash" ]] \
        || { echo "tree-sitter-bash is not installed (run 'pnpm install' in the BashTab checkout)" >&2; exit 1; }
    exit 0
fi

local -r invocation_dir=$PWD
local script_name script_dir
case "$BASH_SOURCE" in
*/*)
    script_name=${BASH_SOURCE##*/}
    script_dir=${BASH_SOURCE%/*}
    ;;
*)
    script_name=$BASH_SOURCE
    script_dir=.
    ;;
esac
pushd "$script_dir" &>/dev/null

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_scope_add_cleanup bu_popd_silent
bu_run_log_command "$@"

local is_all=false
local is_strict=false
local is_help=false
local explain=
local rules=
local severity=info
local baseline=
local write_baseline=
local format=auto
local columns=
local error_msg=
local autocompletion=()
local shift_by=
local -a targets=()
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --all)# _FLAG
        # Lint the whole BashTab tree (core, commands, config, templates)
        is_all=true
        ;;
    --rules)# RULES
        # Only report these rules (comma-separated, e.g. BU001,BU010)
        bu_parse_positional $# --hint "Comma-separated rule ids"
        rules=${!shift_by}
        ;;
    --severity)# SEVERITY
        # Minimum severity to report
        bu_parse_positional $# --enum info warning error enum-- --hint "Minimum severity"
        bu_validate_positional "${!shift_by}"
        severity=${!shift_by}
        ;;
    --explain)# RULE
        # Print the full rationale for one rule and exit
        bu_parse_positional $# --ret __bu_validate_script_rule_ids ret-- --hint "Rule id"
        explain=${!shift_by}
        ;;
    --baseline)# FILE
        # Suppress findings recorded in this baseline file
        bu_parse_positional $# "${BU_AUTOCOMPLETE_SPEC_FILE[@]}"
        baseline=${!shift_by}
        ;;
    --write-baseline)# FILE
        # Record current findings to this file instead of reporting them
        bu_parse_positional $# --hint "Baseline file to write"
        write_baseline=${!shift_by}
        ;;
    --strict)# _FLAG
        # Exit non-zero on warnings too, not just errors
        is_strict=true
        ;;
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
        targets+=("$1")
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
Lint BashTab scripts against the framework's own invariants — the rules that
bash itself cannot express and shellcheck does not know about:

  * arithmetic commands that abort an errexit shell (BU001)
  * file-scope \`declare\` without -g, which the custom source() wrapper
    silently turns into a local (BU010/BU011)
  * case-pattern annotations that contradict the bu_parse_* call, so --help
    documents the wrong arity (BU021)
  * autocomplete DSL lists opened without their terminator (BU024)
  * --is-compatible handled after entrypoint sourcing, which makes the
    registration probe recurse (BU032)
  * command headers that are missing, or placed outside the window where the
    framework actually reads them (BU040/BU041)

Rules match on the bash CST via tree-sitter, not on text, so \`x=\$((i++))\` and
\`if ((i > 0))\` are never confused with a bare \`((i++))\`. Findings are ordinary
records: a table on a terminal, JSONL in a pipe.

Exit status is 0 when clean, 1 when any error-severity finding survives the
baseline, and 2 with --strict when only warnings remain.
" \
        --example "Lint everything" "bu validate-script --all" \
        --example "One directory" "bu validate-script commands/git" \
        --example "Errors only" "bu validate-script --all --severity error" \
        --example "Why does this rule exist" "bu validate-script --explain BU001" \
        --example "Accept today's findings" "bu validate-script --all --write-baseline .bulintbaseline" \
        --example "Query the findings" "bu validate-script --all | bu where 'rule == \"BU001\"'"
    return 0
fi

local -r engine=$BU_DIR/lib/lint/bu_lint.js

if [[ -n "$explain" ]]
then
    node "$engine" --explain "$explain"
    local -r explain_rc=$?
    bu_scope_pop_function
    return "$explain_rc"
fi

# ── file discovery ───────────────────────────────────────────────────────
# Default target set is BashTab's own scripts.
#   - test/ is excluded: its lint fixtures are deliberately invalid.
#   - lib/templates is excluded: templates carry @PLACEHOLDER@ tokens that the
#     bash grammar cannot parse, so every one of them would report BU000.
#     Lint them explicitly (`bu validate-script lib/templates`) when wanted —
#     the header rules are line-based and still work there.
local -a files=()
if "$is_all" || (( ${#targets[@]} == 0 ))
then
    mapfile -t files < <(
        find "$BU_DIR"/lib/core "$BU_DIR"/commands "$BU_DIR"/config \
            -name '*.sh' -type f 2>/dev/null | sort
    )
else
    local target
    for target in "${targets[@]}"
    do
        if [[ -d "$target" ]]
        then
            mapfile -t -O "${#files[@]}" files < <(find "$target" -name '*.sh' -type f | sort)
        elif [[ -f "$target" ]]
        then
            files+=("$target")
        else
            bu_log_err "No such file or directory: $target"
            bu_scope_pop_function
            return 1
        fi
    done
fi

if (( ${#files[@]} == 0 ))
then
    bu_log_warn "No shell scripts to lint"
    bu_scope_pop_function
    return 0
fi

# ── run ──────────────────────────────────────────────────────────────────
local -a engine_args=(--root "$BU_DIR" --severity "$severity")
[[ -n "$rules" ]] && engine_args+=(--rules "$rules")
[[ -n "$baseline" ]] && engine_args+=(--baseline "$baseline")
[[ -n "$write_baseline" ]] && engine_args+=(--write-baseline "$write_baseline")
"$is_strict" && engine_args+=(--strict)

if [[ -n "$write_baseline" ]]
then
    node "$engine" "${engine_args[@]}" "${files[@]}"
    local -r write_rc=$?
    bu_scope_pop_function
    return "$write_rc"
fi

local -a out_args=(--format "$format")
[[ -n "$columns" ]] && out_args+=(--columns "$columns")

# One node process, one jq process — no forks in a loop.
node "$engine" "${engine_args[@]}" "${files[@]}" \
    | bu_out_from_tsv --columns file,line,rule,severity,message,snippet \
    | bu_out "${out_args[@]}"
local -r engine_rc=${PIPESTATUS[0]}

bu_scope_pop_function
return "$engine_rc"
}

# ```
# *Description*:
# Completion helper: the rule ids the engine currently ships.
#
# *Returns*:
# - `BU_RET`: array of rule ids
# ```
__bu_validate_script_rule_ids()
{
    BU_RET=()
    mapfile -t BU_RET < <(node "$BU_DIR"/lib/lint/bu_lint.js --list-rules 2>/dev/null | cut -f1)
    return 0
}

__bu_bu_validate_script_main "$@"
