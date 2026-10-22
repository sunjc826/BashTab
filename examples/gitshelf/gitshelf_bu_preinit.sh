#!/usr/bin/env bash
# ── Pre-init callback (shared by binary and library modes) ────────
# This file is registered in BU_MODULE_LIST — by gitshelf/activate in binary
# mode, or by gitshelf_bu_module.sh in library mode — and sourced DURING
# bu_entrypoint.sh initialization, after the builtin commands are available
# but before the final command scan. It runs identically in both modes and
# must therefore never assume a working directory.
#
# ⚠️ This file executes inside the custom `source` function's scope (see
# AGENTS.md, "Custom `source` Function"). A top-level `declare` without `-g`
# creates a function-local that vanishes when `source` returns. Every global
# declared here uses `declare -g`; scratch variables are unset at the end.
# Plain scalar assignments create globals fine — only associative arrays /
# readonly REQUIRE `declare -g`.

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

# ── Module location ───────────────────────────────────────────────
# Derive our directory from BASH_SOURCE, never from $PWD.
case "${BASH_SOURCE[0]}" in
    */*) _gitshelf_src_dir=${BASH_SOURCE[0]%/*} ;;
    *)   _gitshelf_src_dir=. ;;
esac
GITSHELF_DIR=$(cd -- "$_gitshelf_src_dir" && pwd -P)
export GITSHELF_DIR

# ── Command converter ─────────────────────────────────────────────
# The framework calls this once per file under the commands dir. Return codes:
#   0 — use BU_RET as the command name
#   1 — keep the default name (file name without .sh)
#   2 — REJECT: skip this file entirely
__gitshelf_convert_file_to_command()
{
    local -r file_path=$1

    # Only *.sh scripts may register as commands. Config/data files
    # (shelf.json, README.md, ...) must never become commands.
    [[ "$file_path" == *.sh ]] || return 2

    bu_basename "$file_path"
    local -r file_base=$BU_RET
    local -r no_ext=${file_base%.sh}

    __bu_preinit_split_verb "$no_ext"
    local -r verb=$BU_RET_VERB
    local -r noun=$BU_RET_REST
    local -r command=${verb}-${noun}
    local -r namespace=gitshelf

    # Verb/noun metadata so listings group and colorize correctly under
    # whatever CLI name this module is served through (shelf, devbox, ...).
    # namespace is set explicitly (rather than left to __bu_stamp_command_module)
    # so gitshelf deterministically owns its bare command names: get-repo
    # collides with BashTab's builtin locations get-repo, which registers
    # namespace=bu; registering gitshelf after it must not inherit that.
    BU_COMMAND_VERBS[$verb]=1
    BU_COMMAND_NOUNS[$noun]=1
    BU_COMMAND_PROPERTIES[$command,verb]=$verb
    BU_COMMAND_PROPERTIES[$command,noun]=$noun
    BU_COMMAND_PROPERTIES[$command,namespace]=$namespace

    BU_RET=$command
    return 0
}

bu_preinit_register_user_defined_subcommand_dir \
    "$GITSHELF_DIR/commands" \
    __gitshelf_convert_file_to_command

# The commands dir is flat; config/ and help/ are siblings, not children.
BU_COMMAND_SEARCH_DIR_RECURSIVE["$GITSHELF_DIR/commands"]=false

# ── Config namespace ──────────────────────────────────────────────
# ── Config key ────────────────────────────────────────────────────
# Registered and resolved in gitshelf_bu_config.sh; exported for commands
# that run in a child process.
export GITSHELF_CONFIG_FILE

# ── Default callback a host may override ──────────────────────────
# get-repo resolves each configured path through this callback. The default
# expands a leading `~`. A host (e.g. devbox) may export its own value before
# activation; the `:=` assignment below keeps a pre-set value untouched. For
# execute-type commands the override must resolve in a fresh process, so
# prefer a PATH-resolvable command (or a function redefined by the host's own
# preinit) rather than a shell-local function.
__gitshelf_default_resolve_path()
{
    local -r p=$1
    case "$p" in
        "~")     printf '%s\n' "$HOME" ;;
        "~/"*)   printf '%s\n' "$HOME/${p#\~/}" ;;
        *)       printf '%s\n' "$p" ;;
    esac
}
: "${GITSHELF_RESOLVE_PATH_CALLBACK:=__gitshelf_default_resolve_path}"

# ── Runtime state (global map) ────────────────────────────────────
# Demonstrates the `declare -g` rule for sourced files: a bare `declare -A`
# here would silently vanish. Populated for the help topic and introspection.
declare -A -g GITSHELF_STATE=()
GITSHELF_STATE[version]=0.1.0
GITSHELF_STATE[commands_dir]="$GITSHELF_DIR/commands"
GITSHELF_STATE[config_file]=$GITSHELF_CONFIG_FILE

# ── Pipeline stage effects ────────────────────────────────────────
# Every JSONL-emitting command is a `producer`, so `shelf get-repo | shelf where ...`
# (and the devbox / bu spellings) can complete field names after a pipe.
# Stage-effect lookups are keyed on the canonical `bu <name>` spelling; the
# framework canonicalizes renamed CLIs back to `bu` before matching.
bu_register_stage_effect "bu get-repo" producer
bu_register_stage_effect "bu sync-repo" producer
# The config mutators take their input as arguments and print only log lines,
# so they sit outside any pipeline (`standalone`: none -> none).
bu_register_stage_effect "bu add-repo" standalone
bu_register_stage_effect "bu remove-repo" standalone

# ── Help topics ───────────────────────────────────────────────────
# Modules register their own subsystem help pages; `bu get-help gitshelf`
# renders ours (stamped as module gitshelf).
bu_help_topic_register_dir "$GITSHELF_DIR/help"

# Clean up scratch variables (this file runs inside the source() function).
unset _gitshelf_src_dir
