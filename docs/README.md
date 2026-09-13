# BashTab

**BashTab** is a Bash scripting framework that makes shell development feel like a modern CLI platform. Command scripts, argument parsing, autocompletion, module loading, and interactive fzf previews — all in pure Bash.

![BashTab tour: command discovery, module provenance, querying a TSV file, external completions, and help](./demo.gif)

## 🌐 Try it in your browser

No install needed — the **[live demo](https://evagreendev.github.io/BashTabDemo/)** boots Alpine Linux with BashTab pre-installed, running entirely in your browser via [v86](https://github.com/copy/v86) (x86 emulation in WebAssembly). Demo source: [evagreendev/BashTabDemo](https://github.com/evagreendev/BashTabDemo).

## Quick start

```sh
./setup                       # one-time: initialise submodules, build Fig specs
source ./activate            # load BashTab into your shell
bu                            # list commands
bu new-module --name myapp    # scaffold a module
```

Add this to your `~/.bashrc` to load BashTab automatically:
```sh
source /path/to/BashTab/activate
```

## Demos

Each clip starts in an activated shell. Expand a topic to watch a focused walkthrough; setup and activation are cut from every recording.

<details markdown="1">
<summary><strong>Query a data file</strong> — inferred fields, numeric filters, and team summaries</summary>

Query TSV directly with `--from`, complete fields from its header, or pipe `bu import-tsv` into a query. Use numeric JSON records for grouped averages. CSV and JSONL are supported too (CSV requires `jc`).

![TSV header field completion, numeric latency filtering, and grouped counts and averages](./demo-files.gif)

</details>

<details markdown="1">
<summary><strong>Build an object pipeline</strong> — tables, JSONL, grouping, and table styles</summary>

The same records become a table on a terminal or JSONL in a pipe. Complete comma-separated fields, group and filter records, then render double-border or Markdown tables.

![Terminal tables versus piped JSONL, field completion, aggregation, grep, and table styles](./demo-pipeline.gif)

</details>

<details markdown="1">
<summary><strong>Write a query with Tab</strong> — clauses, fields, operators, values, and connectors</summary>

Build a `where` expression interactively, then project a few columns with a readable `select name, verb, module` list.

![Interactive query completion through fields, operators, distinct values, and and/or connectors](./demo-query.gif)

</details>

<details markdown="1">
<summary><strong>Inspect a pipeline</strong> — compatible commands, field diagnostics, and record types</summary>

Completion uses declared stream formats and required fields. `bu validate-pipeline` checks known field references without executing the pipeline; `bu get-shape` runs a producer to inspect its observed field types.

![Compatible recordifiers after TSV, a missing-field diagnostic, and inferred process record types](./demo-contracts.gif)

</details>

<details markdown="1">
<summary><strong>Compose modules</strong> — a host and library under one CLI</summary>

The included `devbox` host loads `gitshelf` as a library. Inspect module precedence and Git state, discover commands with their owning modules, and open the library's help. Try it with `source ./activate --example devbox` in a fresh shell.

![Devbox and gitshelf module ranks, command ownership, shared completion, and library help](./demo-modules.gif)

</details>

<details markdown="1">
<summary><strong>Rewrite a command line</strong> — preview, wrap, and undo</summary>

An opt-in Alt+T selector previews a registered timeout wrapper and its automatically derived inverse. Unwrapping restores the original command before it runs. See the [recording setup](./demos/setup.sh) for the registration and binding.

![Transform selector previews a timeout wrapper, then unwraps the command with its quoting intact](./demo-transforms.gif)

</details>

<details markdown="1">
<summary><strong>Complete external commands</strong> — Docker and Git options with descriptions</summary>

![External command completion: Docker and Git subcommands and options with descriptions and previews](./demo-external.gif)

</details>

<details markdown="1">
<summary><strong>Discover help</strong> — topic pages, paging, and generated command help</summary>

![Help topic catalog, rendered pipeline guide, and generated format-table help](./demo-help.gif)

</details>

[Demo coverage and recording guide](./demos/README.md) documents the feature audit, commit history, and regeneration commands.

## Highlights

### ⌨️ IDE-style autocompletion
- **fzf dropdown** aligned under the cursor with syntax-highlighted preview line
- **Color-coded metadata**: file types, sizes, symlink targets, option type tags
- **Tree-sitter parser** for accurate CST-based tokenization of pipes, substitutions, and variables
- **Lazy completion generation** — no compilation step, modify scripts and see suggestions instantly

### 📊 Structured output (PowerShell-inspired)
- **JSONL is the object pipeline** — commands emit records, jq is the engine
- **Cmdlet suite**: `bu where`, `bu select`, `bu sort`, `bu distinct-object`, `bu format-table`, `bu out-default`, ...
- **`bu query-object`** — SQL in one command: `where`, `group-by`, `agg`, `having`, `select`, `distinct`, `order-by`, `first` in any order
- **Out-Default**: tables on a terminal, JSONL when piped — automatically
- **File queries**: `--from` and `import-csv` / `import-tsv` / `import-json` / `import-jsonl`, with inferred field completion
- **Pipeline contracts**: compatible command suggestions, `bu validate-pipeline`, and `bu get-shape`
- **Table styles**: Unicode borders by default, plus Markdown, ASCII, double, and more; long tables open in a pager
- **Pipeline-aware completion**: `bu get-command | bu select <TAB>` suggests the producer's fields
- See [Structured Output](./structured_output.md)

**`bu query-object` is a fully interactive DSL** — it completes clause keywords, field names (from pipeline analysis), binary operators, distinct field values (via tab-execute), and `and`/`or` connectors as you type.

### 📦 Module system
- `BU_MODULE_LIST` — semicolon-separated list of `name:version:preinit_path` entries
- `bu new-module --name myapp` — scaffold a module with activate / module script / preinit callback / commands directory
- `bu get-module` — inspect module precedence, version, Git branch, and dirty state
- `bu get-command` — attribute commands to modules and inspect shadowed definitions
- Module preinit callbacks register commands, keybindings, aliases, and completion specs

### 📝 Argument parsing that writes your completions
- `bu_parse_multiselect` — named flags with `-h|--help)# _FLAG` syntax
- `bu_parse_positional` — positional args with `--enum`, `--hint`, `--as-if` completion
- Single definition drives both runtime parsing AND autocomplete generation — no duplication

### 🔒 Safety
- RAII-style scope stack (`bu_scope_push_function` / `bu_scope_pop_function`) ensures cleanups run
- Custom `source` with `--__bu-once` prevents redundant re-sourcing
- `bu_exit_handler_setup` catches unexpected exits

### 🔌 Fig spec integration
BashTab can use [Fig completion specs](https://github.com/withfig/autocomplete) as a fallback when no native bash completion exists (715+ CLIs).

**Setup** (handled automatically by `./setup`):
```sh
git submodule update --init fig_specs
cd fig_specs && pnpm install --ignore-workspace && pnpm build && node ../fig_convert_to_json.mjs
```

**What you get:**
- `bu get-fig-status` — see which commands on your PATH are covered
- `bu get-fig-status --useful` — commands on PATH that lack bash completions
- Automatic fallback: pressing `<TAB>` on an unknown command checks the Fig specs

### 📖 Help topics
- `bu get-help` — list help topics with module provenance
- `bu get-help <topic>` — rendered topic pages with SEE ALSO back-references
- `--help` on any command is generated from its parser definition (options, enums, examples)

### 🚀 Datetime releases
- Calendar-based tags (`v2026.08.15`, `v2026.08.15.1` for same-day) — never a hand-picked semver
- `./release.sh` cuts + pushes the tag and opens a GitHub Release
- `bu get-version` reports the active release (`v2026.08.15-3-g1f4ae9c`)
- See [Releasing](./releasing.md)

### 🎯 Everything is a script
Every built-in command — `bu new-command`, `bu import-environment`, `bu get-command` — is a Bash script generated from the same template you use. The framework eats its own dogfood.

## Not in scope

BashTab is **not**:
- A package manager (no `import`/`load` — use `source` and `BU_MODULE_LIST`)
- A YAML/TOML-to-Bash compiler (we stay in Bash)
- A POSIX-sh framework (requires Bash 4+, uses associative arrays, `coproc`, `mapfile`)
