# Synopsis: BashTab's JSONL object protocol and command pipeline

# Live checks. This file is sourced in a subshell by `bu get-help`, so plain
# assignments here cannot leak into the invoking shell. Dynamic values are
# computed up front, then interpolated into the heredoc below.

_jq_status=
if command -v jq &>/dev/null; then
    _jq_status=$(jq --version 2>/dev/null)
else
    _jq_status="MISSING (install jq >= 1.6)"
fi

_tty_status="piped — Out-Default resolves to jsonl"
if [[ -t 1 ]]; then
    _tty_status="terminal — Out-Default resolves to table"
fi

_output_format=${BU_OUTPUT_FORMAT:-<unset>}
_table_pager=${BU_TABLE_PAGER:-<unset>}
_multi_verbs=${BU_MULTI_WORD_VERBS:-convert-to convert-from}

_cmd_table=$(bu_help_topic_commands "$BU_BUILTIN_COMMANDS_DIR/pipeline")

cat <<EOF
${BU_TPUT_BOLD}NAME${BU_TPUT_RESET}
    pipeline — BashTab's object protocol: JSONL record streams and the command pipeline

${BU_TPUT_BOLD}SYNOPSIS${BU_TPUT_RESET}
    bu get-command | bu where '.type == "source"' | bu select name,verb | bu sort verb

${BU_TPUT_BOLD}DESCRIPTION${BU_TPUT_RESET}
    BashTab commands can emit records instead of text. Instead of parsing
    columns with awk/grep, you filter and shape fields with SQL-style cmdlets
    or raw jq, and presentation (table vs JSON) is chosen automatically at the
    end of the pipeline — like PowerShell's Out-Default.

    Everything is built on one idea: JSONL (one JSON object per line) is the
    object stream, and jq is the engine. A record is a JSON object; a pipeline
    is a stream of records passed through stages that each read JSONL and write
    JSONL until a sink renders them.

${BU_TPUT_BOLD}THE PROTOCOL${BU_TPUT_RESET}
    producer → recordify → transform → sink

    Layer          Core functions                                        Cmdlets
    -------------  ----------------------------------------------------  ------------------------------------------
    Recordifiers   bu_out_record, bu_out_from_tsv, bu_out_from_lines     new-record, convert-from-tsv, convert-from-lines, import-csv, import-tsv, import-jsonl, import-json
    Transforms     bu_out_where, bu_out_select, bu_out_sort_by,          where, select, sort, query-object,
                   bu_out_group_by, bu_out_distinct                      distinct-object
    Sinks          bu_format_table, bu_format_list, bu_format_json,      format-table, format-list, convert-to-json,
                   bu_format_jsonl, bu_format_tsv                        convert-to-jsonl, convert-to-tsv
    Dispatcher     bu_out                                                out-default

    The functions are the scripting API (pure JSONL in/out); the cmdlets wrap
    them for interactive use and add implicit Out-Default, so a terminal
    pipeline ends in a table while a piped one stays JSONL.

    Out-Default format resolution (first match wins):
      1. an explicit --format flag (auto table list json jsonl tsv)
      2. the BU_OUTPUT_FORMAT environment variable
      3. stdout is a terminal → table; otherwise → jsonl

${BU_TPUT_BOLD}THIS MACHINE${BU_TPUT_RESET}
    jq:                $_jq_status
    stdout:            $_tty_status
    BU_OUTPUT_FORMAT:  $_output_format
    BU_TABLE_PAGER:    $_table_pager
    multi-word verbs:  $_multi_verbs

${BU_TPUT_BOLD}COMMANDS${BU_TPUT_RESET}
    Derived from commands/pipeline/ — this table can never drift from the
    scripts' own # Synopsis: headers:

$_cmd_table

${BU_TPUT_BOLD}TYPICAL FLOWS${BU_TPUT_RESET}
    Inspect a command registry as a table, then narrow it down:
        bu get-command
        bu get-command | bu where '.type == "source"' | bu select name,verb
        bu get-command | bu sort definition

    Compose SQL-style in one shot:
        bu get-command | bu query-object where '.type == "source"' \\
            group-by verb agg count order-by count desc first 5

    Build records by hand and render them:
        bu new-record name=alpha hp=10 | bu new-record name=beta hp=20 | bu format-table

${BU_TPUT_BOLD}FAILURE SIGNATURES${BU_TPUT_RESET}
    "jq: command not found" (or bu_out reporting jq missing)
        The whole object layer requires jq >= 1.6. Install it and re-source.

    jq compile errors (e.g. "jq: error: ... syntax error")
        A transform clause is not a valid jq expression. Quote expressions
        with single quotes so the shell does not expand \$ and other operators.

    Empty table / no output
        Normally correct (PowerShell semantics: empty input → no output).
        If you expected records, the upstream producer emitted nothing — check
        its filter or that it actually outputs JSONL (run it and pipe to jq).

    Tab characters inside a value when using convert-from-tsv
        TSV recordification splits on tabs; a tab in a value corrupts the
        record. Use bu new-record (key=value) for arbitrary strings instead.

${BU_TPUT_BOLD}SEE ALSO${BU_TPUT_RESET}
    bu get-command          list commands and their output fields
    bu get-module           list loaded modules
    docs/structured_output.md   the full guide (docs/structured_output.md)
EOF
