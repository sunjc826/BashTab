# shellcheck source=./bu_config_static.sh
source "$BU_NULL"

# Each setting is first declared with `bu_config_register` (metadata driving
# `bu set-config` validation/completion/listing), then assigned with
# ${VAR:-registered-default}: values set earlier (environment, or the
# machine-local config/bu_config_local.sh via `bu set-config`) take precedence.

# ```
# Whether to ignore cache when running bu_cached_execute
# ```
bu_config_register BU_INVALIDATE_CACHE --bool --default false \
    --hint "Ignore cache when running bu_cached_execute"
BU_INVALIDATE_CACHE=${BU_INVALIDATE_CACHE:-${BU_CONFIG_PROPERTIES[BU_INVALIDATE_CACHE,default]}}

# ```
# The log-level when running commands
# ```
bu_config_register BU_LOG_LVL --default "$BU_LOG_LVL_WARN" \
    --enum trace:"$BU_LOG_LVL_TRACE" debug:"$BU_LOG_LVL_DEBUG" info:"$BU_LOG_LVL_INFO" warn:"$BU_LOG_LVL_WARN" err:"$BU_LOG_LVL_ERR" silence:"$BU_LOG_LVL_SILENCE" enum-- \
    --hint "Log level when running commands"
BU_LOG_LVL=${BU_LOG_LVL:-${BU_CONFIG_PROPERTIES[BU_LOG_LVL,default]}}

# ```
# The log-level when hitting TAB.
# In general, this should only log errors to avoid cluttering the
# autocomplete suggestions.
# ```
bu_config_register BU_AUTOCOMPLETE_LOG_LVL --default "$BU_LOG_LVL_ERR" \
    --enum trace:"$BU_LOG_LVL_TRACE" debug:"$BU_LOG_LVL_DEBUG" info:"$BU_LOG_LVL_INFO" warn:"$BU_LOG_LVL_WARN" err:"$BU_LOG_LVL_ERR" silence:"$BU_LOG_LVL_SILENCE" enum-- \
    --hint "Log level during autocomplete (keep at err to avoid cluttering suggestions)"
BU_AUTOCOMPLETE_LOG_LVL=${BU_AUTOCOMPLETE_LOG_LVL:-${BU_CONFIG_PROPERTIES[BU_AUTOCOMPLETE_LOG_LVL,default]}}

bu_config_register BU_AUTOCOMPLETE_BIND_FZF_DISPLAY_METADATA --bool --default true \
    --hint "Show color-coded metadata (type tags, sizes) in fzf completion"
BU_AUTOCOMPLETE_BIND_FZF_DISPLAY_METADATA=${BU_AUTOCOMPLETE_BIND_FZF_DISPLAY_METADATA:-${BU_CONFIG_PROPERTIES[BU_AUTOCOMPLETE_BIND_FZF_DISPLAY_METADATA,default]}}

bu_config_register BU_AUTOCOMPLETE_BIND_TAB_TO_FZF --bool --default true \
    --hint "Bind Tab to fzf completion (Alt-Z toggles per session)"
BU_AUTOCOMPLETE_BIND_TAB_TO_FZF=${BU_AUTOCOMPLETE_BIND_TAB_TO_FZF:-${BU_CONFIG_PROPERTIES[BU_AUTOCOMPLETE_BIND_TAB_TO_FZF,default]}}

# ```
# Verbose bootstrap logging ("sourcing ..." lines during activation).
# Read before this file is loaded, so it only takes effect from the
# environment or config/bu_config_local.sh, not from editing this file.
# ```
bu_config_register BU_BOOTSTRAP_VERBOSE --bool --default false \
    --hint "Verbose logging during activation bootstrap (set via bu set-config)"
BU_BOOTSTRAP_VERBOSE=${BU_BOOTSTRAP_VERBOSE:-${BU_CONFIG_PROPERTIES[BU_BOOTSTRAP_VERBOSE,default]}}

# ```
# Use tree-sitter-bash (via node daemon) for command-line parsing
# in fzf autocomplete instead of the built-in bash parser.
# Provides more accurate cursor-position tracking and syntax awareness.
# ```
bu_config_register BU_AUTOCOMPLETE_USE_TREE_SITTER --bool --default false \
    --hint "Use tree-sitter-bash (node daemon) for command-line parsing in fzf autocomplete"
BU_AUTOCOMPLETE_USE_TREE_SITTER=${BU_AUTOCOMPLETE_USE_TREE_SITTER:-${BU_CONFIG_PROPERTIES[BU_AUTOCOMPLETE_USE_TREE_SITTER,default]}}

# Default output format for `bu out` / `bu * --format auto` when stdout is
# not a terminal can be overridden here. One of: table, list, json, jsonl, tsv
# Empty means: table on a terminal, jsonl otherwise.
bu_config_register BU_OUTPUT_FORMAT \
    --enum auto table list json jsonl tsv enum-- \
    --hint "Default output format when stdout is not a terminal (empty: table on tty, jsonl when piped)"
BU_OUTPUT_FORMAT=${BU_OUTPUT_FORMAT:-}

# Pager for tabular output. When set and stdout is a terminal,
# bu_format_table pipes output through this command.
#   "preset:less"   → less -R      "preset:bat" → bat --paging=always
#   "preset:never"  → cat (no paging)
#   "less -R"       → custom command, used verbatim
bu_config_register BU_TABLE_PAGER --default "preset:less" \
    --presets less less-quit bat never presets-- \
    --hint "Pager for tabular output (preset:less, preset:bat, or a custom command). Empty disables."
BU_TABLE_PAGER=${BU_TABLE_PAGER:-"preset:less"}

# Default table display style for `bu format-table` / `bu out --format table`.
# Overridable per-invocation with --style. One of: classic, plain, ascii,
# unicode, double, markdown, mysql, psql.
bu_config_register BU_TABLE_STYLE --default unicode \
    --enum classic plain ascii unicode double clickhouse markdown mysql psql enum-- \
    --hint "Table border/separator style for bu format-table"
BU_TABLE_STYLE=${BU_TABLE_STYLE:-${BU_CONFIG_PROPERTIES[BU_TABLE_STYLE,default]}}

# Allow pipeline field completion to execute the pipeline prefix being typed
# ("probing") to discover record fields from live output. Off by default:
# only producers in BU_OUT_PROBE_COMMANDS are ever executed.
bu_config_register BU_OUT_PROBE_PIPELINE --bool --default false \
    --hint "Allow pipeline field completion to execute the pipeline prefix (probing)"
BU_OUT_PROBE_PIPELINE=${BU_OUT_PROBE_PIPELINE:-${BU_CONFIG_PROPERTIES[BU_OUT_PROBE_PIPELINE,default]}}

# When true, pipeline consumers that declare a `# Requires-All:` /
# `# Requires-Any:` field contract warn to stderr when the upstream record
# does not satisfy it (see __bu_out_strict_guard in bu_core_out.sh).
bu_config_register BU_OUT_STRICT --bool --default true \
    --hint "Warn when a pipeline consumer's declared field contract is unmet by upstream records"
BU_OUT_STRICT=${BU_OUT_STRICT:-${BU_CONFIG_PROPERTIES[BU_OUT_STRICT,default]}}

# ```
# Show the active top-level module name in PS1, like Python venvs.
# When enabled, PS1 is prefixed with e.g. "[myproject] ".
# ```
bu_config_register BU_PROMPT_SHOW_MODULE --bool --default true \
    --hint "Show the active top-level module name in the shell prompt (PS1)"
BU_PROMPT_SHOW_MODULE=${BU_PROMPT_SHOW_MODULE:-${BU_CONFIG_PROPERTIES[BU_PROMPT_SHOW_MODULE,default]}}

# ```
# When true, expose every source/execute command as a bare shell function
# (e.g. `get-command` instead of `bu get-command`), with Tab completion.
# ```
bu_config_register BU_EXPOSE_COMMANDS --bool --default false \
    --hint "Expose commands as bare shell functions with Tab completion"
BU_EXPOSE_COMMANDS=${BU_EXPOSE_COMMANDS:-false}

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
BU_STACKTRACE_STYLE=${BU_STACKTRACE_STYLE:-${BU_CONFIG_PROPERTIES[BU_STACKTRACE_STYLE,default]}}

# ```
# Directory for remote-session ControlMaster sockets (see bu_core_remote.sh).
# Socket paths must stay under the ~100-byte unix sun_path limit, so a long
# BU_OUT_DIR should be paired with a short override here.
# ```
bu_config_register BU_REMOTE_SSH_DIR --default "$BU_OUT_DIR/ssh" \
    --hint "Directory for remote-session ControlMaster sockets"
BU_REMOTE_SSH_DIR=${BU_REMOTE_SSH_DIR:-${BU_CONFIG_PROPERTIES[BU_REMOTE_SSH_DIR,default]}}
