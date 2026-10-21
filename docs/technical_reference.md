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
actually registered the requested name. It also records the requirement in
`BU_MODULE_DEPS` (`parent>dep;...`; the requirer is the module whose script is
being sourced, else the top-level module, the first `BU_MODULE_LIST` entry),
even when the dependency is already registered.

Modules' config files (`NAME_bu_config.static.sh`, `NAME_bu_config.sh`) and
preinit callbacks then run in **dependency order**: a depth-first topological
sort over `BU_MODULE_DEPS`, so a module comes after everything it requires and
the top-level module runs last. Modules without a requirement between them
keep their `BU_MODULE_LIST` order; a requirement that closes a cycle is
ignored for ordering, with a warning. Precedence (`BU_MODULE_RANK`, which
module's command takes a bare name) still follows `BU_MODULE_LIST` order, the
top-level module first. A library sourced by hand (not via
`bu_module_require`) records no requirements, so it keeps its list position.

This populates:

| Variable | Type | Description |
|---|---|---|
| `BU_MODULE_REGISTRY` | `Map[String, String]` | `name → "version:preinit_path"`. Available in current shell. |
| `BU_MODULE_LIST` | `String` (exported) | `"name:version:path;..."`. Deduped after parsing. Survives subshells for `bu get-module`. |
| `BU_MODULE_DEPS` | `String` (exported) | `"parent>dep;..."`, recorded by `bu_module_require`; orders module config files and preinits. |

`bu get-module` reads `BU_MODULE_LIST` to display loaded modules with name, version, and path.

### Settings precedence and provenance

Settings registered with `bu_config_register` resolve, highest first:

1. **Exported variables**, including one-off overrides such as
   `BU_LOG_LVL=1 source ./activate`.
2. **Settings files** of the setting's config phase (below). They use plain
   `VAR=value` assignments, so the last file sourced wins, and sourcing a
   file by hand applies it.
3. **Registered defaults** (`bu_config_register --default`).

#### Config phases

Every setting belongs to exactly one **config phase**: the phase open when it
was registered (`bu_config_phase_begin NAME` … `bu_config_phase_end NAME`).
Resolving a phase saves the exported values of its settings, resets their
unexported values, sources the phase's settings files (attributing each
assignment to its file), restores the exported values, then applies the
registered defaults by sourcing a vars file generated from the registry:
`$BU_OUT_DIR/cache/config-vars/<top-level module>/<BashTab dir>/<phase>[.<variant>].sh`,
one documented `NAME=${NAME:-default}` line per setting, rewritten only when
the registrations change. A settings file that assigns a setting of another,
already resolved phase is ignored with a warning.

| Phase | Registered in | Settings files | Runs |
|---|---|---|---|
| `static` | `config/bu_config_static.sh`, modules' `NAME_bu_config.static.sh` | `bu_config_local.static.sh` | Once per shell, before almost all of BashTab |
| `main` | `config/bu_config_dynamic.sh`, modules' `NAME_bu_config.sh` | `bu_config_local.sh`, then `site/*.sh` | Every activation |
| `NAME` | Your code, between `bu_config_phase_begin NAME` and `bu_config_phase_end NAME` | `bu_config_local.NAME.sh`, then `bu_config_local.NAME.VARIANT.sh`, plus any `--settings-file` | Whenever you run it |

Each settings file exists in the checkout (`config/…`) and, when an embedder
sets `BU_CONFIG_LOCAL_FILE`, next to it (`${BU_CONFIG_LOCAL_FILE%.sh}.NAME.sh`,
read after the checkout's). `bu set-config` writes each setting to its phase's
file.

Only exported values beat the settings files: a value you set in the shell
without `export` is reset whenever its phase runs (every activation for
`main`).

**Static settings** (`bu_config_phase_begin NAME --static`) are final for the
life of the shell. A value set before the phase runs counts as yours, exported
or not; once resolved, the values are exported, so child processes (execute-type
commands, nested shells) share them. On re-activation a static phase only
restores any value that changed, with a warning; `bu set-config` stores a
static setting for new shells without changing the live value, and
`bu import-environment --reset-source` resolves the static phases again
(keeping the values you supplied). **Env-only** static settings
(`--env-only`: `BU_CONFIG_LOCAL_FILE`, `BU_TOP_LEVEL_MODULE`, `BU_MODULE_LIST`)
choose the settings files and modules themselves, so only the environment can
set them: settings files are ignored and `bu set-config` refuses them.

**Variants** model profiles: `bu_config_phase_begin profile --variant dev`
sources `bu_config_local.profile.sh` (all profiles) and then
`bu_config_local.profile.dev.sh`, and uses `--default-for dev VALUE` defaults.
Settings registered only for some variants appear and disappear as the phase
runs again, `--prefix PREFIX` keeps a phase's names apart, and
`bu_config_phase_unload` drops a phase. `bu set-config` writes the active
variant's file (applied live); `--variant NAME` and `--all-variants` target
another variant or the shared file, applied the next time the phase runs.

```sh
bu_config_phase_begin profile --variant "$MYAPP_PROFILE" --prefix MYAPP_
bu_config_register MYAPP_API_URL --default-for dev https://dev.example \
    --default-for prod https://prod.example --hint "API endpoint"
[[ "$MYAPP_PROFILE" == dev ]] && bu_config_register MYAPP_MOCK_PORT --default 8080
bu_config_phase_end profile
```

**Extra settings files**: `--settings-file [ORIGIN:]PATH` (repeatable) adds a
file of the project's own to the phase, attributed as ORIGIN (default `local`;
the split is at the first colon, a relative PATH is resolved when the phase
begins, and `env`, `shell`, `default`, `callback`, `site` are reserved). Files
are sourced in the order declared, a missing one is skipped, and everything
above applies to them: assignments to another phase's settings are ignored
with a warning, exported values still win, defaults apply last. The bare
`--settings-file local` places the phase's built-in files (both levels,
variant included) among them; without it they come first. A profile with a
per-user file below the machine-local one and an override file above it:

```sh
bu_config_phase_begin profile --variant "$MYAPP_PROFILE" --prefix MYAPP_ \
    --settings-file "user:$MYAPP_ROOT/users/$USER/settings.sh" \
    --settings-file local \
    --settings-file "profile:$MYAPP_ROOT/profiles/$MYAPP_PROFILE/overrides.sh"
```

`bu_config_phase_files NAME` returns (in `BU_RET`) the ordered `ORIGIN:PATH`
entries the phase reads, missing files included, e.g. for a doctor command.
`bu set-config` still writes to the built-in file; `--file PATH` naming one of
the declared files records its ORIGIN, as the next resolution will.

**Modules** register their settings in `NAME_bu_config.sh` (main phase) and
`NAME_bu_config.static.sh` (static phase) next to their preinit, found from
`BU_MODULE_LIST`; `BU_CURRENT_MODULE_DIR` is the module's directory while they
run. Registering from a module's preinit instead (outside any phase) warns:
the environment and settings files do not apply to such a setting.

#### Provenance

`bu get-config` reports each setting's `phase` (`profile[dev]` for a variant)
and where its value came from:

| `origin` | Meaning | `location` |
|---|---|---|
| `env` | Exported before its phase ran | empty |
| `shell` | Changed in the shell after its phase ran; for a static setting, set unexported before the phase ran | empty |
| `local` | A settings file of its phase (including `bu set-config`) | `file:line` of the last assignment |
| *ORIGIN* | A file declared with `bu_config_phase_begin --settings-file ORIGIN:PATH` (or a `bu set-config` write that lands on it, via `--file`, `--layer` or the natural layer): the declared label | `file:line` of the last assignment |
| `site` | A `site/*.sh` file | `file:line` when the assignment is a plain `VAR=`/`export VAR=` line, else `file` |
| `callback` | A user-defined config callback (`BU_USER_DEFINED_*_CONFIGS`) | empty |
| `layer` | `bu set-config --layer`/`--file` (or the natural layer) in this shell, to a file the phase does not read | `file:line` |
| `default` | None of the above | where the setting is registered |

`bu set-config` warns when the variable is exported, since an exported value
keeps winning on later activations.

`bu edit-config` opens the settings in `bu view-table` with row actions:
`t` toggles a boolean or steps to the next allowed value, `e` asks for a
value, `x` restores the default, and `o` opens the setting's `location` in
`$VISUAL`/`$EDITOR`. Each change goes through `bu set-config` and the table
reloads; because the viewer is a separate process, the changes are queued and
applied to the calling shell when it exits (static settings: in a new shell).
The same mechanism is available to any producer:
`bu view-table --action KEY[:LABEL]=COMMAND --reload COMMAND --key COLUMN`.
An action is eval'd in the viewer's shell with the cursor record in
`BU_TV_RECORD`; it can ask for input with `bu_tv_prompt` and run an editor with
`bu_tv_interactive`, and its last output line shows on the status line.

#### File-backed enums

An inline `--enum a b c enum--` suits a handful of modes. For a list that
lives elsewhere and changes (venues, colos, feed names), keep the values in a
file:

```sh
bu_config_register MYAPP_VENUE --enum-file "$BU_CURRENT_MODULE_DIR"/venues.txt \
    --enum-source myapp_list_venues --hint "Trading venue"
```

- `--enum-file PATH` reads one value per line; blank lines and `#` comments
  are ignored, and the `name:mapped` form of `--enum` applies. The values land
  in `BU_CONFIG_PROPERTIES[NAME,enum]` exactly as with `--enum`, so
  completion, `bu set-config` validation and the `allowed` column of
  `bu get-config` work unchanged; the absolute path is kept in
  `BU_CONFIG_PROPERTIES[NAME,enum_file]` (a relative PATH is resolved against
  `$PWD` when registering). An unreadable PATH is a registration error naming
  the setting; `--enum` and `--enum-file` are mutually exclusive.
- `--enum-source CMD` (needs `--enum-file`) is a function name or command
  line, `eval`'d in the current shell, that prints the fresh values one per
  line; kept in `BU_CONFIG_PROPERTIES[NAME,enum_source]`. A file that does not
  exist yet is then only a warning: the setting accepts any value until
  `bu update-config-enum NAME --execute` creates the file.

A file refreshed from a source has this layout (a file without markers
counts as all generated):

```text
# Venues we trade, from the ops venue registry.        <- header, kept
# --- generated (myapp_list_venues, 2026-10-21) ---     <- rewritten
xnys
xnas
# --- hand-kept ---                                     <- kept as is
# not in the registry yet
mytest
```

`bu update-config-enum [SETTING...] [--execute] [--format F]` (default: every
setting registered with `--enum-source`; function
`bu_config_refresh_enum_file NAME [--execute]`) runs each source, diffs it
against the generated section and lists records `name file kind value
action`: one `added`/`removed` per value and one `summary` ("N generated,
M hand-kept, +a -r"), action `would-write`, `written` or `unchanged`. With
`--execute` it rewrites the file (header kept, generated section replaced
under a dated marker, hand-kept section kept) and updates the live enum. An
unchanged file is not rewritten; a source that fails or prints nothing
leaves the file alone and exits 1.

#### Validating settings

Nothing validates at activation: a value set by a settings file (a node pin,
a ref override) is never checked, and only `bu set-config` validates what it
writes. Check where a bad value matters:

- `bu validate-config [SETTING...] [--allow VALUE]... [--invalid]
  [--format F]` lists records `name value origin status detail` (origin as
  `bu get-config` reports it; status `ok` or `invalid`) and exits 1 when any
  is invalid. Without names it checks every setting with an enum or bool
  rule. Empty values and `--allow` sentinels pass as "not applicable"; the
  stored form of a `name:mapped` entry (`BU_LOG_LVL` holding `4`) passes as
  well as the name; an unregistered name is invalid.
- `bu_config_validate_settings [--allow VALUE]... [NAME...]` is the same as a
  function (TSV on stdout, status 1 when any is invalid).
- `bu_config_require_valid [--allow VALUE]... [NAME...]` is the gate for a
  module's preflight or plan verb: it logs each invalid setting with
  `bu_log_err` and returns 1, and is silent when all pass.

```sh
myapp_plan() {
    bu_config_require_valid --allow auto MYAPP_VENUE MYAPP_NODE || return 1
    ...
}
```

### Initialization callable functions
Another point of customization are the pre-init functions. They are found in [bu_core_preinit.sh][bu_core_preinit]. They all have the `bu_preinit_` prefix.

- `bu_preinit_register_user_defined_key_binding`:
  - Description: Register a key binding for interactive shells. Values are stored in `BU_KEY_BINDINGS` and later applied via `bind -x`. When called from a module preinit callback (where `BU_CURRENT_MODULE` is set), the owning module is stamped into `BU_KEY_BINDING_MODULES` so `bu` help can attribute the binding; core defaults are stamped `bu`. On bash < 5.2 every binding (and fzf Tab) is wrapped as `__bu_bind_x_run <value>`, which keeps an external command inside the handler from saving readline's raw mode as the shell's tty state (keystrokes would otherwise stop echoing after the next Ctrl-C'd command); bash 5.2+ binds the value directly.
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
| `short` | One compact line per frame: `0: false at script.sh:42` |
| `full` | Python-style frames with the surrounding source lines, fault line highlighted (default) |

```sh
# Compact
bu set-config BU_STACKTRACE_STYLE short

# Verbose — show surrounding source lines (default)
bu set-config BU_STACKTRACE_STYLE full
```

The `full` style renders each frame as a `File "...", line N, in func` header
followed by a source window. The number of lines shown before/after each frame
is `BU_STACKTRACE_CONTEXT_LINES` (default `4`), a tunable global in
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

### Tab backends

`BU_AUTOCOMPLETE_TAB_BACKEND` picks how Tab shows candidates. Tab is bound on
activation, and again when `Alt-Z` turns it back on; `bu_autocomplete_enable_tab
BACKEND` binds a backend directly. All three run
the same completion engine (`__bu_autocomplete_tab_parse_line` to find the
command and its words, `__bu_autocomplete_tab_collect` to run its completion
function); they differ only in the display:

| Backend | Tab runs | Per Tab, besides the completion function |
|---|---|---|
| `fzf` (default) | `__bu_bind_fzf_tab_autocomplete`: dropdown placed under the word, preview pane for long descriptions | ~15 processes: 3 cursor-position queries (each a round trip to the terminal, over the network on ssh) with their `stty` calls, `tput`, `sed` for the prompt, `sort`, fzf |
| `fzf-cheap` | `__bu_bind_fzf_cheap_tab_autocomplete`: the dropdown on the prompt row, the line as fzf's prompt, no preview | `sort`, fzf |
| `readline` | readline's own completion with cobra-style `word  (description)` entries | one subshell, no process |

`fzf-cheap` relies on bash clearing the prompt row before a `bind -x` handler
and redrawing it afterwards, and on `fzf --height` drawing from the cursor row
and returning there: nothing to measure or restore. The fzf backends fall back
to `readline` when fzf is not installed.

`readline` binds Tab to a macro of two internal key sequences
(`\C-x\C-_t`, `\C-x\C-_c`). The first runs `__bu_bind_readline_tab_prepare`
(`bind -x`): it runs the engine, adds the descriptions, stashes the
candidates and points the command's compspec at
`__bu_autocomplete_readline_stash_func`. The second is readline's `complete`,
which calls that function: it restores the original compspec and returns the
stash, minus the part of the word in front of readline's own word start
(`--format=` in `--format=js`, an opening quote). Readline then inserts the
common prefix, lists the candidates and honours inputrc settings
(`show-all-if-ambiguous`, `completion-query-items`, `colored-stats`, ...) as
usual. Because `complete` lists only when the command before it was
`complete`, a Tab on an unchanged line rebinds the second key sequence to
`possible-completions`. Command names and filename completions are left
undescribed: readline displays a filename's last path component only.

### fzf autocomplete display

The `__bu_fzf_compute_dimensions` function handles dropdown positioning (tested across 40–200 column terminals). Metadata formatting is shared between the legacy and tree-sitter autocomplete paths, with:
- Inline hints: type tags + sizes in fzf `--with-nth` fields
- Preview panel: 40-char side window via `--preview` when metadata overflows
- **Alias merging**: case-pattern alternatives that are equal modulo leading `-`/`+` and case (`--select`, `select`, `SELECT`) collapse into a single row — the first form, unless the user typed another form's prefix (keeps the row alive through compgen's prefix filter). Using any form excludes the whole group. Alternatives that differ after normalization (`-v|--verb`, `--json|--yaml`) stay separate rows; the legacy short/long used-option exclusion still applies.

### Structured output (JSONL pipeline)

PowerShell-inspired structured output: **JSONL (one JSON object per line) is the object stream**, jq is the backend. Commands emit records, transforms shape them, and a sink formatter decides presentation at the end of the pipeline (Out-Default: table on a terminal, JSONL when piped).

Implemented in [bu_core_out.sh](../lib/core/bu_core_out.sh) with cmdlet commands (`bu where`, `bu select`, `bu sort`, `bu count`, `bu query-object`, `bu format-table`, ...), including:

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
