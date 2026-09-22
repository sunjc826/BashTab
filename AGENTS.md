# AGENTS.md

This file provides guidance to AI coding agents (Claude Code, pi, etc.) when working with code in this repository.

## Project Overview

BashTab is a Bash scripting framework providing intelligent autocompletion, argument parsing, IDE integration, and modern CLI tools. It stays 100% in Bash with no DSL or YAML conversion.

## Common Commands

### Testing

```bash
# Initialize test submodules (first time only)
git submodule update --init

source ./activate -t
```

Do **not** run the full test suite locally — it takes extremely long on a
normal machine (anything less than ~64-way parallelism is impractical).
Leave full-suite runs to CI.

Even a single `.bats` file can be very slow, so **handpick individual test
cases** with `--filter` instead of running a whole file:

```bash
# One test function
bats --filter 'test_bu_query_object_grep_regex_any_field' ./test/out_test.bats

# A few related tests by regex
bats --filter 'grep|query_object' ./test/out_test.bats
```

Only test what your change touches.

### Development Environment

```bash
source ./activate           # Standard activation
source ./activate -e        # Load examples environment
source ./activate -t        # Load test environment
```

### Build Single-File Distribution

```bash
source ./activate --__bu-inline ./inline.sh
```

## Architecture

### Core Modules (`/lib/core/`)

- **bu_core_base.sh** - Core utilities (filesystem, logging, string manipulation, arrays, caching)
- **bu_core_autocomplete.sh** - Autocompletion generation with lazy loading and script parsing
- **bu_core_cli.sh** - CLI command routing
- **bu_core_preinit.sh** - Pre-initialization for registering commands, key bindings, aliases
- **bu_core_tmux.sh** - Tmux orchestration and job management
- **bu_core_var.sh** - Global variable initialization

### Initialization Flow

1. `bu_entrypoint.sh` - Main entry point that orchestrates loading
2. Parses `BU_MODULE_LIST` (the sole module registry)
3. Loads static config (`config/bu_config_static.sh`)
4. Loads dynamic config (`config/bu_config_dynamic.sh`)
5. Sources all core modules
6. Runs pre-init callbacks, then main init, then post-entrypoint callbacks

### ⚠️ Custom `source` Function (read this before writing sourced files)

After activation, `source` is **not the bash builtin** — `bu_custom_source.sh`
replaces it with a function (`bu_def_source`) that adds `--__bu-once`,
autopushd, and inline-build support. One critical consequence:

**Any file sourced through it executes inside that function's scope.** A
top-level `declare` (without `-g`) in a sourced file therefore creates a
**function-local variable that vanishes when `source` returns**. The failure
is silent: the globals you declared are simply missing afterwards.

```bash
# ✗ BROKEN in sourced files — becomes a local of the source() function,
#   lost as soon as source returns
declare -r MY_CONST=$'\e'
declare -A MY_MAP=()
declare -i MY_COUNTER=0

# ✓ CORRECT — global declarations survive
declare -g -r MY_CONST=$'\e'
declare -A -g MY_MAP=()
declare -g -i MY_COUNTER=0

# ✓ ALSO FINE — plain assignments create/modify globals even inside a function
MY_SCALAR=value
MY_ARRAY=(a b c)
# (but associative arrays and readonly REQUIRE declare, so use -g for those)
```

**Symptoms of a missing `-g`:** `declare: VAR: not found` after sourcing;
escape sequences printed literally (`[1m` instead of bold text); unset
variables silently treated as `0`/`""` in arithmetic and expansions.

Escape hatches: `builtin source file.sh` bypasses the wrapper entirely;
`bu_ext_source` temporarily undefines it. Check at runtime with
`[[ "$BU_SOURCE_IS_CUSTOM" == true ]]`.

### Commands (`/commands/`)

Scripts named `bu-*.sh` that can be invoked via:
- `bu verb-noun ...`
- `bu-verb-noun.sh ...` (direct executable)

Command types: `execute` (new process), `source` (current shell), `function` (bash function)

## Creating New Commands

Use `bu new-command --dir commands --name my-command` to generate from template.

### Command Structure

All commands follow this pattern (see `lib/templates/script_template.sh`):

```bash
#!/usr/bin/env bash
function __bu_SCRIPT_NAME_main()
{
# 1. Setup: get script location, pushd to script dir
local -r invocation_dir=$PWD
local script_name script_dir
# ... path parsing ...
pushd "$script_dir" &>/dev/null

# 2. Source entrypoint (executable scripts only, skipped during autocomplete)
if [[ -z "$COMP_CWORD" ]]; then
    source "$BU_DIR"/bu_entrypoint.sh
fi

# 3. Initialize scope management
bu_exit_handler_setup
bu_scope_push_function
bu_scope_add_cleanup bu_popd_silent
bu_run_log_command "$@"

# 4. Declare local variables for options
local my_option=
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=

# 5. Parse arguments in while loop
while (($#)); do
    bu_parse_multiselect $# "$1"
    case "$1" in
    -o|--option)# OPTION_HINT
        # Help text for this option (shown in autohelp)
        bu_parse_positional $# --hint "description"
        my_option=${!shift_by}
        ;;
    -f|--flag)# _FLAG
        # Help text for flag
        is_flag=true
        ;;
    -h|--help)# _FLAG
        is_help=true
        ;;
    *)
        bu_parse_error_enum "$1"
        break
        ;;
    esac
    if "$is_help"; then break; fi
    if (( $# < shift_by )); then
        bu_parse_error_argn "$1" $#
        break
    fi
    shift "$shift_by"
done

# 6. Handle autocomplete
if bu_env_is_in_autocomplete; then
    bu_autocomplete
    return 0
fi

# 7. Handle help
if "$is_help"; then
    bu_autohelp
    return 0
fi

# 8. Main logic here

# 9. Cleanup
bu_scope_pop_function
}

__bu_SCRIPT_NAME_main "$@"
```

### Aliases in Case Patterns (Autocomplete)

Alternatives in one case pattern that normalize to the same token (strip leading `-`/`+`, lowercase) are treated as **aliases**: `--select|select` shows a single completion row (first form wins, switching to a typed prefix), metadata shows `aka <other forms>`, and using any form excludes the group. Alternatives that differ after normalization (e.g. `-v|--verb`) are not merged — they stay separate rows with the legacy short/long exclusion. Put the preferred insert form first in the pattern.

### Comments in Case Statements (Autohelp Only)

Comments after case patterns are **purely for autohelp generation** and have no runtime effect:
- `# HINT` after case pattern - displayed in autocomplete preview
- `# _FLAG` - marks option as a flag (no argument)
- Comment lines below the case pattern - help text shown in `--help` output

Runtime behavior is determined solely by `bu_parse_*` function calls.

### Parsing Functions

**`bu_parse_multiselect $# "$1"`** - Called at start of each case iteration. Tracks which options have been parsed to exclude them from future autocomplete suggestions. Sets `shift_by=1`. During autocomplete, it invokes an awk parser to extract all options from the enclosing case-esac block (via `--options-at FILE LINE`).

**`bu_parse_positional $# [DSL_ARGS...]`** - Parses the next positional argument. Increments `shift_by`. The value is accessed via `${!shift_by}`. DSL arguments control autocomplete behavior.

**`bu_parse_nested impl_func`** - Delegates parsing to another function for subcommand handling.

**`bu_parse_command_context --marker`** - Parses arguments until `marker--` is found, used for recursive command invocation.

**`bu_validate_positional "${!shift_by}"`** - Validates the parsed value against the autocompletion DSL (used after `--enum`).

### Autocomplete DSL

Arguments to `bu_parse_positional` are processed by `__bu_autocomplete_completion_func_master_helper`. Key DSL options:

| DSL Argument | Description |
|--------------|-------------|
| `--hint "text"` | Display hint text during autocomplete |
| `--enum val1 val2 ... enum--` | Offer literal values as completions |
| `:literal` | Add literal string (colon prefix, Ruby symbol style) |
| `--stdout cmd arg1 ... stdout--` | Run command, use stdout lines as completions |
| `--ret func arg1 ... ret--` | Run function, use `BU_RET` array as completions |
| `--options-at FILE LINE` | Parse case block at location for option completions |
| `--as-if cmd subcmd ... as-if--` | Delegate to another command's autocomplete |
| `--delimited [--delimiter X] opt1 opt2 ... delimited--` | Comma-delimited multiselect; excludes already-selected tokens, auto-hint shows available options |
| `-a/--ansi COLOR` | Apply ANSI color to completions |

Example usages from commands:
```bash
# Enum with validation
bu_parse_positional $# --enum function execute source alias enum--
bu_validate_positional "${!shift_by}"

# Directory completion
bu_parse_positional $# "${BU_AUTOCOMPLETE_SPEC_DIRECTORY[@]}"

# Hint only
bu_parse_positional $# --hint "Name of the script"
```

### Sourceable vs Executable Scripts

**Executable** (`script_template.sh`): Sources `bu_entrypoint.sh`, uses `bu_exit_handler_setup`

**Sourceable** (`source_script_template.sh`): Assumes entrypoint already loaded, sources `$BU_NULL` for shellcheck

## Bash Style Guide

### Collections

Use **arrays**, not space-delimited strings, for any collection of values:

```bash
# ✓ Good — array
BU_OUT_FORMATS=(auto table list json jsonl tsv)

# ✗ Avoid — string with implicit word splitting
BU_OUT_FORMATS="auto table list json jsonl tsv"
```

When passing an array to a command, use `"${arr[@]}"` (preserves individual elements):

```bash
bu_parse_positional $# --enum "${BU_OUT_FORMATS[@]}" enum--
```

When iterating, use `"${arr[@]}"`:

```bash
for item in "${items[@]}"; do ...; done
```

When joining for display, use `${arr[*]}` (joins with first character of IFS, typically space).

### Variables

- **Global variables**: `BU_*` prefix, declare with `declare -g` or `declare -A -g` — the `-g` is **required**, not stylistic (see "Custom `source` Function" above)
- **Local variables**: Always `local`, use `local -r` when the value never changes after initialization
- **Return values**: `BU_RET` for strings/arrays, `BU_RET_MAP` for associative arrays
- **Constants**: `declare -r -g` at global scope (`-g` required for the same reason)

Declare locals at the top of the function, not scattered throughout:

```bash
# ✓ Good
function my_func() {
    local name=
    local -a items=()
    local is_verbose=false
    ...
}
```

### `set -e` safety

Every script and function in this codebase may be sourced from a user's shell
that runs `set -e` (or `set -o errexit`).  Any non-zero return from a function
called at the top level of a sourced script will **abort the entire sourcing**
and kill the user's shell session.

**Rules for shared-codepath functions:**

1. Functions that can "fail normally" (cache miss, key not set, optional feature
   unavailable) must **always return 0**.  Log a warning, not an error.
2. At the call site in entrypoint/init scripts, guard with `|| true` even when
   the function returns 0 — defensive redundancy:
   ```bash
   __bu_try_load_command_cache || true
   ```
3. Only `return 1` from functions where failure is genuinely exceptional and
   should abort — and only when called from a non-sourced context.
4. The `bu_entrypoint.sh` script ends with `return 0` specifically to contain
   any leaked non-zero status from earlier commands under `set -e`.

**Checklist before writing a function used in init/entrypoint:**
- [ ] Could this be sourced from a shell with `set -e`? (yes, always)
- [ ] Does any code path return non-zero for a non-fatal reason? → change to `return 0`
- [ ] Is the call site guarded with `|| true`?
- [ ] Any `((counter++))` increment from 0? → use `: $((counter++))` instead (bare arithmetic returns 1 when the expression evaluates to 0, which aborts under `set -e`)

### Quoting

Always quote variable expansions unless you explicitly want word splitting:

```bash
# ✓ Good
bu_log_err "$error_msg"
"$command" "${args[@]}"

# ✗ Avoid — unquoted expansion
bu_log_err $error_msg
```

### Case Statements

Keep case patterns simple. Use `# _FLAG` for flags, `# HINT` for positional hints:

```bash
case "$1" in
    -h|--help)# _FLAG
        is_help=true
        ;;
    --format)# FORMAT
        bu_parse_positional $# --enum "${BU_OUT_FORMATS[@]}" enum--
        format=${!shift_by}
        ;;
    *)
        bu_parse_error_enum "$1"
        ;;
esac
```

### Indentation

4-space indentation. No tabs.

### Function Naming

- Public API: `bu_*` prefix
- Private/internal: `__bu_*` prefix



## Key Argument Parsing Functions

- `bu_parse_positional` - Positional arguments
- `bu_parse_multiselect` - Keyword arguments
- `bu_parse_nested` - Subparsers
- `bu_parse_nested_multiselect` - Repeatable subcommand options
- `bu_parse_nested_multiselect_stay` - Repeatable subcommand options (stay in multiselect)
- `bu_parse_command_context` - Recursive command calls

These functions unify parsing, autocompletion, and variable binding.

## Structured Output (JSONL pipeline)

PowerShell-inspired: JSONL (one JSON object per line) is the object stream, jq is the backend. Implemented in `lib/core/bu_core_out.sh`.

- **Recordifiers**: `bu_out_record k=v` / `k:=v` (typed), `bu_out_from_tsv --columns`, `bu_out_from_lines --column`
- **Transforms**: `bu_out_where '<jq expr>'`, `bu_out_select a,b=version`, `bu_out_sort_by key [--desc]`
- **Sinks**: `bu_format_table` (auto-width, `--stream`, `--colors`), `bu_format_list`, `bu_format_json`, `bu_format_jsonl`, `bu_format_tsv`
- **Dispatcher**: `bu_out` — Out-Default. Resolution: `--format` > `BU_OUTPUT_FORMAT` > TTY (table) vs pipe (jsonl)

Command pattern (zero forks in the loop):
```bash
{
    for entry in "${entries[@]}"; do
        printf '%s\t%s\t%s\n' "$name" "$version" "$path"
    done
} | bu_out_from_tsv --columns name,version,path | bu_out --format "$format"
```

Commands expose `--format` (enum: auto table list json jsonl tsv) and `--columns` (supports `key:Label` display labels). Cmdlet wrappers usable in any pipeline: `bu new-record`, `bu convert-from-tsv`, `bu convert-from-lines`, `bu where`, `bu select`, `bu sort`, `bu format-table`, `bu format-list`, `bu convert-to-json`, `bu convert-to-jsonl`, `bu convert-to-tsv`, `bu out-default`. Cmdlets implicitly end at Out-Default (pipe through `bu_out`): a table on a terminal, JSONL when piped. The underlying functions stay pure JSONL. `bu query-object` composes the transforms SQL-style with bare or dashed clause keywords (`where`/`select`/`order-by`/`desc`/`first`, any order; execution is WHERE→GROUP BY→HAVING→SELECT→ORDER BY→FIRST). Grouping: `group-by verb agg count,avg:hp` (`[name=]func[:field]`, repeatable/comma-separated; funcs: count sum avg min max first last collect), `having` filters groups, no `agg` = DISTINCT keys. `distinct` (also `bu distinct-object`) dedupes whole records after projection, order-preserving.

Command names support multi-word verbs via `BU_MULTI_WORD_VERBS` (default: `convert-to`, `convert-from`), so `convert-to-jsonl` parses as verb=`convert-to`, noun=`jsonl`.

After a pipe, field-aware completion suggests producer record fields for `select`/`where`/`sort` and sink `--columns`: static registry `BU_OUT_PRODUCER_FIELDS` (extend with `bu_register_output_fields`), opt-in live probing via `BU_OUT_PROBE_PIPELINE` + `BU_OUT_PROBE_COMMANDS`.

See `docs/structured_output.md` for the full guide.

## Extension Mechanisms

Register via pre-init functions:
- `bu_preinit_register_user_defined_key_binding`
- `bu_preinit_register_user_defined_completion_func`
- `bu_preinit_register_user_defined_subcommand_dir`
- `bu_preinit_register_user_defined_subcommand_file`
- `bu_preinit_register_user_defined_subcommand_function`
- `bu_preinit_register_new_alias`

### Module System

`BU_MODULE_LIST` is the sole module registry — an exported scalar of the form
`"name:version:preinit_path;..."`.  Top-level projects set it in their
`activate` script; library dependencies append to it in their module scripts.

```bash
# Top-level activate (sets the initial list):
export BU_MODULE_LIST="myproject:0.1.0:/path/to/preinit.sh;"

# Library module script (appends):
BU_MODULE_LIST+="libname:0.1.0:/path/to/lib_preinit.sh;"
```

`bu_entrypoint.sh` calls `__bu_parse_module_list` which dedupes by name,
populates `BU_MODULE_REGISTRY` for `bu get-module`, and registers each
preinit callback to be sourced during init.

- `bu new-module --name myapp` — scaffold a module
- `bu get-module` — list loaded modules with name, version, path

### Tree-sitter Daemon

- `lib/bin/bu_ts_daemon.js` — Node.js daemon using tree-sitter-bash for CST parsing
- `lib/core/bu_core_ts.sh` — bash wrapper using `coproc`, exposes `bu_ts_parse()`
- Toggle: `BU_AUTOCOMPLETE_USE_TREE_SITTER=true` (default `false`)
- Handles pipes, command substitutions, variable expansions, returns range-based replacements
- Grammar resolution goes through `lib/grammar/load.js`, never `require("tree-sitter-bash")` directly

### Grammar fork (`lib/grammar/`)

`tree-sitter-bash` rejects constructs that are valid bash. That hurts completion
most, because it parses command lines the user types — which cannot be rewritten
to suit the grammar. `lib/grammar/patches.js` carries a small patch set against
the installed upstream grammar; only that file is committed, everything else is
generated into the gitignored `lib/grammar/build/`.

```sh
node lib/grammar/build.js    # optional, needs a C toolchain
node lib/grammar/test.js     # regression sweep + cause expectations
```

The fork is optional: `load.js` falls back to the stock parser, and the linter
then reports the gaps as `BU000` instead. Before adding a patch, read
`lib/grammar/README.md` — in particular, **always run the regression sweep**: a
one-line patch that fixed its own repro silently broke `for ((i=0; i<3; i++))`,
and only the sweep caught it.

### Linting (`bu validate-script`)

`bu validate-script --all` checks the invariants bash cannot express and
shellcheck does not know about (errexit-aborting arithmetic, file-scope
`declare` without `-g`, case-annotation/parser mismatches, header windows).
Rules live in `lib/lint/bu_lint.js` and match on the CST, not on text.
`.bulintbaseline` records pre-existing findings so CI fails only on new ones;
regenerate it with `bu validate-script --all --write-baseline .bulintbaseline`.

### fzf Autocomplete Display

- `__bu_fzf_compute_dimensions` — shared dimension calculation (tested 40–200 cols)
- `__bu_file_metadata_append` — color-coded file hints (type tag + size + symlink)
- `__bu_synopsis_color` — compact option type tags (flag/enum/str)
- Preview panel only opens when metadata overflows box width

## Project Integration Pattern

BashTab modules follow Rust's library/binary model:

| Role | Entrypoint | Has `BU_TOP_LEVEL_MODULE` | Calls `bu_mark_load_complete` |
|------|-----------|---------------------------|-------------------------------|
| **Binary** (top-level) | `activate` | yes — set before sourcing entrypoint | yes — saves command cache |
| **Library** (dependency) | `*_bu_module.sh` (appends to `BU_MODULE_LIST`) | no — inherits parent's | no — parent handles caching |

A module can be used either way. Its `activate` makes it a standalone "binary"; its `*_bu_module.sh` lets another project consume it as a library.

### Setup (as binary / standalone project)

1. Add BashTab as git submodule (`deps/bash-tab`)
2. Run `bu new-module --name myproject` to scaffold module
3. Customize `myproject_bu_preinit.sh` for your commands
4. Add commands: `bu new-command --dir myproject/commands --name my-cmd`
5. Users `source ./myproject/activate` to enter the environment

### Setup (as library / dependency of another project)

1. Append your module entry to `BU_MODULE_LIST` in the host project's activate
2. The host project's `activate` sets its own `BU_TOP_LEVEL_MODULE`
3. Your preinit callbacks run during the host's initialization
4. Your commands appear alongside the host's — all cached under the host's key

### Cache lifecycle

```bash
# In the top-level activate script:
export BU_TOP_LEVEL_MODULE="myproject"   # set BEFORE sourcing
source "$BU_DIR"/bu_entrypoint.sh        # loads cache if it exists
bu_mark_load_complete                     # saves cache (no-op if loaded)
```

- **First activation**: full scan → saves cache to `$BU_CACHE_DIR/commands-myproject.cache`
- **Subsequent**: loads from cache, skips the `find` + `--is-compatible` probe entirely
- **After adding/removing commands**: `bu clear-cache myproject` then re-activate
- **List caches**: `bu get-cache`
- **Disable caching**: set `export BU_COMMAND_CACHE_ENABLED=false` before sourcing (forces scan-always-fresh for dynamic module systems)
- **Relocate output**: set `export BU_OUT_DIR=/path/to/dir` before sourcing; BU_CACHE_DIR, BU_LOG_DIR, BU_TMP_DIR, and BU_HISTORY all derive from it

## Code Documentation

Use triple backtick markdown format for bash-language-server compatibility:
```bash
# ```md
# Description of function
#
# Params:
# - $1: description
#
# Returns:
# - BU_RET: description
# ```
function bu_example() { ... }
```

## Key Utilities

**Scope management (RAII-like cleanup)**:
- `bu_scope_push_function` / `bu_scope_pop_function`
- `bu_scope_add_cleanup`

**I/O conversion**:
- `bu_ret_to_stdout` / `bu_stdout_to_ret`

**Filesystem**:
- `bu_mkdir`, `bu_realpath`, `bu_basename`, `bu_dirname`

**Logging**:
- `bu_log_info`, `bu_log_err`, `bu_log_warn`


## MacOS

Setup steps
```bash
brew install bash
brew install findutils
brew install bash-completion@2
brew install fzf
```

