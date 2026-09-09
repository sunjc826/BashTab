# The purpose of early init is so that we can make some things available to downstream repos
# to use in their pre-init callbacks. Most importantly, the builtin bu commands.
# This avoids some of the need to do double initialization, i.e.
# initialize BashTab fully just to have the bu builtin commands,
# then call the bu builtin commands inside a downstream repo activation script,
# then reinitialize again.

# bash-ide source=./bu_core_base.sh
# bash-ide source=./bu_core_autocomplete.sh
# bash-ide source=./bu_core_cache.sh

# ```
# *Description*:
# Read an explicit `# Dispatch: <type>` declaration from a command script
# header (first 8 lines).  Returns `source` or `execute` in BU_RET, or
# empty when the script declares no dispatch intent.
#
# *Params*:
# - `$1`: Path to the command script
#
# *Returns*:
# - BU_RET: declared dispatch type, or empty
# ```
__bu_command_dispatch_decl()
{
    BU_RET=
    local -r file=$1
    local _decl=
    if [[ -v __BU_COMMAND_HEADER_DISPATCH[$file] ]]
    then
        # Fast path: batch-scanned files have their Dispatch pre-extracted.
        _decl=${__BU_COMMAND_HEADER_DISPATCH[$file]}
    else
        __bu_command_header_get "$file" "Dispatch" _decl
    fi
    # Only "source" or "execute" are valid dispatch types.
    case "$_decl" in
    source|execute) BU_RET=$_decl ;;
    esac
    return 0
}

__bu_init_env_commands()
{
    # ── Recursion guard for --is-compatible probes ──
    # The framework probes gated commands with `BU_IS_COMPAT_PROBE=1 bash
    # <script> --is-compatible`.  An executable command generated from the
    # older script_template.sh sources bu_entrypoint before honoring
    # --is-compatible; that entrypoint load would re-run this scan and
    # re-probe every gated command, each spawning another bash → infinite
    # recursion that hangs until Ctrl-C.  Skip the scan entirely here: the
    # probe only needs the bu_* functions (loaded earlier), not the command
    # registry, and its own scan results are discarded anyway.
    if [[ "${BU_IS_COMPAT_PROBE:-}" == 1 ]]; then
        return 0
    fi

    # ── Determine whether --is-compatible probes can be skipped ──
    local compat_cache_valid=false
    local fingerprint

    if "$BU_COMMAND_CACHE_LOADED"; then
        # Command cache was loaded — BU_COMMAND_UNAVAILABLE is already
        # populated.  Use it to skip --is-compatible probes.
        compat_cache_valid=true
    elif "$BU_COMMAND_CACHE_ENABLED" && bu_cap_cache_fingerprint; then
        # Try the per-environment compat cache (only when caching is enabled)
        fingerprint=$BU_RET
        if bu_cap_cache_load "$fingerprint"; then
            compat_cache_valid=true
        fi
    fi

    local _scan_lazy=${BU_COMMAND_SCAN_LAZY:-false}

    # The command scan is the header cache's invalidation boundary: files may
    # have changed since the last scan, so drop the memo before re-reading.
    # No per-file stat fingerprinting needed — the scan re-reads everything.
    if ! "$_scan_lazy"; then
        __BU_COMMAND_HEADER_BLOCK=()
        __BU_COMMAND_HEADER_PARSED=()
        __BU_COMMAND_HEADER_DISPATCH=()
    fi

    local dir
    local file
    local convert_file_to_subcommand
    local command
    # Scan-time pipeline-contract coverage buckets (aggregated into one warning
    # per bucket after the full scan, not one warning per command).
    local -a _pipeline_contract_missing=()
    local -a _pipeline_contract_missing_fields=()
    for dir in "${!BU_COMMAND_SEARCH_DIRS[@]}"
    do
        bu_env_append_path "$dir"

        # ── Lazy mode: defer the scan body, only do PATH appends ──
        if "$_scan_lazy"; then
            continue
        fi

        convert_file_to_subcommand=${BU_COMMAND_SEARCH_DIRS[$dir]}
        local find_opts=()
        if ! "${BU_COMMAND_SEARCH_DIR_RECURSIVE[$dir]:-true}"; then
            find_opts+=(-maxdepth 1)
        fi
        find_opts+=(-type f)

        # Per-directory ignore file: <dir>/.bashtabignore
        # One glob pattern per line; # comments and blank lines are ignored.
        local -a ignore_patterns=()
        if [[ -f "$dir/.bashtabignore" ]]; then
            local _line
            while IFS= read -r _line; do
                _line=${_line%%#*}               # strip # comments
                _line=${_line#"${_line%%[![:space:]]*}"}  # ltrim
                _line=${_line%"${_line##*[![:space:]]}"}  # rtrim
                [[ -n "$_line" ]] && ignore_patterns+=("$_line")
            done < "$dir/.bashtabignore"
        fi

        # Collect candidate files once, then batch-parse their headers in a
        # single awk process so the per-file registration loop below only
        # reads the memo (no per-file awk fork).
        local -a _dir_files=()
        local _dir_file
        while IFS= read -r _dir_file
        do
            _dir_files+=("$_dir_file")
        done < <(find "$dir" "${find_opts[@]}" -printf "%P\n" 2>/dev/null)

        __bu_command_headers_batch "$dir" "${_dir_files[@]}"

        # Batch-detect --is-compatible scripts with a single grep so the
        # per-file loop below does a pure membership test (no per-file fork).
        local -A _dir_compat_files=()
        if ((${#_dir_files[@]}))
        then
            local -a _compat_paths=()
            local _cr
            for _cr in "${_dir_files[@]}"
            do
                _compat_paths+=("$dir/$_cr")
            done
            local _cf
            while IFS= read -r _cf
            do
                _dir_compat_files[$_cf]=1
            done < <(grep -lE -- '--is-compatible[)"]' "${_compat_paths[@]}" 2>/dev/null)
        fi

        for file in "${_dir_files[@]}"
        do
            # Inline dirname/basename (bu_dirname/bu_basename are function
            # calls; this hot loop runs once per file).
            local file_dir file_name
            case "$file" in
            */*) file_dir=${file%/*}; file_name=${file##*/} ;;
            *)   file_dir=.; file_name=$file ;;
            esac

            if [[ ! -e "$dir"/"$file_dir"/__bu_entrypoint_decl.sh ]]
            then
                bu_gen_substitute BU_DIR <"$BU_LIB_TEMPLATE_DIR"/bu_entrypoint_decl_template.sh >"$dir"/"$file_dir"/__bu_entrypoint_decl.sh
            fi

            # Builtin skip list: docs, dotfiles, internal helpers
            case "$file_name" in
            *.txt|README|README.*|*.md) 
                continue
                ;;
            __*)
                # 2 underscores in front can be used to hide scripts
                continue
                ;;
            .*)
                # Dotfiles (hidden files)
                continue
                ;;
            esac

            # Per-directory .bashtabignore patterns: match against
            # path-relative-to-dir ($file) or basename ($file_name)
            local _skip=false
            local _pat
            for _pat in "${ignore_patterns[@]}"; do
                if [[ "$file" == $_pat || "$file_name" == $_pat ]]; then
                    _skip=true
                    break
                fi
            done
            "$_skip" && continue

            local script_path=$dir/$file
            command=${file%.sh}
            if [[ -n "$convert_file_to_subcommand" ]]
            then
                # Converter callback return codes:
                #   0 — use BU_RET as the command name
                #   1 — keep the default name (file name without .sh)
                #   2 — REJECT: skip this file entirely, do not register
                # The || capture is errexit-safe: prevents set -e from
                # aborting when the converter returns non-zero.
                local convert_rc=0
                $convert_file_to_subcommand "$file" || convert_rc=$?
                case $convert_rc in
                0) command=$BU_RET ;;
                2) continue ;;
                # 1 or any other non-zero: keep default command name
                esac
            fi

            # If the script declares --is-compatible, run it to check.
            # Scripts without it are assumed compatible (backward compat).
            # Matches both case-style (--is-compatible)) and if-style (--is-compatible").
            if [[ -n "${_dir_compat_files[$script_path]:-}" ]]; then
                if $compat_cache_valid; then
                    # Cache hit — check if this command was marked unavailable
                    if [[ -n "${BU_COMMAND_UNAVAILABLE[$command]:-}" ]]; then
                        BU_COMMAND_PROPERTIES[$command,unavailable_path]=$script_path
                        continue
                    fi
                elif "$BU_COMMAND_COMPAT_DEFERRED"; then
                    # Deferred mode — register optimistically and mark the
                    # script path pending.  The probe runs on first dispatch
                    # (see bu_cap_ensure_compat) instead of at scan time.
                    BU_COMMAND_PROPERTIES[$command,compat_pending]=$script_path
                else
                    # Cache miss — probe
                    local reason
                    if ! reason=$(BU_IS_COMPAT_PROBE=1 bash "$script_path" --is-compatible 2>&1); then
                        BU_COMMAND_UNAVAILABLE[$command]=$reason
                        BU_COMMAND_PROPERTIES[$command,unavailable_path]=$script_path
                        continue
                    fi
                fi
            fi

            # Register through the write funnel: the definition write settles
            # the dispatch type from the file's # Dispatch: header (unsetting
            # any stale cached type when the header is absent).
            local _dir_module=${BU_COMMAND_SEARCH_DIR_MODULE[$dir]:-}
            __bu_command_register "$command" "$script_path" \
                --settle-from-file "$script_path" \
                --module "$_dir_module"

            # ── Pipeline-contract coverage collection (memo-only reads) ──
            # Gated behind BU_PIPELINE_CONTRACT_WARN (on by default). Reads the
            # batch header memo populated above — no per-file forks.
            if [[ "${BU_PIPELINE_CONTRACT_WARN:-true}" != false ]]
            then
                local _pc_effect=${BU_OUT_STAGE_EFFECT["bu $command"]:-}
                local _pc_header=
                if [[ -z "$_pc_effect" ]]
                then
                    __bu_command_header_get "$script_path" "Pipeline" _pc_header
                fi
                if [[ -z "$_pc_effect" && -z "$_pc_header" ]]
                then
                    # No # Pipeline: header and no registered stage effect.
                    _pipeline_contract_missing+=("$command")
                elif [[ "$_pc_header" == transform || "$_pc_header" == consume ]]
                then
                    # A stdin-extracting stage must declare the fields it reads,
                    # otherwise it passes the post-pipe filter on format alone.
                    local _pc_req_all= _pc_req_any=
                    __bu_command_header_get "$script_path" "Requires-All" _pc_req_all
                    __bu_command_header_get "$script_path" "Requires-Any" _pc_req_any
                    if [[ -z "$_pc_req_all" && -z "$_pc_req_any" ]]
                    then
                        _pipeline_contract_missing_fields+=("$command")
                    fi
                fi
            fi
        done
    done

    # ── Aggregated pipeline-contract warnings ──
    # One message per bucket after the full scan.  Gated behind
    # BU_PIPELINE_CONTRACT_WARN (on by default; "false" silences).
    if [[ "${BU_PIPELINE_CONTRACT_WARN:-true}" != false ]]
    then
        if ((${#_pipeline_contract_missing[@]} > 0))
        then
            local -a _pcw_head=("${_pipeline_contract_missing[@]:0:5}")
            local _pcw_names="${_pcw_head[*]}"
            if ((${#_pipeline_contract_missing[@]} > 5))
            then
                _pcw_names+=" ..."
            fi
            bu_log_warn "${#_pipeline_contract_missing[@]} command(s) have no pipeline contract (${_pcw_names}): add a '# Pipeline:' header or register a stage effect"
        fi
        if ((${#_pipeline_contract_missing_fields[@]} > 0))
        then
            local -a _pcw_head2=("${_pipeline_contract_missing_fields[@]:0:5}")
            local _pcw_names2="${_pcw_head2[*]}"
            if ((${#_pipeline_contract_missing_fields[@]} > 5))
            then
                _pcw_names2+=" ..."
            fi
            bu_log_warn "${#_pipeline_contract_missing_fields[@]} consume/transform command(s) are missing a field contract (${_pcw_names2}): declare the fields their stdin extraction reads via '# Requires-All:' or '# Requires-Any:'"
        fi
    fi

    # Save compat cache if we probed fresh (only when caching is enabled,
    # the command cache wasn't loaded, and deferred mode is off — nothing
    # was probed in deferred mode, and saving would write an all-available
    # cache that poisons later non-deferred shells).
    if "$BU_COMMAND_CACHE_ENABLED" && ! "$BU_COMMAND_CACHE_LOADED" && ! $compat_cache_valid && ! "$BU_COMMAND_COMPAT_DEFERRED" && [[ -n "$fingerprint" ]]; then
        bu_cap_cache_save "$fingerprint"
    fi

    if "$_scan_lazy"; then
        __BU_COMMAND_SCAN_PENDING=true
    fi
}

# ```
# *Description*:
# Run the deferred command-registry scan if BU_COMMAND_SCAN_LAZY deferred it.
# Called at the top of the CLI dispatcher and completion entry point so the
# first by-name dispatch or completion transparently completes initialization.
# Cheap no-op when the scan already ran.
# ```
bu_ensure_command_scan()
{
    if [[ "${__BU_COMMAND_SCAN_PENDING:-false}" != true ]]; then
        return 0
    fi
    __BU_COMMAND_SCAN_PENDING=false
    # Temporarily clear lazy mode so __bu_init_env_commands runs the scan
    local _saved=${BU_COMMAND_SCAN_LAZY:-}
    BU_COMMAND_SCAN_LAZY=false
    __bu_init_env_commands
    if [[ -n "$_saved" ]]; then
        BU_COMMAND_SCAN_LAZY=$_saved
    else
        unset BU_COMMAND_SCAN_LAZY
    fi
    # Register script-level completions from the freshly-scanned registry.
    # Guarded: __bu_init_autocomplete is defined in bu_core_init.sh, which is
    # sourced AFTER the pre-init callbacks.  A module pre-init that dispatches
    # `bu` (e.g. `bu import-environment`) reaches this scan via the lazy path
    # before the function exists; in that case the later bu_init registers
    # completions anyway.
    if declare -F __bu_init_autocomplete &>/dev/null; then
        __bu_init_autocomplete
    fi
}

__bu_init_env_commands
# Get bu_impl.sh on PATH so that bu can be called
bu_env_append_path "$BU_LIB_BINSRC_DIR"
