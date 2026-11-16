# Bash version guard.  Must stay first and use only syntax that bash 3.2
# (macOS /bin/bash) and zsh can parse; everything below needs bash >= 4.4.
if [ -z "${BASH_VERSINFO-}" ] || [ "${BASH_VERSINFO[0]}" -lt 4 ] ||
    { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -lt 4 ]; }
then
    # Command scripts reach here via `#!/usr/bin/env bash`, which takes the
    # first bash on PATH.  On macOS that is often /bin/bash 3.2, because
    # /etc/profile's path_helper moves /bin ahead of Homebrew in login shells.
    # Re-run the script under the bash that activated BashTab (BU_BASH).
    # The script sourced us without args, so "$@" is still its own argv, and
    # its `invocation_dir` local is visible here (template line 1); a
    # relative $0 only resolves from there, so cd back before testing it.
    case $- in
    *i*) ;;
    *)
        if [ -n "${BASH_VERSION-}" ] && [ -n "${BU_BASH-}" ] && [ "$BU_BASH" != "${BASH-}" ] &&
            [ -x "$BU_BASH" ] && cd "${invocation_dir:-.}" && [ -f "$0" ]
        then
            exec "$BU_BASH" "$0" "$@"
        fi
        ;;
    esac
    echo "bu: BashTab requires bash >= 4.4, but ${BASH:-this shell} is ${BASH_VERSION:-not bash}." \
        "On macOS: brew install bash, and put \$(brew --prefix)/bin ahead of /bin in PATH." >&2
    # Never kill an interactive shell (it may run `set -e`).
    case $- in
    *i*) return 0 ;;
    esac
    exit 1
fi
# Inherited by command scripts so they can re-exec under it (see above).
export BU_BASH="$BASH"

case "${BASH_SOURCE}" in
*/*) pushd "${BASH_SOURCE%/*}" &>/dev/null ;; # Enter the current directory
*) pushd . &>/dev/null ;; # This seems like duplicate work but we need to match the popd later
esac

declare -a -g BU_RET=()
declare -A -g BU_RET_MAP=()
# `declare -p` check instead of "${#BU_MODULE_REGISTRY[@]}", which errors
# under `set -u` when the array has never been declared.
if ! declare -p BU_MODULE_REGISTRY &>/dev/null
then
    declare -A -g BU_MODULE_REGISTRY=()
fi

# ${VAR:-} guards: this file may be sourced from shells running `set -u`.
BU_REPO_DIR_PREV=${BU_REPO_DIR:-}
BU_REPO_SHA1_PREV=${BU_REPO_SHA1:-}
BU_REPO_DIR=$PWD
# Suppressed: users who downloaded a ZIP/tarball have no .git directory.
BU_REPO_SHA1=$(git rev-parse @ 2>/dev/null) || BU_REPO_SHA1=unknown
# Human-readable release identity, derived from the datetime (CalVer) tags cut
# by release.sh.  `git describe --tags --always --dirty` yields e.g.
# "v2026.08.15-3-g1f4ae9c" (or "...-dirty" with uncommitted changes) and is
# stable/meaningless-free — no manual version bump to forget.
BU_VERSION=$(git describe --tags --always --dirty 2>/dev/null) || BU_VERSION=unknown
# Nearest release tag (empty → "unknown") for the `bu get-version` catalog.
BU_VERSION_TAG=$(git describe --tags --abbrev=0 2>/dev/null) || BU_VERSION_TAG=unknown
if [[ -n "$BU_REPO_SHA1_PREV" && "$BU_REPO_SHA1" != "$BU_REPO_SHA1_PREV" ]]
then
    echo "WARN    A different BashTab version is being activated: Prev[$BU_REPO_SHA1_PREV@$BU_REPO_DIR_PREV] Cur[$BU_REPO_SHA1@$BU_REPO_DIR] Cur-version[$BU_VERSION]" >&2
fi

source ./bu_custom_source.sh --__bu-once
source ./lib/core/bu_core_config.sh --__bu-once

source ./lib/core/bu_core_user_defined.sh --__bu-once

# ── Config phase "static" ───────────────────────────────────────────────────
# Settings final for the life of the shell, resolved before almost all of
# BashTab runs: exported values > bu_config_local.static.sh > registered
# defaults, then exported so child processes share them. On re-activation
# the registrations are no-ops and the phase only restores any value that
# changed.
#
# BU_MODULE_LIST (a static, env-only setting) is the sole module registry: an
# exported scalar "name:version:preinit_path;...". Top-level projects set it
# in their activate script, library dependencies append to it in their module
# scripts. It is normalized (repeated modules dropped) before it is final.
# Each module registers its static settings in NAME_bu_config.static.sh next
# to its preinit, and its main-phase settings in NAME_bu_config.sh.
bu_config_phase_begin static --static || true
_bu_cur_module_prev=${BU_CURRENT_MODULE:-}
BU_CURRENT_MODULE=bu
source ./config/bu_config_static.sh
BU_CURRENT_MODULE=$_bu_cur_module_prev
__bu_module_list_normalize || true
__bu_source_module_configs static || true
bu_config_phase_end static || true

# ── Config phase "main" ─────────────────────────────────────────────────────
# Precedence: exported variables > settings files > registered defaults.
# Register the core settings (and any user-defined config callbacks' ones),
# then resolve them: save exported values, source the settings files with
# their plain VAR=value assignments, restore the exported values, and apply
# defaults from the generated vars file. Each file's assignments are
# attributed to it for `bu get-config`. Re-activation runs the phase again.
bu_config_phase_begin main || true
# Core settings are registered from the framework itself, so scope
# BU_CURRENT_MODULE=bu around the dynamic config source (same save/restore
# pattern as the core help-topic registration further down) to stamp each
# core setting's provenance as module "bu".
_bu_cur_module_prev=${BU_CURRENT_MODULE:-}
BU_CURRENT_MODULE=bu
source ./config/bu_config_dynamic.sh
BU_CURRENT_MODULE=$_bu_cur_module_prev
__bu_source_module_configs main || true
__bu_config_phase_prepare main || true

# The phase's settings files are sourced here at top level rather than inside
# bu_config_phase_end, so site glue runs in the entrypoint's own scope.
# Intentionally NOT --__bu-once: re-activation should re-read edited settings.
#
# 1. Machine-local settings (uncommitted, managed by `bu set-config`).
# 2. The embedder's BU_CONFIG_LOCAL_FILE, the write target of `bu set-config`
#    when an embedding project points it at its own tree. It must be re-read
#    here (not just applied by the embedder's activate in the parent shell):
#    execute-type commands re-run this entrypoint in a child process, where the
#    parent's non-exported variables are invisible.
# 3. Fleet-shared site glue (profile.d-style, sourced in glob order), committed
#    and deployed with the checkout: a "site" is a fleet of hosts sharing one
#    module system/package tool. Runs before capability probing so a site can
#    install a BU_CAP_MISS_RESOLVER hook that makes lazily-loaded binaries
#    visible to bu_cap_probe. Site files should be idempotent.
__bu_config_phase_files main || true
_bu_config_files=("${BU_RET[@]}")
for _bu_config_file in "${_bu_config_files[@]}"
do
    # shellcheck disable=SC1090
    source "${_bu_config_file#*:}"
    __bu_config_phase_track "${_bu_config_file#*:}" "${_bu_config_file%%:*}" || true
done
unset _bu_config_file _bu_config_files

# User-defined config callbacks count as one more source of the phase
bu_source_user_defined_configs
__bu_config_phase_track "" callback || true

__bu_config_phase_complete main || true

source ./lib/core/bu_core_var.sh --__bu-once
source ./lib/core/bu_core_base.sh --__bu-once
# Context-variable origin tracking + consumption logging (bu_var_origin_* /
# bu_context_*).  Loaded early so embedders can wrap their configuration
# sourcing chain in bu_var_origin_enable/bu_var_origin_disable windows.
source ./lib/core/bu_core_context.sh --__bu-once
# Location/repo/help-topic registries are re-sourced every activation (no
# --__bu-once) so their arrays reset before preinits and the local file
# re-register entries.
source ./lib/core/bu_core_location.sh
source ./lib/core/bu_core_repo.sh
source ./lib/core/bu_core_help_topic.sh
# BashTab's own subsystem topics live in <repo>/help and are registered from
# core (not a module preinit) so the builtin CLI always ships them. They
# re-register on every activation because bu_core_help_topic.sh resets the
# registry above, before module preinits add theirs. Core topics are stamped
# as module "bu" (the framework itself).
_bu_cur_module_prev=${BU_CURRENT_MODULE:-}
BU_CURRENT_MODULE=bu
bu_help_topic_register_dir "$BU_DIR/help"
BU_CURRENT_MODULE=$_bu_cur_module_prev
source ./lib/core/bu_core_out.sh --__bu-once
source ./lib/core/bu_core_column.sh --__bu-once
source ./lib/core/bu_core_pipemeta.sh --__bu-once
source ./lib/core/bu_core_remote.sh --__bu-once
source ./lib/core/bu_core_compat.sh --__bu-once
source ./lib/core/bu_core_cap.sh --__bu-once
bu_cap_init
source ./lib/core/bu_core_autocomplete.sh --__bu-once
source ./lib/core/bu_core_help_parse.sh --__bu-once
source ./lib/core/bu_core_tmux.sh --__bu-once
source ./lib/core/bu_core_cli.sh --__bu-once
source ./lib/core/bu_core_expose.sh --__bu-once
source ./lib/core/bu_core_transform.sh --__bu-once
source ./lib/core/bu_core_preinit.sh --__bu-once

# Now that all registry arrays are declared, parse BU_MODULE_LIST.
__bu_parse_module_list

source ./lib/core/bu_core_cache.sh --__bu-once
__bu_try_load_command_cache || true

source ./lib/core/bu_core_early_init.sh

bu_source_user_defined_pre_init_callbacks

# User-local named locations (after preinits so user registrations win).
bu_location_source_local_file

source ./lib/core/bu_core_init.sh

source ./lib/core/bu_core_ts.sh --__bu-once

# Warm-start the tree-sitter daemon at shell init so first Tab is instant.
# (~200ms one-time cost absorbed into shell startup)
if "$BU_AUTOCOMPLETE_USE_TREE_SITTER" && [[ -n "${BU_CAP[node]:-}" ]] && [[ $- == *i* ]]; then
    __bu_ts_daemon_start &>/dev/null
fi

popd &>/dev/null

bu_source_user_defined_post_entrypoint_callbacks

bu_log_info "Bash utils: fully set up"

# Sourcing may happen under `set -e`: never leak a non-zero status to the user's shell.
return 0
