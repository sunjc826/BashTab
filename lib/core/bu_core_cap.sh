# ```
# Capability detection and platform identification.
#
# Probes the environment once at init time and produces a canonical picture
# of what is available — binaries, platform identity, and distro-specific
# package names.  The rest of the framework consults BU_CAP and BU_PLATFORM_*
# instead of scattering ad-hoc `command -v` calls.
#
# Variables set (all global, exported where noted):
#   BU_PLATFORM_ID         e.g. "ubuntu", "fedora", "arch", ""
#   BU_PLATFORM_FAMILY     e.g. "debian", "rhel fedora" — space-separated, from ID_LIKE
#   BU_PLATFORM_NAME       e.g. "Ubuntu 24.04.1 LTS" from VERSION / PRETTY_NAME
#   BU_CAP                 associative array: capability name → binary path (or "")
#   BU_CAP_MISS_RESOLVER   optional function name invoked on a probe miss (site glue)
#   BU_PKG_MAP             associative array: binary → "distro:pkg distro:pkg … pip:pkg"
#   BU_COMMAND_UNAVAILABLE associative array: command → reason (populated by registration)
# ```

# bash-ide source=./bu_core_base.sh


# ── Platform detection ────────────────────────────────────────────────

bu_cap_detect_platform()
{
    BU_PLATFORM_ID=
    BU_PLATFORM_FAMILY=
    BU_PLATFORM_NAME=

    if [[ -f /etc/os-release ]]; then
        local id= id_like= name= version= pretty=
        # Evaluate os-release safely into local variables
        eval "$(grep -E '^(ID|ID_LIKE|NAME|VERSION|PRETTY_NAME|VERSION_ID)=' /etc/os-release \
            | sed -e 's/^ID=/id=/' -e 's/^ID_LIKE=/id_like=/' \
                  -e 's/^NAME=/name=/' -e 's/^VERSION_ID=/version=/' \
                  -e 's/^VERSION=/version=/' -e 's/^PRETTY_NAME=/pretty=/')"

        # Strip quotes
        id=${id//\"/}
        id_like=${id_like//\"/}
        name=${name//\"/}
        version=${version//\"/}
        pretty=${pretty//\"/}

        BU_PLATFORM_ID=$id
        BU_PLATFORM_FAMILY=${id_like:-$id}
        if [[ -n "$pretty" ]]; then
            BU_PLATFORM_NAME=$pretty
        elif [[ -n "$name" && -n "$version" ]]; then
            BU_PLATFORM_NAME="$name $version"
        elif [[ -n "$name" ]]; then
            BU_PLATFORM_NAME=$name
        fi
    fi
}

# ── Binary probing ────────────────────────────────────────────────────

# ```
# Probe for a single capability binary.
#
# Params:
# - $1: capability name (key in BU_CAP)
# - $2: primary binary name to look for
# - $3: fallback binary name (optional)
#
# Returns: 0 always. Presence/absence is recorded in BU_CAP[$cap] instead of
# the exit status, because this runs while bu_entrypoint.sh is being sourced —
# a non-zero return here would abort the whole activation under `set -e`.
# ```
bu_cap_probe()
{
    local cap=$1 binary=$2 fallback=${3:-}
    if command -v "$binary" &>/dev/null; then
        BU_CAP[$cap]=$(command -v "$binary")
    elif [[ -n "$fallback" ]] && command -v "$fallback" &>/dev/null; then
        BU_CAP[$cap]=$(command -v "$fallback")
    else
        # Miss: give a site-installed resolver one chance to make the binary
        # available on demand (module systems, etc.) before giving up.
        # The resolver is called as `resolver <cap> <binary>` with output
        # discarded, then we re-probe. It must never abort activation, so a
        # non-zero return is swallowed (this runs while the entrypoint is
        # sourced, possibly under `set -e`).
        local resolver=${BU_CAP_MISS_RESOLVER:-}
        if [[ -n "$resolver" ]] && declare -F "$resolver" &>/dev/null; then
            "$resolver" "$cap" "$binary" &>/dev/null || true
            if command -v "$binary" &>/dev/null; then
                BU_CAP[$cap]=$(command -v "$binary")
            elif [[ -n "$fallback" ]] && command -v "$fallback" &>/dev/null; then
                BU_CAP[$cap]=$(command -v "$fallback")
            else
                BU_CAP[$cap]=
            fi
        else
            BU_CAP[$cap]=
        fi
    fi
    return 0
}

# ```
# Probe all known capabilities.  Called once at init.
# ```
bu_cap_probe_all()
{
    bu_log_debug "Init probe"
    bu_cap_probe fzf      fzf
    bu_cap_probe jq       jq
    bu_cap_probe node     node
    bu_cap_probe jc       jc
    bu_cap_probe docker   docker

    if [[ -n "${BU_CAP[docker]}" ]]
    then
        if { docker info |& grep -q 'permission denied' ; } &>/dev/null
        then
            BU_CAP[docker,sudo]=sudo
        fi
    fi

    bu_cap_probe systemctl systemctl
    bu_cap_probe dpkg     dpkg
    bu_cap_probe rpm      rpm
    bu_cap_probe pacman   pacman
    bu_cap_probe apk      apk
    bu_cap_probe bats     bats
    bu_cap_probe gawk     gawk     awk
    bu_cap_probe gfind    gfind    find
}

# ── Install hints ─────────────────────────────────────────────────────

# Binary → "distro:pkg distro:pkg …" mapping.
# The lookup function matches the current BU_PLATFORM_ID first, then tries
# each member of BU_PLATFORM_FAMILY, and finally falls back to the first
# entry or a generic "pip:xxx" hint.
declare -A -g BU_PKG_MAP=(
    [jq]="debian:jq ubuntu:jq fedora:jq arch:jq alpine:jq"
    [fzf]="debian:fzf ubuntu:fzf fedora:fzf arch:fzf alpine:fzf"
    [node]="debian:nodejs ubuntu:nodejs fedora:nodejs arch:nodejs alpine:nodejs"
    [jc]="pip:jc debian:pipx-fed-jc ubuntu:pipx-fed-jc"
    [docker]="debian:docker.io ubuntu:docker.io fedora:docker arch:docker alpine:docker"
    [dpkg]="debian:dpkg ubuntu:dpkg"
    [rpm]="fedora:rpm arch:rpm"
    [pacman]="arch:pacman"
    [bats]="debian:bats ubuntu:bats fedora:bats arch:bats alpine:bats"
    [gawk]="debian:gawk ubuntu:gawk fedora:gawk arch:gawk alpine:gawk"
    [gfind]="debian:findutils ubuntu:findutils fedora:findutils arch:findutils alpine:findutils"
)

# ```
# Return a human-readable install instruction for a capability.
#
# Params:
# - $1: capability name (e.g. "jq", "fzf")
#
# Returns:
# - BU_RET: install hint string, or empty if the cap is already present
# ```
bu_install_hint()
{
    local cap=$1
    BU_RET=

    # Already installed — no hint needed
    if [[ -n "${BU_CAP[$cap]:-}" ]]; then
        return 0
    fi

    local pkg_entry=${BU_PKG_MAP[$cap]:-}
    if [[ -z "$pkg_entry" ]]; then
        BU_RET="no install hint available"
        return 0
    fi

    # Try exact platform match first
    local pkg
    for entry in $pkg_entry; do
        local distro=${entry%%:*}
        pkg=${entry#*:}
        if [[ "$distro" == "$BU_PLATFORM_ID" ]]; then
            bu_install_hint_for_distro "$distro" "$pkg"
            return 0
        fi
    done

    # Try family members
    if [[ -n "$BU_PLATFORM_FAMILY" ]]; then
        local fam
        for fam in $BU_PLATFORM_FAMILY; do
            for entry in $pkg_entry; do
                distro=${entry%%:*}
                pkg=${entry#*:}
                if [[ "$distro" == "$fam" ]]; then
                    bu_install_hint_for_distro "$distro" "$pkg"
                    return 0
                fi
            done
        done
    fi

    # Fallback: first non-pip entry, or the pip one
    for entry in $pkg_entry; do
        distro=${entry%%:*}
        pkg=${entry#*:}
        if [[ "$distro" != "pip" ]]; then
            bu_install_hint_for_distro "$distro" "$pkg"
            return 0
        fi
    done

    # Last resort: pip
    for entry in $pkg_entry; do
        distro=${entry%%:*}
        pkg=${entry#*:}
        if [[ "$distro" == "pip" ]]; then
            BU_RET="pip install $pkg"
            return 0
        fi
    done

    BU_RET="no install hint available"
}

bu_install_hint_for_distro()
{
    local distro=$1 pkg=$2
    case "$distro" in
        debian|ubuntu)  BU_RET="sudo apt install $pkg" ;;
        fedora|rhel)    BU_RET="sudo dnf install $pkg" ;;
        arch)           BU_RET="sudo pacman -S $pkg" ;;
        alpine)         BU_RET="sudo apk add $pkg" ;;
        pip)            BU_RET="pip install $pkg" ;;
        *)              BU_RET="install $pkg" ;;
    esac
}

# ── Global registry of unavailable commands ───────────────────────────
# Populated by __bu_init_env_commands during registration.
# Maps command name → human-readable reason.
declare -A -g BU_COMMAND_UNAVAILABLE=()

# ── Compatibility cache ───────────────────────────────────────────────
# Caches --is-compatible probe results across shell sessions.
# Avoids forking 30+ bash processes on every `source ./activate`.
#
# Each unique environment (system + available binaries) gets its own cache
# file: $BU_CACHE_DIR/compat-<hash>.cache
#
# The cache is invalidated when:
#   - Platform / bash version changes
#   - A probed binary is installed, removed, or moves
#
# NOT invalidated by PATH changes or script edits (use bu_cap_cache_invalidate
# to force a re-probe after changing command dependencies).

# Active cache hash (empty until fingerprint is computed at init)
BU_COMPAT_CACHE_HASH=
# Active cache file (set after fingerprint is computed)
BU_COMPAT_CACHE_FILE=

# ```
# Generate a fingerprint of the environment: kernel, distro, bash version,
# and the actual paths of all probed capabilities (from BU_CAP).
#
# This is deliberately stable: PATH can change without affecting the hash
# as long as the same binaries are reachable.  Script edits do not affect
# the hash — use bu_cap_cache_invalidate to force a re-probe after
# changing a command's --is-compatible dependencies.
#
# Returns: BU_RET = md5 hash string (empty if md5sum unavailable)
# ```
bu_cap_cache_fingerprint()
{
    BU_RET=
    if ! command -v md5sum &>/dev/null; then
        return 1
    fi
    local hash_input
    hash_input=$(
        uname -srm
        cat /etc/os-release 2>/dev/null
        echo "BASH=$BASH_VERSION"
        # Hash the actual binary paths, not PATH itself.
        # This is stable across PATH changes (venvs, nix shells, etc.)
        # as long as the same tools are reachable.
        local cap
        for cap in $(printf '%s\n' "${!BU_CAP[@]}" | sort); do
            printf 'CAP:%s=%s\n' "$cap" "${BU_CAP[$cap]:-}"
        done
        # Hash the sorted list of gated script paths so adding/removing
        # a gated command invalidates the cache.
        local dir
        for dir in "${!BU_COMMAND_SEARCH_DIRS[@]}"; do
            local find_opts=()
            if ! "${BU_COMMAND_SEARCH_DIR_RECURSIVE[$dir]:-true}"; then
                find_opts+=(-maxdepth 1)
            fi
            find_opts+=(-type f)
            local _gated_path
            while IFS= read -r _gated_path; do
                printf 'GATED:%s\n' "$_gated_path"
            done < <(find "$dir" "${find_opts[@]}" -exec grep -lE -- '--is-compatible[)"]' {} \; 2>/dev/null | sort)
        done
    )
    BU_RET=$(echo "$hash_input" | md5sum | cut -d' ' -f1)
}

# ```
# Resolve the cache file path for a given fingerprint hash.
#
# Params:
# - $1: fingerprint hash
#
# Returns: BU_RET = cache file path
# ```
bu_cap_cache_file_for()
{
    BU_RET=$BU_CACHE_DIR/compat-$1.cache
}

# ```
# Load the cached --is-compatible results from a per-hash cache file.
# Populates BU_COMMAND_UNAVAILABLE.  The hash is in the filename so no
# header validation is needed — file existence is the cache hit.
#
# Params:
# - $1: fingerprint hash that identifies the cache file
#
# Returns: 0 if cache was loaded, 1 if the file doesn't exist
# ```
bu_cap_cache_load()
{
    local fp=$1
    bu_cap_cache_file_for "$fp"
    local cache_file=$BU_RET

    if [[ ! -f "$cache_file" ]]; then
        return 1
    fi

    # Load entries (format: command\texit_code\treason)
    local command exit_code reason
    while IFS=$'\t' read -r command exit_code reason; do
        [[ -z "$command" || "$command" == \#* ]] && continue
        if [[ "$exit_code" != "0" ]]; then
            BU_COMMAND_UNAVAILABLE[$command]=$reason
        fi
    done < "$cache_file"

    BU_COMPAT_CACHE_HASH=$fp
    BU_COMPAT_CACHE_FILE=$cache_file
    bu_log_info "Compat cache loaded from ${cache_file##*/} (${#BU_COMMAND_UNAVAILABLE[@]} unavailable)"
    return 0
}

# ```
# Save the current --is-compatible results to a per-hash cache file.
# Reads BU_COMMAND_UNAVAILABLE (populated by the registration loop) and
# writes tab-separated entries.  Also cleans up the legacy compat.cache.
#
# Params:
# - $1: fingerprint hash for the cache file name
# ```
bu_cap_cache_save()
{
    local fp=$1
    bu_cap_cache_file_for "$fp"
    local cache_file=$BU_RET
    bu_mkdir "$(dirname "$cache_file")"

    {
        printf '# BashTab compat cache — environment %s\n' "$fp"
        local cmd reason
        # Write unavailable commands
        for cmd in "${!BU_COMMAND_UNAVAILABLE[@]}"; do
            printf '%s\t1\t%s\n' "$cmd" "${BU_COMMAND_UNAVAILABLE[$cmd]}"
        done
        # Write commands that ARE available (so the cache knows they were checked)
        local cmd
        for cmd in "${!BU_COMMANDS[@]}"; do
            # Only include gated commands (scripts that declare --is-compatible)
            local script_path=${BU_COMMANDS[$cmd]}
            if [[ -f "$script_path" ]] && grep -qE -- '--is-compatible[)"]' "$script_path" 2>/dev/null; then
                printf '%s\t0\t\n' "$cmd"
            fi
        done
    } > "$cache_file"

    BU_COMPAT_CACHE_HASH=$fp
    BU_COMPAT_CACHE_FILE=$cache_file

    # Clean up legacy single-cache file if it exists
    local legacy_file=$BU_CACHE_DIR/compat.cache
    if [[ -f "$legacy_file" ]]; then
        rm -f "$legacy_file"
    fi

    bu_log_info "Compat cache saved to ${cache_file##*/} ($(grep -cv '^#' "$cache_file" || true) entries)"
}

# ```
# Force-invalidate ALL compat caches so the next activation re-probes.
# Safe to run anytime — just deletes the per-hash cache files.
#
# Usage:
#   bu_cap_cache_invalidate          # clear all cached environments
#   bu_cap_cache_invalidate --stale  # clear only caches older than 7 days
# ```
bu_cap_cache_invalidate()
{
    local mode=${1:-all}
    case "$mode" in
        --stale)
            local cache_file deleted=0
            for cache_file in "$BU_CACHE_DIR"/compat-*.cache; do
                [[ -f "$cache_file" ]] || continue
                # Delete if older than 7 days (604800 seconds)
                if [[ $(date +%s) -gt $(($(stat -c %Y "$cache_file" 2>/dev/null || echo 0) + 604800)) ]]; then
                    rm -f "$cache_file"
                    ((deleted++))
                fi
            done
            bu_log_info "Compat cache: cleaned $deleted stale file(s)"
            ;;
        *)
            local count=0
            for cache_file in "$BU_CACHE_DIR"/compat-*.cache; do
                [[ -f "$cache_file" ]] || continue
                rm -f "$cache_file"
                ((count++))
            done
            rm -f "$BU_CACHE_DIR/compat.cache"  # legacy
            BU_COMPAT_CACHE_HASH=
            BU_COMPAT_CACHE_FILE=
            bu_log_info "Compat cache invalidated ($count file(s) removed)"
            ;;
    esac
}

# ```
# *Description*:
# Settle a deferred --is-compatible probe for one command.  Only acts when the
# command carries the compat_pending marker written by the deferred scan; it
# is otherwise a no-op.  The marker is cleared before probing so the probe
# runs exactly once whatever the outcome.  A failed probe moves the command
# into BU_COMMAND_UNAVAILABLE with the probe's stderr/stdout as the reason and
# records unavailable_path — the same terminal state a scan-time probe
# failure produces — so the existing unavailable-reporting and
# reprobe/recovery paths operate on it unmodified.
#
# *Params*:
# - `$1`: command name
#
# *Returns*:
# - 0 if the command is available (or not pending), 1 if unavailable
# ```
bu_cap_ensure_compat()
{
    local -r cmd=$1
    local script_path=${BU_COMMAND_PROPERTIES[$cmd,compat_pending]:-}
    [[ -n "$script_path" ]] || return 0

    # Clear the marker first so the probe settles exactly once, even on
    # failure — a failed probe must not re-run on every dispatch.
    unset "BU_COMMAND_PROPERTIES[$cmd,compat_pending]"

    local reason
    if reason=$(BU_IS_COMPAT_PROBE=1 bash "$script_path" --is-compatible 2>&1); then
        return 0
    fi

    # Probe failed — leave the exact terminal state a scan-time failure
    # produces so the unavailable-reporting and reprobe/recovery paths work.
    BU_COMMAND_UNAVAILABLE[$cmd]=$reason
    BU_COMMAND_PROPERTIES[$cmd,unavailable_path]=$script_path
    unset "BU_COMMANDS[$cmd]"
    return 1
}

# ```
# *Description*:
# Re-run --is-compatible probes for unavailable commands that have a
# recorded script path.  On success, the command is registered, removed
# from BU_COMMAND_UNAVAILABLE, and the active compat cache is re-saved.
#
# *Params*:
# - `$1` (optional): Specific command to re-probe.  If omitted, reprobes
#   all currently unavailable commands with a recorded path.
#
# *Returns*:
# - 0 if at least one command was recovered, 1 otherwise
# ```
bu_cap_reprobe_unavailable()
{
    local target=${1:-}
    local recovered=0
    local cmd script_path reason

    local -a _cmds_to_probe=()
    if [[ -n "$target" ]]
    then
        if [[ -n "${BU_COMMAND_UNAVAILABLE[$target]:-}" && -n "${BU_COMMAND_PROPERTIES[$target,unavailable_path]:-}" ]]
        then
            _cmds_to_probe=("$target")
        fi
    else
        for cmd in "${!BU_COMMAND_UNAVAILABLE[@]}"
        do
            [[ -n "${BU_COMMAND_PROPERTIES[$cmd,unavailable_path]:-}" ]] && _cmds_to_probe+=("$cmd")
        done
    fi

    for cmd in "${_cmds_to_probe[@]}"
    do
        script_path=${BU_COMMAND_PROPERTIES[$cmd,unavailable_path]}
        if [[ ! -f "$script_path" ]]
        then
            # Script is gone — keep it unavailable
            continue
        fi
        if reason=$(BU_IS_COMPAT_PROBE=1 bash "$script_path" --is-compatible 2>&1)
        then
            # Probe passed — register through the write funnel. settle-from-file
            # clears any stale cached type so dispatch re-derives from the file.
            __bu_command_register "$cmd" "$script_path" --settle-from-file "$script_path" --module ""
            unset 'BU_COMMAND_UNAVAILABLE[$cmd]'
            unset 'BU_COMMAND_PROPERTIES[$cmd,unavailable_path]'
            bu_log_info "Reprobe recovered $cmd"
            : $((recovered++))
        fi
    done

    # Re-save the active compat cache if we recovered anything
    if (( recovered > 0 )) && [[ -n "${BU_COMPAT_CACHE_HASH:-}" ]]
    then
        bu_cap_cache_save "$BU_COMPAT_CACHE_HASH"
    fi

    return $(( recovered > 0 ? 0 : 1 ))
}

# ── Initialization ────────────────────────────────────────────────────

bu_cap_init()
{
    declare -A -g BU_CAP=()

    bu_cap_detect_platform
    bu_cap_probe_all

    bu_log_info "Platform: ${BU_PLATFORM_NAME:-unknown} (${BU_PLATFORM_ID:-unknown})"
    local cap
    for cap in "${!BU_CAP[@]}"; do
        if [[ -n "${BU_CAP[$cap]}" ]]; then
            bu_log_debug "  $cap = ${BU_CAP[$cap]}"
        else
            bu_log_debug "  $cap = (missing)"
        fi
    done
}
