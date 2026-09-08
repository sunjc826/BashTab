# ```
# Command-registry caching.
#
# When BU_TOP_LEVEL_MODULE is set before sourcing bu_entrypoint.sh, the
# framework can cache the entire command registry (BU_COMMANDS, verb/noun
# sets, properties, unavailable commands) to disk.  On subsequent
# activations the `find` + `--is-compatible` probe loop is skipped entirely.
#
# Lifecycle:
#   1. export BU_TOP_LEVEL_MODULE="myproject"   # before sourcing entrypoint
#   2. source bu_entrypoint.sh                   # may load cache
#   3. bu_mark_load_complete                     # save cache (no-op if loaded)
#
# Libraries/modules must never call bu_mark_load_complete — only the
# top-level activation script.
#
# Cache files: $BU_CACHE_DIR/commands-<key>.cache
# Serialization: declare -p for each associative array (eval-safe).
# Invalidation: delete the cache file, or use `bu cache-invalidate`.
# ```

# bash-ide source=./bu_core_base.sh

# Set to true by __bu_try_load_command_cache when a cache is loaded.
# Checked by __bu_init_env_commands to skip the scan.
declare -g BU_COMMAND_CACHE_LOADED=false

# Set to true after the first call to __bu_try_load_command_cache.
# Prevents re-loading (and overwriting) the cache when bu_entrypoint.sh
# is re-sourced mid-session (e.g. by bu import-environment).
declare -g __BU_COMMAND_CACHE_CHECKED=false

# Set to false to force a full command scan on every activation.
# Use in environments where available commands change per shell
# (dynamic module systems, rapid development).
BU_COMMAND_CACHE_ENABLED=${BU_COMMAND_CACHE_ENABLED:-true}

# Opt-in deferred --is-compatible probing. When true, gated commands
# (scripts declaring --is-compatible) register as available immediately at
# scan time and are probed on first dispatch instead of during activation.
# This trades activation latency for deferred discovery: completion and
# command listings show pending gated commands as available until their first
# probe, and the first dispatch of an incompatible command errors with the
# probe reason instead of the command being hidden. A scan run with this on
# never persists compat-probe results to the compat cache.
BU_COMMAND_COMPAT_DEFERRED=${BU_COMMAND_COMPAT_DEFERRED:-false}

# ── Prompt integration ───────────────────────────────────────────────

# Saved original PROMPT_COMMAND before BashTab hooked it.
declare -g __BU_PROMPT_ORIGINAL_PROMPT_COMMAND=
# The module name currently shown in the prompt (empty if none).
declare -g __BU_PROMPT_MODULE_DISPLAYED=

# ```
# PROMPT_COMMAND hook that prepends the active module indicator to PS1
# on every prompt display.  Works with dynamic PS1 (e.g. users whose
# PROMPT_COMMAND rebuilds PS1 from scratch each time).
#
# Chains to the original PROMPT_COMMAND after prepending.
# ```
__bu_prompt_command_hook()
{
    local indicator="[\[${BU_TPUT_GREEN}\]${BU_TOP_LEVEL_MODULE}\[${BU_TPUT_RESET}\]] "
    # Chain to the original PROMPT_COMMAND
    local orig=${__BU_PROMPT_ORIGINAL_PROMPT_COMMAND:-}
    if [[ -n "$orig" ]]; then
        eval "$orig"
    fi

    # Only prepend if not already there (handles re-entrant / nested cases)
    if [[ "$PS1" != *"$indicator"* ]]; then
        PS1="${indicator}${PS1}"
    fi
}

# ```
# Prepend the active top-level module name to the prompt.
#
# Only runs in interactive shells.  Saves the original PROMPT_COMMAND
# and installs a hook that prepends a colored [module] indicator before
# each primary prompt.  Subsequent calls with the same module are no-ops.
#
# Uses PROMPT_COMMAND (not a one-shot PS1 edit) so it works correctly
# with dynamic prompts that are rebuilt on every display.
#
# Params: None
# ```
__bu_prompt_show_module()
{
    # `return 0`, not `return`: a bare return propagates the failed [[ ]] status
    # (1), which aborts the caller under `set -e` when the shell is
    # non-interactive and BU_PROMPT_SHOW_MODULE=true (see AGENTS.md set -e rules).
    [[ $- == *i* ]] || return 0

    local module=${BU_TOP_LEVEL_MODULE:-}
    if [[ -z "$module" || "$module" == "$__BU_PROMPT_MODULE_DISPLAYED" ]]; then
        return
    fi

    # Save the original PROMPT_COMMAND once
    if [[ -z "$__BU_PROMPT_MODULE_DISPLAYED" ]]; then
        __BU_PROMPT_ORIGINAL_PROMPT_COMMAND=${PROMPT_COMMAND:-}
    fi

    PROMPT_COMMAND='__bu_prompt_command_hook'
    __BU_PROMPT_MODULE_DISPLAYED=$module
}

# ```
# Remove the module indicator from the prompt and restore the original
# PROMPT_COMMAND.
#
# Params: None
# ```
__bu_prompt_hide_module()
{
    local indicator="[\[${BU_TPUT_GREEN}\]${BU_TOP_LEVEL_MODULE}\[${BU_TPUT_RESET}\]] "
    PS1=${PS1#"$indicator"}
    PROMPT_COMMAND=${__BU_PROMPT_ORIGINAL_PROMPT_COMMAND:-}
    __BU_PROMPT_MODULE_DISPLAYED=
}

# ```
# Resolve the command-cache file path for a top-level module key.
#
# Params:
# - $1: top-level module key
#
# Returns: BU_RET = cache file path
# ```
__bu_command_cache_file()
{
    BU_RET=$BU_CACHE_DIR/commands-$1.cache
}

# ```
# Try to load the command registry from cache.
#
# Called during early init (after builtin dirs are registered, before
# user pre-init callbacks).  If a cache exists for BU_TOP_LEVEL_MODULE,
# sources it to restore all registry arrays and sets
# BU_COMMAND_CACHE_LOADED=true so that __bu_init_env_commands skips the
# scan (PATH setup still runs).
#
# Returns: always 0 (cache miss is normal; never abort under set -e)
# ```
__bu_try_load_command_cache()
{
    if ! "$BU_COMMAND_CACHE_ENABLED"; then
        return 0
    fi

    # Only check once per session.  Re-sourcing bu_entrypoint.sh
    # (e.g. via bu import-environment) must not reload the cache
    # and overwrite any command dirs registered in between.
    if "$__BU_COMMAND_CACHE_CHECKED"; then
        return 1
    fi
    __BU_COMMAND_CACHE_CHECKED=true

    local key=${BU_TOP_LEVEL_MODULE:-}
    if [[ -z "$key" ]]; then
        return 0
    fi

    __bu_command_cache_file "$key"
    local cache_file=$BU_RET

    if [[ ! -f "$cache_file" ]]; then
        bu_log_warn "Command cache: miss (${cache_file##*/}) — will do a full scan"
        return 0
    fi

    bu_log_info "Command cache: hit (${cache_file##*/})"
    # shellcheck disable=SC1090
    if ! source "$cache_file"; then
        bu_log_warn "Command cache: corrupt, removing ${cache_file##*/}"
        rm -f "$cache_file"
        return 0
    fi

    # Cache loaded.  BU_COMMAND_SEARCH_DIRS and BU_COMMAND_UNAVAILABLE
    # are restored.  __bu_init_env_commands will rebuild BU_COMMANDS
    # from find, skipping --is-compatible probes for known commands.
    BU_COMMAND_CACHE_LOADED=true

    if "${BU_PROMPT_SHOW_MODULE:-false}"; then
        __bu_prompt_show_module
    fi
    return 0
}

# ```
# Serialize the expensive-to-recompute parts of the command registry.
#
# Only BU_COMMAND_SEARCH_DIRS (directory list) and BU_COMMAND_UNAVAILABLE
# (--is-compatible probe results) are cached.  BU_COMMANDS and verb/noun
# sets are cheap to rebuild from find on every activation.
#
# Params:
# - $1: top-level module key
# ```
__bu_save_command_cache()
{
    local key=$1
    __bu_command_cache_file "$key"
    local cache_file=$BU_RET
    bu_mkdir "$(dirname "$cache_file")"

    {
        printf '# BashTab command cache — project: %s\n' "$key"
        printf '# Created: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
        printf '# Auto-generated by bu_mark_load_complete.\n'
        printf '# Delete this file to force a fresh --is-compatible probe on next activation.\n'
        printf '# Managed by: bu get-cache | bu clear-cache\n'
        printf '#\n'
        printf '# Caches command-search directories, recursion flags, and\n'
        printf '# --is-compatible probe results.  BU_COMMANDS is rebuilt\n'
        printf '# from find on every activation — no stale paths possible.\n'
        echo
        declare -p BU_COMMAND_SEARCH_DIRS
        declare -p BU_COMMAND_SEARCH_DIR_RECURSIVE
        declare -p BU_COMMAND_UNAVAILABLE
    } > "$cache_file"

    bu_log_info "Command cache saved to ${cache_file##*/}"
}

# ```
# *Description*:
# Mark module loading as complete and cache the command registry.
#
# Called by the top-level activation script after sourcing bu_entrypoint.sh
# and registering all command directories.  Libraries/modules should NOT
# call this — only the top-level entrypoint.
#
# Reads BU_TOP_LEVEL_MODULE (must be set before sourcing bu_entrypoint.sh)
# to determine the cache key.
#
# No-op if the command cache was already loaded from disk during init.
#
# *Params*: None
#
# *Returns*: 0 on success, 1 if BU_TOP_LEVEL_MODULE is not set
#
# *Examples*:
# ```bash
# export BU_TOP_LEVEL_MODULE="myproject"
# source /path/to/bash-tab/bu_entrypoint.sh
# bu_mark_load_complete
# ```
# ```
bu_mark_load_complete()
{
    if ! "$BU_COMMAND_CACHE_ENABLED"; then
        return 0
    fi

    local key=${BU_TOP_LEVEL_MODULE:-}
    if [[ -z "$key" ]]; then
        bu_log_warn "bu_mark_load_complete: BU_TOP_LEVEL_MODULE is not set."
        bu_log_warn "  Set it before sourcing bu_entrypoint.sh to enable command caching:"
        bu_log_warn "    export BU_TOP_LEVEL_MODULE=\"myproject\""
        return 0
    fi

    if "$BU_COMMAND_CACHE_LOADED"; then
        bu_log_info "Command cache: already loaded, skipping save."
        return 0
    fi

    __bu_save_command_cache "$key"
    BU_COMMAND_CACHE_LOADED=true

    if "${BU_PROMPT_SHOW_MODULE:-false}"; then
        __bu_prompt_show_module
    fi
}

# ```
# Invalidate the command cache for one or all top-level module keys.
#
# Params:
# - $1: key to invalidate, or "--all" to invalidate all command caches
#
# Returns: 0 on success
# ```
__bu_invalidate_command_cache()
{
    local key=$1
    if [[ "$key" == "--all" ]]; then
        local cache_file count=0
        for cache_file in "$BU_CACHE_DIR"/commands-*.cache; do
            [[ -f "$cache_file" ]] || continue
            rm -f "$cache_file"
            ((count++))
        done
        bu_log_info "Command cache: invalidated $count file(s)"
        BU_COMMAND_CACHE_LOADED=false
    elif [[ -n "$key" ]]; then
        __bu_command_cache_file "$key"
        local cache_file=$BU_RET
        if [[ -f "$cache_file" ]]; then
            rm -f "$cache_file"
            bu_log_info "Command cache: invalidated ${cache_file##*/}"
        else
            bu_log_info "Command cache: no cache found for '$key'"
        fi
        # If we invalidated the currently loaded cache, reset the flag
        if [[ "${BU_TOP_LEVEL_MODULE:-}" == "$key" ]]; then
            BU_COMMAND_CACHE_LOADED=false
        fi
    fi
}

# ```
# List cached command registries with their project keys and timestamps.
#
# Returns: BU_RET = array of "key  date  size" lines
# ```
__bu_command_cache_list()
{
    BU_RET=()
    local cache_file key date size
    for cache_file in "$BU_CACHE_DIR"/commands-*.cache; do
        [[ -f "$cache_file" ]] || continue
        key=${cache_file##*/commands-}
        key=${key%.cache}
        date=$(stat -c '%y' "$cache_file" 2>/dev/null || stat -f '%Sm' "$cache_file" 2>/dev/null || echo '?')
        size=$(stat -c '%s' "$cache_file" 2>/dev/null || stat -f '%z' "$cache_file" 2>/dev/null || echo 0)
        # Format size for display
        if ((size >= 1024)); then
            size="$(( (size + 512) / 1024 ))K"
        else
            size="${size}B"
        fi
        BU_RET+=("$key"$'\t'"$date"$'\t'"$size")
    done
}
