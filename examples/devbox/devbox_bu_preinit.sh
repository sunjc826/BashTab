#!/usr/bin/env bash
# ── Pre-init callback (host project) ──────────────────────────────
# Registered by devbox/activate via BU_MODULE_LIST and sourced DURING
# bu_entrypoint.sh initialization. The host owns the top-level role; this
# file only registers the host's own surface (commands, help, config).
#
# ⚠️ Runs inside the custom `source` function's scope (see AGENTS.md "Custom
# `source` Function") — globals use `declare -g`; scratch vars are unset.

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

# ── Module location ───────────────────────────────────────────────
case "${BASH_SOURCE[0]}" in
    */*) _devbox_src_dir=${BASH_SOURCE[0]%/*} ;;
    *)   _devbox_src_dir=. ;;
esac
DEVBOX_DIR=$(cd -- "$_devbox_src_dir" && pwd -P)
export DEVBOX_DIR

# ── Command converter ─────────────────────────────────────────────
# The host uses its own (simpler) converter: verb-noun files, *.sh only,
# verb/noun metadata for listings. Unlike gitshelf, it leaves the namespace
# unset so __bu_stamp_command_module defaults it to the module (devbox).
# bash-ide parse-func-sig
__devbox_convert_file_to_command()
{
    local -r file_path=$1
    [[ "$file_path" == *.sh ]] || return 2

    bu_basename "$file_path"
    local -r no_ext=${BU_RET%.sh}

    __bu_preinit_split_verb "$no_ext"
    local -r verb=$BU_RET_VERB
    local -r noun=$BU_RET_REST
    local -r command=${verb}-${noun}

    BU_COMMAND_VERBS[$verb]=1
    BU_COMMAND_NOUNS[$noun]=1
    BU_COMMAND_PROPERTIES[$command,verb]=$verb
    BU_COMMAND_PROPERTIES[$command,noun]=$noun

    BU_RET=$command
    return 0
}

bu_preinit_register_user_defined_subcommand_dir \
    "$DEVBOX_DIR/commands" \
    __devbox_convert_file_to_command

BU_COMMAND_SEARCH_DIR_RECURSIVE["$DEVBOX_DIR/commands"]=false

# Config keys are registered in devbox_bu_config.sh.

# ── Pipeline stage effects ────────────────────────────────────────
bu_register_stage_effect "bu get-env" producer

# ── Help topics ───────────────────────────────────────────────────
bu_help_topic_register_dir "$DEVBOX_DIR/help"

unset _devbox_src_dir
