# ```
# The master command name. Default is `bu`, but users can override it by defining `BU_USER_DEFINED_CLI_COMMAND_NAME`.
# ```
BU_CLI_COMMAND_NAME=${BU_USER_DEFINED_CLI_COMMAND_NAME:-bu}

# This file can sourced multiple times, but the following variables will only be defined once
# to avoid resetting changes.
# All array/map container variables should be placed below this conditional
if [[ -n "${BU_CORE_VAR_SOURCED:-}" ]]; then return; fi

declare -g BU_CORE_VAR_SOURCED=1

# ```
# Additional names that the CLI completion function should accept beyond
# BU_CLI_COMMAND_NAME.  Projects that alias the CLI (e.g. a single-letter
# wrapper `j` for `jr`) populate this array and then register the
# completion themselves:
#   BU_CLI_COMMAND_ALIASES+=(j)
#   complete -F __bu_autocomplete_completion_func_cli j
# ```
declare -a -g BU_CLI_COMMAND_ALIASES=()

# ```
# This mapping will be passed directly to `complete -F`
# ```
declare -A -g BU_AUTOCOMPLETE_COMPLETION_FUNCS=(
    [$BU_CLI_COMMAND_NAME]="__bu_autocomplete_completion_func_cli"
)

# ```
# Map of command to script path / function
# ```
declare -A -g BU_COMMANDS=()
# ```
# Qualified side-store for same-name commands from different modules, keyed
# `:<ns>:<cmd>`. Populated by __bu_command_register when a collision parks or
# demotes a definition. Dispatch and type resolution read it; never write.
# ```
declare -A -g BU_COMMANDS_QUALIFIED=()
# ```
# Map of directory to convert_file_to_command
# ```
declare -A -g BU_COMMAND_SEARCH_DIRS=()
# ```
# Map of directory to whether it is scanned recursively (default: true = recursive).
# Set to false by bu import-environment --non-recursive.
# ```
declare -A -g BU_COMMAND_SEARCH_DIR_RECURSIVE=()
# ```
# File extensions (without the dot) of the files in a command search dir that
# are command candidates. Decided from the file name alone, so the directory
# may hold other files (logs, core dumps) without them ever being opened.
# Set it before the entrypoint runs to change it.
# ```
if ! declare -p BU_COMMAND_FILE_EXTENSIONS &>/dev/null
then
    declare -a -g BU_COMMAND_FILE_EXTENSIONS=(sh py)
fi
# ```
# Map of (<command>,<query>) to properties
# The following queries are currently defined
# - type 
#   - Meaning: The type of Bash object implementing the command
#   - Values: 
#     - function: For Bash functions
#     - execute: For executable Bash scripts
#     - source: For non-executable Bash scripts meant to be sourced
#     - alias: For bu aliases. See `bu_preinit_register_new_alias`.
#     - <empty>: To be dynamically derived
# - verb
#   - Meaning: Breakdown of the command. The verb portion.
# - noun
#   - Meaning: Breakdown of the command. The noun portion.
# - namespace
#   - Meaning: Breakdown of the command. The namespace portion.
# ```
declare -A -g BU_COMMAND_PROPERTIES=()

# ```
# Set of all parsed verbs from the bu command list
# Note: This is an associative array, thus to get all verbs, do `${!BU_COMMAND_VERBS[@]}`
# ```
declare -A -g BU_COMMAND_VERBS=()
# ```
# Set of all parsed nouns from the bu command list
# Note: This is an associative array, thus to get all nouns, do `${!BU_COMMAND_NOUNS[@]}`
# ```
declare -A -g BU_COMMAND_NOUNS=()
# ```
# Set of all parsed namespaces from the bu command list
# Note: This is an associative array, thus to get all nouns, do `${!BU_COMMAND_NAMESPACE[@]}`
# ```
declare -A -g BU_COMMAND_NAMESPACES=()

# ```
# Verbs that consist of multiple words (kebab-case), checked first when
# parsing command names. PowerShell's two-word verbs in kebab form.
# Example: with `convert-to` in this list, `convert-to-jsonl` parses as
# verb=`convert-to`, noun=`jsonl` instead of verb=`convert`, noun=`to-jsonl`.
# Extend from user-defined configs to support custom multi-word verbs.
# ```
# `declare -p` check: "${#arr[@]}" on an undeclared array errors under `set -u`.
if ! declare -p BU_MULTI_WORD_VERBS &>/dev/null
then
    declare -a -g BU_MULTI_WORD_VERBS=(convert-to convert-from)
fi

# ```
# Registry of loaded modules: name → "version:preinit_path"
# Populated by __bu_parse_module_list from BU_MODULE_LIST. Inspected by bu get-module.
# ```
declare -A -g BU_MODULE_REGISTRY=()
# Precedence rank: lower rank wins the bare command name. Populated by
# __bu_parse_module_list (1-based BU_MODULE_LIST position); the framework
# itself is pinned at 900, unranked modules default to 500, and a no-module
# (interactive/session) registration is rank 0.
declare -A -g BU_MODULE_RANK=([bu]=900)
# Reverse map: preinit_path → module name, built by __bu_parse_module_list.
# Used by bu_source_user_defined_pre_init_callbacks to expose BU_CURRENT_MODULE.
declare -A -g BU_MODULE_PREINIT_MAP=()
# Transient owning-module name while a module preinit callback is sourced.
# Set/cleared by bu_source_user_defined_pre_init_callbacks; registrations that
# run inside the callback inherit it as their provenance.
declare -g BU_CURRENT_MODULE=
# Command-search directory → owning module name, stamped when a module preinit
# registers a subcommand dir. The command scanner copies it onto each command.
declare -A -g BU_COMMAND_SEARCH_DIR_MODULE=()
# Optional presentation alias: module name → short display label (dropdown tag).
# Registry keys always use the full module name.
declare -A -g BU_MODULE_DISPLAY_NAMES=()
# Exportable scalar version of the registry for subshell inspection
# Format: "name:version:path;name:version:path;..."
export BU_MODULE_LIST=${BU_MODULE_LIST:-}

# Global default for the parse-position counter incremented by bu_parse_positional /
# bu_parse_multiselect. bu_parse_nested re-declares this as a `local`, which shadows
# the global via dynamic scoping; the global exists so stray increments don't trip `set -u`.
declare -g __bu_g_shift_by=0

# ```
# It is recommended to isolate this by declaring `local -A BU_COMPOPT_CURRENT_COMPLETION_OPTIONS`
# instead of using the global version.
# ```
declare -A -g BU_COMPOPT_CURRENT_COMPLETION_OPTIONS=()

# ```
# Dynamic compopt options set DURING a completion via the compopt wrapper.
# Kept separate from BU_COMPOPT_CURRENT_COMPLETION_OPTIONS (the static
# compspec) so dynamic nospace can be honored unconditionally at insertion,
# while static nospace keeps the suffix heuristic.
# ```
declare -A -g BU_COMPOPT_DYNAMIC_COMPLETION_OPTIONS=()

# ```
# Whether the current compopt builtin is overridden by a custom func
# ```
declare -g BU_COMPOPT_IS_CUSTOM=false

# Double quote the value to get Go-To Definition working in bash-language-server

# ```
# This mapping will be passed directly to `bind -x`
# ```
declare -A -g BU_KEY_BINDINGS=(
    ['\ee']="__bu_bind_edit"
    ['\ea']="__bu_bind_fzf_history"
    ['\ez']="bu_autocomplete_toggle_tab"
)

# Human-readable descriptions for key bindings, keyed by the same
# escape sequence.  Displayed in `bu` help.
declare -A -g BU_KEY_BINDING_DOCS=(
    ['\ee']='Edit the current command line in $EDITOR'
    ['\ea']='Fuzzy-search command history'
    ['\ez']='Toggle Tab between default and BashTab completion'
)

# Owning module for each key binding, keyed by the same escape sequence.
# Core defaults are declared outside any module scope, so they are stamped
# as module "bu" (the framework itself) here in the literal declaration.
# A module re-registering a chord via bu_preinit_register_user_defined_key_binding
# takes over the stamp, so this always attributes the LIVE binding.
declare -A -g BU_KEY_BINDING_MODULES=(
    ['\ee']='bu'
    ['\ea']='bu'
    ['\ez']='bu'
)

# Command-line transform registry: name → match/replace/description/module/derived.
# Populated by bu_preinit_register_line_transform (see bu_core_transform.sh).
declare -A -g BU_LINE_TRANSFORM_PROPERTIES=()

# 1 metadata entry corresponds to 1 compreply entry
# Meant for display in fzf completion mode
# (=() required: "${#arr[@]}" on a declared-but-unset array errors under `set -u`)
declare -a -g BU_COMPREPLY_METADATA=()

# Meant for display in fzf completion mode
declare -g BU_COMPREPLY_HINT=
