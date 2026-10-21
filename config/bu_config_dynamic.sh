# shellcheck source=./bu_config_static.sh
source "$BU_NULL"

# Settings of the built-in config phase "main", registered here and nowhere
# else: the entrypoint resolves them after this file (exported values >
# settings files > the registered --default) and assigns them from a vars
# file generated from these registrations (see "Settings precedence and
# provenance" in docs/technical_reference.md).

# ```
# Whether to ignore cache when running bu_cached_execute
# ```
bu_config_register BU_INVALIDATE_CACHE --bool --default false \
    --hint "Ignore cache when running bu_cached_execute"

# ```
# The log-level when running commands
# ```
bu_config_register BU_LOG_LVL --default "$BU_LOG_LVL_WARN" \
    --enum trace:"$BU_LOG_LVL_TRACE" debug:"$BU_LOG_LVL_DEBUG" info:"$BU_LOG_LVL_INFO" warn:"$BU_LOG_LVL_WARN" err:"$BU_LOG_LVL_ERR" silence:"$BU_LOG_LVL_SILENCE" enum-- \
    --hint "Log level when running commands"

# ```
# The log-level when hitting TAB.
# In general, this should only log errors to avoid cluttering the
# autocomplete suggestions.
# ```
bu_config_register BU_AUTOCOMPLETE_LOG_LVL --default "$BU_LOG_LVL_ERR" \
    --enum trace:"$BU_LOG_LVL_TRACE" debug:"$BU_LOG_LVL_DEBUG" info:"$BU_LOG_LVL_INFO" warn:"$BU_LOG_LVL_WARN" err:"$BU_LOG_LVL_ERR" silence:"$BU_LOG_LVL_SILENCE" enum-- \
    --hint "Log level during autocomplete (keep at err to avoid cluttering suggestions)"

bu_config_register BU_AUTOCOMPLETE_BIND_FZF_DISPLAY_METADATA --bool --default true \
    --hint "Show color-coded metadata (type tags, sizes) in fzf completion"

bu_config_register BU_AUTOCOMPLETE_BIND_TAB_TO_FZF --bool --default true \
    --hint "Bind Tab to BashTab completion, shown by BU_AUTOCOMPLETE_TAB_BACKEND (Alt-Z toggles per session)"

# ```
# How BashTab Tab completion shows its candidates (all three use the same
# completion engine):
# - fzf:       fzf dropdown placed under the word being completed, with a
#              preview pane for long descriptions
# - fzf-cheap: fzf dropdown on the prompt row; skips the terminal queries,
#              stty/tput calls and prompt rendering that placing it takes
# - readline:  readline's own candidate list, with descriptions; honours
#              inputrc settings and needs no fzf
# The fzf backends fall back to readline when fzf is not installed.
# ```
bu_config_register BU_AUTOCOMPLETE_TAB_BACKEND --default fzf \
    --enum fzf fzf-cheap readline enum-- \
    --hint "Tab completion UI: fzf (dropdown under the word), fzf-cheap (dropdown on the prompt row, fewer processes), readline (native list with descriptions)"

# ```
# Use tree-sitter-bash (via node daemon) for command-line parsing
# in fzf autocomplete instead of the built-in bash parser.
# Provides more accurate cursor-position tracking and syntax awareness.
# ```
bu_config_register BU_AUTOCOMPLETE_USE_TREE_SITTER --bool --default false \
    --hint "Use tree-sitter-bash (node daemon) for command-line parsing in fzf autocomplete"

# Default output format for `bu out` / `bu * --format auto` when stdout is
# not a terminal can be overridden here. One of: table, list, json, jsonl, tsv, csv, markdown, html
# Empty means: table on a terminal, jsonl otherwise.
bu_config_register BU_OUTPUT_FORMAT \
    --enum auto table list json jsonl tsv csv markdown html enum-- \
    --hint "Default output format when stdout is not a terminal (empty: table on tty, jsonl when piped)"

# query-object execution backend. Keep the original shell pipeline available;
# combined evaluates all query clauses in one jq process before Out-Default.
bu_config_register BU_QUERY_EXECUTOR --default pipeline \
    --enum pipeline combined enum-- \
    --hint "Query executor: pipeline (separate stages) or combined (one jq evaluator)"

# Pager for tabular output. When set and stdout is a terminal,
# bu_format_table pipes output through this command.
#   "less" / "preset:less" → less -FRX; "bat" → bat --paging=always
#   "never" / "preset:never" → cat (no paging)
#   "less -FRX"     → custom command, used verbatim
bu_config_register BU_TABLE_PAGER --default "preset:less" \
    --presets less less-quit bat never presets-- \
    --hint "Pager: less, less-quit, bat, never (preset names), preset:NAME (explicit), or a custom command. Empty disables."

# Default table display style for `bu format-table` / `bu out --format table`.
# Overridable per-invocation with --style. One of: classic, plain, ascii,
# unicode, double, markdown, mysql, psql.
bu_config_register BU_TABLE_STYLE --default unicode \
    --enum classic plain ascii unicode double clickhouse markdown mysql psql enum-- \
    --hint "Table border/separator style for bu format-table"

# Allow pipeline field completion to execute the pipeline prefix being typed
# ("probing") to discover record fields from live output. Off by default:
# only producers in BU_OUT_PROBE_COMMANDS are ever executed.
bu_config_register BU_OUT_PROBE_PIPELINE --bool --default false \
    --hint "Allow pipeline field completion to execute the pipeline prefix (probing)"

# When true, pipeline consumers that declare a `# Requires-All:` /
# `# Requires-Any:` field contract apply the configured record validation.
# Defaults warn on the first record (see __bu_out_strict_guard).
bu_config_register BU_OUT_STRICT --bool --default true \
    --hint "Enable validation of pipeline consumers' declared field contracts"

# Keep BU_OUT_STRICT=false as the legacy master switch.
bu_config_register BU_OUT_VALIDATION --default warn \
    --enum off warn error enum-- \
    --hint "Record contract validation: off, warn and pass through, or reject invalid records"
bu_config_register BU_OUT_VALIDATE_RECORDS --default first \
    --enum first all enum-- \
    --hint "Check required fields on the first record or every record"

# ```
# Show the active top-level module name in PS1, like Python venvs.
# When enabled, PS1 is prefixed with e.g. "[myproject] ".
# ```
bu_config_register BU_PROMPT_SHOW_MODULE --bool --default true \
    --hint "Show the active top-level module name in the shell prompt (PS1)"

# ```
# When true, expose every source/execute command as a bare shell function
# (e.g. `get-command` instead of `bu get-command`), with Tab completion.
# ```
bu_config_register BU_EXPOSE_COMMANDS --bool --default false \
    --hint "Expose commands as bare shell functions with Tab completion"

# ```
# How the exit-handler traceback is rendered when a command fails.
#   short - one compact line per stack frame
#   full  - Python-style frames plus the surrounding source lines (default)
# The number of context lines shown by "full" is BU_STACKTRACE_CONTEXT_LINES
# (a tunable global in bu_core_base.sh; not registered because it is a plain
# integer).
# ```
bu_config_register BU_STACKTRACE_STYLE --default full \
    --enum short full enum-- \
    --hint "Traceback rendering style (short: one line per frame, full: source context)"

# ```
# Directory for remote-session ControlMaster sockets (see bu_core_remote.sh).
# Socket paths must stay under the ~100-byte unix sun_path limit, so a long
# BU_OUT_DIR should be paired with a short override here.
# ```
bu_config_register BU_REMOTE_SSH_DIR --default "$BU_OUT_DIR/ssh" \
    --hint "Directory for remote-session ControlMaster sockets"
