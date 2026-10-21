---
layout: page
title: Getting Started
permalink: /getting-started/
nav_order: 2
---

## Install

```sh
git clone https://github.com/evagreendev/BashTab.git
cd BashTab
```

**Optional dependencies:**

| Tool | Why |
|---|---|
| [`fzf`](https://github.com/junegunn/fzf) | Interactive dropdown completions, history search, inline editing |
| `tree-sitter` + `tree-sitter-bash` (npm) | CST-based command-line parsing for accurate pipe/variable/substitution detection |
| `file` | File-type hints in autocomplete (text/json/exe/png tags) |

```sh
sudo apt install fzf          # or your package manager
npm install tree-sitter tree-sitter-bash   # optional, for tree-sitter parser
```

## Activate

From the repo root:

```sh
source ./activate
```

This loads all core modules and registers built-in commands. Add this to your `.bashrc` for persistent setup:

```sh
source /path/to/BashTab/activate
```

### Customize the CLI name

```sh
BU_USER_DEFINED_CLI_COMMAND_NAME=mycli source ./activate
# Now use `mycli` instead of `bu`
```

### Enable tree-sitter parser

```sh
BU_AUTOCOMPLETE_USE_TREE_SITTER=true
```

The hand-written parser is the default (zero dependencies). Tree-sitter handles complex pipelines, nested `$(...)`, and `$VAR` expansions more accurately. The daemon starts automatically on shell init.

## Explore

```sh
bu                           # list all commands, aliases, keybindings
bu get-command               # query commands by namespace, verb, noun
bu get-command --verb module # find module-related commands
bu get-module               # list loaded modules
```

### Autocomplete

```sh
bu <TAB>                     # fzf dropdown with metadata hints
bu new-command --<TAB>       # colored type tags (flag, enum, str)
ls <TAB>                     # file completions with type + size hints
echo $HO<TAB>                # variable name completion
```

### Choose the Tab display

```sh
bu set-config BU_AUTOCOMPLETE_TAB_BACKEND readline
```

- `fzf` (default): fzf dropdown under the word being completed, with a preview pane
- `fzf-cheap`: the same dropdown on the prompt row, without the terminal queries that placing it costs (snappier, especially over ssh)
- `readline`: bash's own completion list, with descriptions; no fzf needed

Tab is bound when BashTab activates: press `Alt-Z` twice (off, then on) to switch the current shell over.

### Key bindings

| Keys | Action |
|---|---|
| `Alt-E` | Edit the current command line in `$EDITOR` |
| `Alt-A` | Fuzzy-search command history |
| `Alt-Z` | Toggle Tab between default and BashTab completion |
| `Tab` | Confirm fzf selection |
| `Ctrl-T` / `Ctrl-R` | fzf file / history search (if available) |

## Create your first command

```sh
bu new-command --dir commands --name my-first-cmd
```

This scaffolds a script with argument parsing, help generation, and autocomplete already wired up. See the [Creating Custom Commands](how-to-01-create-custom-commands) guide for details.

## Build a module

```sh
bu new-module --name myapp
```

Generates:

```
myapp/
├── activate                   ← source to activate
├── myapp_bu_module.sh         ← appends to BU_MODULE_LIST
├── myapp_bu_preinit.sh        ← imports commands directory
└── commands/                  ← your subcommands
```

Then add commands:

```sh
cd myapp
source activate
bu new-command --dir commands --name my-first-cmd
```

See the [Workflow Guide](how-to-02-BashTab-workflow) for using BashTab as a project dependency.
