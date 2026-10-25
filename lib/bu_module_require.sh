# ─────────────────────────────────────────────────────────────────────────────
# bu_module_require.sh — dependency-free module loader for BashTab.
#
# Source this file in an activate script BEFORE bu_entrypoint.sh to register
# optional library modules with proper idempotency, autoclone, and presence
# semantics.  Provides a single function:
#
#     bu_module_require NAME [--dir DIR] [--module-file FILE] \
#                            [--git-url URL] [--branch BRANCH] [--required]
#
# Hard constraints (honored here):
#   - No bu_* dependencies, no custom `source`, nothing from the entrypoint.
#   - bash builtins + git only.
#   - Safe under `set -e` and `set -u` (embedder activates run with both).
# ─────────────────────────────────────────────────────────────────────────────

# Emit a padded INFO/WARN/ERR line to stderr.  Stand-in for bu_log_*, which is
# unavailable before bu_entrypoint.sh.  The 7-char padding matches the core
# logger's `printf -v log_prefix '%-7s'` so activate output lines up.
#
# @arg $1 {string} level Log level (INFO, WARN, ERR)
# @arg $@ {string} args... Message
# bash-ide parse-func-sig
__bu_module_require_log()
{
    local level=$1
    shift
    printf '%-7s %s\n' "$level" "$*" >&2
}

# Test whether NAME is already registered in BU_MODULE_LIST.  The match is
# anchored on the entry boundary (start-of-list or after ';') so a name that is
# a suffix of another ("lib" vs "mylib") never false-positives.
#
# @arg $1 {string} name Module name
#
# @returns
# - 0 if registered, 1 otherwise
# bash-ide parse-func-sig
__bu_module_require_registered()
{
    local -r name=$1
    local -r list=${BU_MODULE_LIST:-}
    [[ "$list" == "$name:"* || "$list" == *";$name:"* ]]
}

# Modules whose *_bu_module.sh script is being sourced by bu_module_require,
# innermost last: the requirer of a nested bu_module_require call. Kept across
# re-sourcing this file mid-require.
declare -p __BU_MODULE_REQUIRE_STACK &>/dev/null || __BU_MODULE_REQUIRE_STACK=()

# Record that module PARENT requires module DEP in BU_MODULE_DEPS, an exported
# "parent>dep;..." list. bu_entrypoint.sh orders modules (config files and
# preinit callbacks) so each comes after the modules it requires. An edge
# already recorded is not added again, so re-activation leaves the list as is.
#
# @arg $1 {string} parent Requiring module (empty: nothing to record)
# @arg $2 {string} dep Required module
# bash-ide parse-func-sig
__bu_module_require_add_dep()
{
    local -r parent=$1
    local -r dep=$2
    [[ -n "$parent" && "$parent" != "$dep" ]] || return 0
    case ";${BU_MODULE_DEPS:-};" in
    *";$parent>$dep;"*) return 0 ;;
    esac
    BU_MODULE_DEPS="${BU_MODULE_DEPS:-}$parent>$dep;"
    export BU_MODULE_DEPS
    return 0
}

# Register a library module by sourcing its *_bu_module.sh script (which
# appends a `name:version:preinit_path;` entry to BU_MODULE_LIST).
#
# Semantics, in order:
#   1. Idempotent: return 0 immediately if NAME is already registered
#      (anchored match — diamond-safe for nested requires).
#   2. Autoclone: if --dir is missing and --git-url was given, clone it
#      (respecting --branch).  Interactive ttys are asked Y/n first;
#      non-interactive clones proceed silently.  Failure is a WARN that falls
#      through to the missing-module policy, not an abort.
#   3. Resolve the module script: --module-file wins; else glob
#      <dir>/*_bu_module.sh.  Exactly one match required; multiple matches is
#      an error telling the user to disambiguate with --module-file.
#   4. Presence policy: missing + --required → ERR and return 1 (an errexit
#      activate aborts loudly); missing + optional → one INFO line and return
#      0.  Never a silent skip.
#   5. Register: `builtin source` the script (bypassing any source() override),
#      then verify NAME actually appeared in BU_MODULE_LIST — a mismatch is a
#      WARN, failing only under --required.
#
# @arg $1 string Module name
# @option --dir DIR: directory containing the module's *_bu_module.sh
# @option --module-file FILE: explicit module script path (overrides the glob)
# @option --git-url URL: clone source if --dir is absent
# @option --branch BRANCH: branch to clone (defaults to the repo's default branch)
# @option --required: fail (return 1) instead of skipping when the module is missing
#
# @returns
# - 0 on success (or when an optional module is skipped)
# - 1 on usage errors, required-module failures, or ambiguous globs under
#   --required
bu_module_require()
{
    local name=
    local dir=
    local module_file=
    local git_url=
    local branch=
    local required=false
    local arg=

    # ── Argument parsing / usage validation ───────────────────────
    if (($# == 0)); then
        __bu_module_require_log ERR "bu_module_require: missing module NAME"
        return 1
    fi

    name=$1
    shift

    if [[ -z "$name" || "$name" == -* ]]; then
        __bu_module_require_log ERR "bu_module_require: invalid module name '$name' (looks like a flag)"
        return 1
    fi

    while (($#)); do
        arg=$1
        case "$arg" in
        --dir)
            if (($# < 2)); then
                __bu_module_require_log ERR "bu_module_require '$name': option --dir requires a value"
                return 1
            fi
            dir=$2
            shift 2
            ;;
        --dir=*)
            dir=${arg#--dir=}
            shift
            ;;
        --module-file)
            if (($# < 2)); then
                __bu_module_require_log ERR "bu_module_require '$name': option --module-file requires a value"
                return 1
            fi
            module_file=$2
            shift 2
            ;;
        --module-file=*)
            module_file=${arg#--module-file=}
            shift
            ;;
        --git-url)
            if (($# < 2)); then
                __bu_module_require_log ERR "bu_module_require '$name': option --git-url requires a value"
                return 1
            fi
            git_url=$2
            shift 2
            ;;
        --git-url=*)
            git_url=${arg#--git-url=}
            shift
            ;;
        --branch)
            if (($# < 2)); then
                __bu_module_require_log ERR "bu_module_require '$name': option --branch requires a value"
                return 1
            fi
            branch=$2
            shift 2
            ;;
        --branch=*)
            branch=${arg#--branch=}
            shift
            ;;
        --required)
            required=true
            shift
            ;;
        *)
            __bu_module_require_log ERR "bu_module_require '$name': unknown option '$arg'"
            return 1
            ;;
        esac
    done

    if [[ -z "$dir" && -z "$module_file" ]]; then
        __bu_module_require_log ERR "bu_module_require '$name': one of --dir or --module-file is required"
        return 1
    fi

    # ── 0. Dependency edge: the module whose script is being sourced, or the
    #       top-level module (the first BU_MODULE_LIST entry) requires NAME.
    #       Recorded even when NAME is already registered (diamonds). ──
    local parent=
    if ((${#__BU_MODULE_REQUIRE_STACK[@]})); then
        parent=${__BU_MODULE_REQUIRE_STACK[${#__BU_MODULE_REQUIRE_STACK[@]}-1]}
    else
        parent=${BU_MODULE_LIST:-}
        parent=${parent%%:*}
    fi
    __bu_module_require_add_dep "$parent" "$name"

    # ── 1. Idempotency (anchored: start-of-list or after ';') ─────
    if __bu_module_require_registered "$name"; then
        return 0
    fi

    # ── 2. Autoclone (only when --dir is the operative source) ────
    if [[ -z "$module_file" && -n "$git_url" && ! -d "$dir" ]]; then
        local -a clone_args=(clone)
        if [[ -n "$branch" ]]; then
            clone_args+=(--branch "$branch")
        fi
        clone_args+=("$git_url" "$dir")

        if [[ -t 0 ]]; then
            local answer=
            printf 'bu_module_require: clone %s into %s? [Y/n] ' "$git_url" "$dir" >&2
            IFS= read -r answer || true
            case "${answer:-}" in
            [nN]|[nN][oO])
                __bu_module_require_log WARN "bu_module_require '$name': clone skipped by user; continuing without it"
                ;;
            *)
                if ! git "${clone_args[@]}" >/dev/null 2>&1; then
                    __bu_module_require_log WARN "bu_module_require '$name': clone of $git_url failed; continuing without it"
                fi
                ;;
            esac
        else
            if ! git "${clone_args[@]}" >/dev/null 2>&1; then
                __bu_module_require_log WARN "bu_module_require '$name': clone of $git_url failed; continuing without it"
            fi
        fi
    fi

    # ── 3. Resolve the module script ──────────────────────────────
    local resolved_file=$module_file
    if [[ -z "$resolved_file" ]]; then
        local -a matches=()
        local f=
        for f in "$dir"/*_bu_module.sh; do
            [[ -f "$f" ]] || continue
            matches+=("$f")
        done

        if (( ${#matches[@]} > 1 )); then
            __bu_module_require_log ERR "bu_module_require '$name': multiple *_bu_module.sh files found in '$dir'; pass --module-file to disambiguate"
            if "$required"; then
                return 1
            fi
            return 0
        elif (( ${#matches[@]} == 1 )); then
            resolved_file=${matches[0]}
        fi
    fi

    # ── 4. Presence policy (never a silent skip) ──────────────────
    local where=
    if [[ -n "$module_file" ]]; then
        where="--module-file $module_file"
    else
        where="--dir $dir"
    fi

    if [[ -z "$resolved_file" || ! -r "$resolved_file" ]]; then
        if "$required"; then
            __bu_module_require_log ERR "bu_module_require '$name': required module script not found ($where)"
            return 1
        fi
        __bu_module_require_log INFO "bu_module_require '$name': module script not found ($where); skipping optional module"
        return 0
    fi

    # ── 5. Register (builtin source bypasses any source() override) ─
    __BU_MODULE_REQUIRE_STACK+=("$name")
    if ! builtin source "$resolved_file"; then
        unset '__BU_MODULE_REQUIRE_STACK[${#__BU_MODULE_REQUIRE_STACK[@]}-1]'
        __bu_module_require_log WARN "bu_module_require '$name': failed to source module script '$resolved_file'"
        if "$required"; then
            return 1
        fi
        return 0
    fi
    unset '__BU_MODULE_REQUIRE_STACK[${#__BU_MODULE_REQUIRE_STACK[@]}-1]'

    if ! __bu_module_require_registered "$name"; then
        __bu_module_require_log WARN "bu_module_require '$name': module script '$resolved_file' did not register '$name' in BU_MODULE_LIST"
        if "$required"; then
            return 1
        fi
        return 0
    fi

    return 0
}

# Sourcing may happen under `set -e`: never leak a non-zero status to the
# user's shell.
return 0
