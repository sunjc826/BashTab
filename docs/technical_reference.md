---
layout: page
title: Technical Reference
permalink: /technical-reference/
nav_order: 5
---

## Using bu as a scripting dependency

The recommended way to use BashTab in your project is via the module system.

```sh
# 1. Add BashTab as a git submodule
git submodule add https://github.com/evagreendev/BashTab.git deps/bash-tab

# 2. Scaffold your module
source deps/bash-tab/activate
bu new-module --name myproject

# 3. Edit myproject/myproject_bu_preinit.sh, then activate
source ./myproject/activate
```

See the [Workflow Guide](how-to-02-BashTab-workflow) for a complete walkthrough.

### Legacy (manual registration)

The following variables and functions are used by libraries invoking BashTab to change its behavior at initialization time.

### Initialization variables
Bash variables are all strings/arrays of strings/maps of strings, alongside some variable attributes (e.g. number `-i`, readonly `-r` etc.) but we can interpret them differently.
These variables are "declared" (really, it's for bash-langugage server to give hints when hovering over them) in [bu_user_defined_decl.sh][bu_user_defined_decl].

The customizable variables all have the `BU_USER_DEFINED_` prefix.

Let us define the following conventional variable "types":

| Type | Description | Example |
|---|---|---|
| `Function` | The variable name refers to a shell function. | `bu_init() { ... }` |
| `AbsPath[A]` | Absolute path. `A` is an optional annotation describing the expected file type (for example, `ExecutableScript` or `SourceableScript`). |  |
| `ExecutableScript` | Annotation for `AbsPath` indicating the file is an executable script. | `/usr/local/bin/my-script` has type `AbsPath[ExecutableScript]` |
| `SourceableScript` | Annotation for `AbsPath` indicating the file is intended to be sourced. | `./bu_entrypoint.sh` has type `RelPath[SourceableScript]` |
| `RelPath[A]` | Relative path. `A` is an optional annotation like with `AbsPath`. | `scripts/myscript.sh` |
| `Path[A]` | Either `AbsPath[A]` or `RelPath[A]`. | `./lib/core/bu_core_base.sh` |
| `Int` | Integer value. | `42` |
| `Ref[T]` | A nameref to `T`, where `T` is some parameterized type. | `declare -n ref=executable_script_path_name` has type `Ref[Path[ExecutableScript]]` |
| `Array[T]` | Bash indexed array whose elements are of type `T`. | `BU_FOO=(one two three)` has type `Array[String]` <br> `BU_BAR=(1 2 3)` has type `Array[Int]` |
| `Map[K, V]` | Bash associative array mapping keys of type `K` to values of type `V`. | `declare -A m=([1]=one)` has type `Map[Int, String]` |
| `T1 \| T2` | Union Type of `T1` and `T2` | |

Variable list

| Variable | Type | Description |
|---|---|---|
| `BU_USER_DEFINED_STATIC_CONFIGS` | `Array[ Function \| Path[SourceableScript] ]` | Static user-defined configuration callback scripts/functions. These are sourced once during initialization. |
| `BU_USER_DEFINED_DYNAMIC_CONFIGS` | `Array[ Function \| Path[SourceableScript] ]` | Dynamic user-defined configuration callback scripts/functions. These are sourced every time the shell sources user-defined configs. |
| `BU_USER_DEFINED_STATIC_PRE_INIT_ENTRYPOINT_CALLBACKS` | `Array[ Function \| Path[SourceableScript] ]` | Static user-defined pre-initialization callback scripts/functions. These are sourced once before shell initialization. |
| `BU_USER_DEFINED_DYNAMIC_POST_ENTRYPOINT_CALLBACKS` | `Array[ Function \| Path[SourceableScript] ]` | Dynamic user-defined post-initialization callback scripts/functions. These are sourced after shell initialization. |
| `BU_USER_DEFINED_STATIC_POST_ENTRYPOINT_CALLBACKS` | `Array[ Function \| Path[SourceableScript] ]` | Static user-defined post-initialization callback scripts/functions. These are sourced once after shell initialization. |
| `BU_USER_DEFINED_DYNAMIC_POST_ENTRYPOINT_CALLBACKS` | `Array[ Function \| Path[SourceableScript] ]` | Dynamic user-defined post-initialization callback scripts/functions. These are sourced after shell initialization. |
| `BU_USER_DEFINED_COMPLETION_COMMAND_TO_KEY_CONVERSIONS` | `Array[Function]` | User-defined command-to-key conversion functions. These functions can customize how commands are converted to completion keys. |
| `BU_USER_DEFINED_AUTOCOMPLETE_HELPERS` | `Array[Function]` | User-defined autocomplete helper functions. These functions provide custom lazy autocompletion behavior. |
| `BU_USER_DEFINED_CLI_COMMAND_NAME` | `Function` | A custom command line name for `bu`. |

### Module registry

Modules register by appending to `BU_MODULE_LIST`, an exported scalar of the form
`"name:version:preinit_path;..."`.  `bu_entrypoint.sh` parses this (deduping by name),
sources each preinit, and populates `BU_MODULE_REGISTRY` for `bu get-module`.

```sh
# In a module script (appends):
BU_MODULE_LIST+="modname:0.1.0:/path/to/modname_bu_preinit.sh;"

# Or set directly in a top-level activate script:
export BU_MODULE_LIST="myproject:0.1.0:/path/to/preinit.sh;"
```

Host projects register library dependencies via `bu_module_require` (sourced
BEFORE `bu_entrypoint.sh`; dependency-free — builtins + git only, safe under
`set -e`/`set -u`):

```sh
source "$BU_DIR/lib/bu_module_require.sh"
bu_module_require somelib --dir "/path/to/somelib"          # opt-in by presence
bu_module_require otherlib --dir "/path" --required          # abort if missing
bu_module_require remotelib --dir "/path" --git-url "https://..." --branch main
```

It is idempotent (anchored match — `lib` vs `mylib` never collides), resolves
`<dir>/*_bu_module.sh` or an explicit `--module-file`, and verifies the script
actually registered the requested name.

This populates:

| Variable | Type | Description |
|---|---|---|
| `BU_MODULE_REGISTRY` | `Map[String, String]` | `name → "version:preinit_path"`. Available in current shell. |
| `BU_MODULE_LIST` | `String` (exported) | `"name:version:path;..."`. Deduped after parsing. Survives subshells for `bu get-module`. |

`bu get-module` reads `BU_MODULE_LIST` to display loaded modules with name, version, and path.

### Initialization callable functions
Another point of customization are the pre-init functions. They are found in [bu_core_preinit.sh][bu_core_preinit]. They all have the `bu_preinit_` prefix.

- `bu_preinit_register_user_defined_key_binding`:
  - Description: Register a key binding for interactive shells. Values are stored in `BU_KEY_BINDINGS` and later applied via `bind -x`. When called from a module preinit callback (where `BU_CURRENT_MODULE` is set), the owning module is stamped into `BU_KEY_BINDING_MODULES` so `bu` help can attribute the binding; core defaults are stamped `bu`.
  - Params: `$1` = key sequence (e.g. `\ee`), `$2` = command/function to invoke, `$3` (optional) = human-readable description shown in `bu` help.
  - Example: `bu_preinit_register_user_defined_key_binding '\em' my_custom_edit "Edit in my custom editor"`

- `bu_preinit_register_user_defined_completion_func`:
  - Description: Register a completion function for a specific command. Mappings are stored in `BU_AUTOCOMPLETE_COMPLETION_FUNCS` and used to call `complete -F`.
  - Params: `$1` = command name, `$2` = completion function name.
  - Example: `bu_preinit_register_user_defined_completion_func mycmd __mycmd_completion`

- `bu_preinit_register_user_defined_subcommand_dir`:
  - Description: Register a directory containing subcommand scripts. Optionally provide a conversion function to transform file names to `verb-noun` command names.
  - Params: `$1` = directory path, `...` = optional conversion function and args.
  - Example: `bu_preinit_register_user_defined_subcommand_dir ~/my-commands bu_convert_file_to_command_namespace prefix`

- `bu_preinit_register_user_defined_subcommand_file`:
  - Description: Register a single script file as a `bu` subcommand.
  - Params: `$1` = file path, `$2` (optional) = command name (derived from filename if omitted), `$3` (optional) = type (`function`, `execute`, `source`).
  - Example: `bu_preinit_register_user_defined_subcommand_file ~/scripts/get-status.sh get-status execute`

- `bu_preinit_register_user_defined_subcommand_function`:
  - Description: Register an in-shell function as a `bu` subcommand.
  - Params: `$1` = function name, `$2` (optional) = command name, `$3` (optional) = type.
  - Example: `bu_preinit_register_user_defined_subcommand_function my_helper_func my-helper function`

- `bu_preinit_register_new_alias`:
  - Description: Create a `bu` alias that expands a positional-style invocation into a named-argument command. Alias specs use `{}` for a single positional, `{...}` for remaining input, and `{?}` for optional remaining input.
  - Params: `$1` = alias name, `$2..` = alias spec (see `bu_preinit_register_new_alias` for syntax rules).
  - Example: `bu_preinit_register_new_alias gc get-command --namespace {} {?} --verb {} {?} --noun {} {...}`


## Development & Contributing

### Code structure
The core library is in [core][core]
- [bu_core_base.sh][bu_core_base] provides the core library functions for the framework
- [bu_core_autocomplete.sh][bu_core_autocomplete] provides the autocompletion functionality for the `bu` command and the scripts it invokes.

There are library functions that are not used by the core scripting framework, but are nonetheless useful in writing your own scripts.
- [bu_core_tmux.sh][bu_core_tmux] provides imperative utilities (`bu_spawn`) for orchestrating jobs across tmux panes.

### Running Tests

BashTab uses the [BATS (Bash Automated Testing System)](https://github.com/bats-core/bats-core) framework for unit testing.

```sh
git submodule update --init
source ./bu_test_entrypoint.sh
bats ./test/parse_bash_test.bats    # hand-written parser tests (54 tests)
bats ./test/ts_test.bats            # tree-sitter daemon tests (49 tests)
bats ./test/fzf_dims_test.bats      # fzf dimension calculation tests (14 tests)
bats ./test/out_test.bats           # structured output tests (38 tests)
bats ./test/traceback_test.bats     # exit-handler traceback rendering tests
```

### Exit handler & traceback styles

When a command fails under `errexit` (`bu_exit_handler_setup` enables `set -e -E`),
the exit handler in [bu_core_base.sh](../lib/core/bu_core_base.sh) prints a traceback
of the call stack. The rendering style is controlled by the registered setting
`BU_STACKTRACE_STYLE`:

| Value | Description |
|---|---|
| `short` | One compact line per frame: `0: false at script.sh:42` (default) |
| `full` | Python-style frames with the surrounding source lines, fault line highlighted |

```sh
# Compact (default)
bu set-config BU_STACKTRACE_STYLE short

# Verbose — show surrounding source lines
bu set-config BU_STACKTRACE_STYLE full
```

The `full` style renders each frame as a `File "...", line N, in func` header
followed by a source window. The number of lines shown before/after each frame
is `BU_STACKTRACE_CONTEXT_LINES` (default `2`), a tunable global in
`bu_core_base.sh` that can be exported before sourcing to widen the window:

```sh
export BU_STACKTRACE_CONTEXT_LINES=5
source ./activate
```

```
  File "/path/to/script.sh", line 42, in my_func
       40 │     local x=1
       41 │     x=$((x + 1))
  >    42 │     false
       43 │     cleanup
       44 │ }
```

Frames whose source file is missing or unreadable fall back to a single grey
`<source unavailable>` line rather than failing the exit handler.

The `full` style also applies a light, dependency-free syntax highlight to the
source lines: bash reserved words (violet), brackets/parens/braces (yellow),
comments (grey, falling back to blue on 8-colour terminals), and single/double
quoted strings (green). It is a single-pass highlighter, so it does not parse
nested `$((...))`/`${...}` constructs or heredocs — it trades a little precision
for zero dependencies and speed on the error path. When the terminal has no
colour support the codes degrade to empty and the source is shown plain.

### Tree-sitter daemon

Located at `lib/bin/bu_ts_daemon.js`. The bash wrapper `lib/core/bu_core_ts.sh` manages a `coproc` node process that accepts `CURSOR:LINE` input and returns JSON CST with:

| Field | Description |
|---|---|
| `cmdName` | Command name at cursor |
| `cmdWords` | Space-separated command words (unit separator delimited) |
| `pipeBefore` / `pipeAfter` | Text before/after the last pipe separator |
| `cursor.replaceStart/End/Text` | Range-based replacement (LSP TextEdit style) |
| `cursor.completeKind` | `command`, `dollar_word`, `dollar_brace` |

Toggle with `BU_AUTOCOMPLETE_USE_TREE_SITTER=true`.

### fzf autocomplete display

The `__bu_fzf_compute_dimensions` function handles dropdown positioning (tested across 40–200 column terminals). Metadata formatting is shared between the legacy and tree-sitter autocomplete paths, with:
- Inline hints: type tags + sizes in fzf `--with-nth` fields
- Preview panel: 40-char side window via `--preview` when metadata overflows
- **Alias merging**: case-pattern alternatives that are equal modulo leading `-`/`+` and case (`--select`, `select`, `SELECT`) collapse into a single row — the first form, unless the user typed another form's prefix (keeps the row alive through compgen's prefix filter). Using any form excludes the whole group. Alternatives that differ after normalization (`-v|--verb`, `--json|--yaml`) stay separate rows; the legacy short/long used-option exclusion still applies.

### Structured output (JSONL pipeline)

PowerShell-inspired structured output: **JSONL (one JSON object per line) is the object stream**, jq is the backend. Commands emit records, transforms shape them, and a sink formatter decides presentation at the end of the pipeline (Out-Default: table on a terminal, JSONL when piped).

Implemented in [bu_core_out.sh](../lib/core/bu_core_out.sh) with cmdlet commands (`bu where`, `bu select`, `bu sort`, `bu query-object`, `bu format-table`, ...), including:

- Recordifiers / transforms / sinks with documented streaming-vs-buffering behavior
- `bu query-object` — SQL-style clauses (`where group-by agg having select distinct order-by first`)
- Pipeline-aware field completion (static registry + opt-in probing)
- Alias merging in option completion (`--select|select` is one row)
- Multi-word verbs (`convert-to`, `convert-from`)

**See the full guide: [Structured Output](./structured_output.md)**

### Code Documentation Standards

This project follows a consistent documentation format for functions and variables, designed to work with [bash-language-server](https://github.com/bash-lsp/bash-language-server).

#### Function Documentation Format

Functions should be documented with the following format:

```sh
# ```
# *Description*
# Short description of function
#
# *Params*:
# - `$1`: Description of first parameter
# - `$2`: Description of second parameter
#
# *Returns*:
# - `$BU_RET`: Description of return value
#
# *Example*:
# ```bash
# function_name "arg1" "arg2"
# ```
#
# *Notes*:
# - Important note 1
# - Important note 2
# ```
```

The outer triple backticks allow bash-language-server to properly parse the markdown documentation inside the comments. How it works is that bash-language-server defaults to wrapping comment blocks in a `` ``` `` block, thus the top and bottom triple backticks close up the txt block so we can add arbitrary markdown in between.

#### Variable Naming Conventions

- **Global Variables**: Prefix with `BU_` to namespace them within BashTab (e.g., `BU_VERSION`, `BU_CONFIG_PATH`)
- **Functions**: Prefix with `bu_` to namespace them (e.g., `bu_init`, `bu_parse_args`)
- **Return Values**: 
  - Use `BU_RET` to return strings and non-associative arrays. The value can be either scalar or array depending on the function's purpose
  - Use `BU_RET_MAP` to return associative arrays.
- **User-Defined Variables**: Prefix with `BU_USER_DEFINED_` for variables that are expected to be defined externally by users

### Building a Single-File Distribution

To consolidate the entire BashTab library into a single file for easier distribution or embedding:

```sh
source ./activate --__bu-inline ./inline.sh
```

This generates an `inline.sh` file containing the complete BashTab library.
`--__bu-inline` makes certain assumptions about where source statements are invoked, so this might break at some points.


{% capture github_base %}{{ site.github.repository_url }}/blob/{{ site.github.build_revision }}/{% endcapture %}
{% capture links %}

[commands]: ../commands/
[bu-import-environment]: ../commands/bu-import-environment.sh
[bu-get-command]: ../commands/bu-get-command.sh
[bu-new-command]: ../commands/bu-new-command.sh
[bu-run-example]: ../examples/commands/bu-run-example.sh
[bu_user_defined_decl]: ../bu_user_defined_decl.sh
[bu_core_preinit]: ../lib/core/bu_core_preinit.sh
[core]: ../lib/core/
[bu_core_base]: ../lib/core/bu_core_base.sh
[bu_core_autocomplete]: ../lib/core/bu_core_autocomplete.sh
[bu_core_tmux]: ../lib/core/bu_core_tmux.sh

{% endcapture %}
<!-- https://shopify.github.io/liquid/filters/replace_first/ -->
<!-- https://stackoverflow.com/questions/27694610/how-can-i-split-a-string-by-newline-in-shopify -->
{% assign links_list = links | newline_to_br | split: '<br />' %}
{% for link in links_list %}
{{ link | replace_first: "../", github_base }}
{% endfor %}
