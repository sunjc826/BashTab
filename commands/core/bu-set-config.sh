#!/usr/bin/env bash
# Pipeline: standalone
# Dispatch: source
# Synopsis: Set a BashTab configuration value
# Help-Topic: config
function __bu_bu_set_config_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

# Machine-local settings file. Overridable for tests.
local file=${BU_CONFIG_LOCAL_FILE:-"$BU_DIR"/config/bu_config_local.sh}
local file_explicit=false
local layer=

# Managed block markers
local -r __BU_SET_CONFIG_OPENER='# >>> bu set-config managed block -- do not hand-edit inside'
local -r __BU_SET_CONFIG_CLOSER='# <<< bu set-config managed block'

local var=
local value=
local is_unset=false
local is_help=false
local is_dry_run=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    -u|--unset)# _FLAG
        # Remove VAR's assignments from the settings file (registered default restored)
        is_unset=true
        ;;
    --dry-run|--what-if) # _FLAG
        is_dry_run=true
        ;;
    -h|--help)# _FLAG
        # Print help
        is_help=true
        ;;
    -f|--file)# FILE
        # Write to FILE instead of the default settings file
        bu_parse_positional $# "${BU_AUTOCOMPLETE_SPEC_FILE[@]}" --hint "Settings file path"
        file=${!shift_by}
        file_explicit=true
        ;;
    -l|--layer)# LAYER
        # Route write through a registered layer resolver
        bu_parse_positional $# --ret __bu_config_completion_layers ret-- --hint "Config layer name"
        layer=${!shift_by}
        ;;
    *)
        # Bare positionals: VAR then VALUE
        if bu_env_is_in_autocomplete && (($# == 1))
        then
            # $1 is the word being completed
            if [[ "$1" == -* ]]
            then
                : # keep bu_parse_multiselect's --options-at completion
            elif [[ -z "$var" ]]
            then
                autocompletion=(--ret __bu_config_completion_names ret--)
            elif [[ -z "$value" ]]
            then
                autocompletion=(--ret __bu_config_completion_values "$var" ret--)
            fi
            bu_autocomplete
            return 0
        fi
        if [[ -z "$var" ]]
        then
            var=$1
        elif [[ -z "$value" ]]
        then
            value=$1
        else
            bu_parse_error_enum "$1"
            break
        fi
        ;;
    esac
    if "$is_help"
    then
        break
    fi
    if (( $# < shift_by ))
    then
        bu_parse_error_argn "$1" $#
        break
    fi
    shift "$shift_by"
done

if bu_env_is_in_autocomplete
then
    bu_autocomplete
    return 0
fi

if "$is_help"
then
    bu_autohelp
    return 0
fi

# ── Validate VAR ────────────────────────────────────────────
if ! bu_config_name_is_valid "$var"
then
    local _prefix_list="${BU_CONFIG_NAME_PREFIXES[*]}"
    bu_log_err "Setting name must match ^(${_prefix_list// /|})[A-Z0-9_]+\$ (got: '${var:-<empty>}')"
    bu_log_err "Usage: bu set-config BU_SOME_SETTING value | --unset BU_SOME_SETTING"
    bu_scope_pop_function
    return 1
fi

# ── Registry-driven value validation ─────────────────────────
# Validate BEFORE touching the file.
if ! "$is_unset" && [[ -z "$value" ]]
then
    bu_log_err "Missing value. Usage: bu set-config $var VALUE (see also: bu get-config)"
    bu_scope_pop_function
    return 1
fi

if ! "$is_unset" && [[ "${BU_CONFIG_PROPERTIES[$var,registered]:-}" == true ]]
then
    if bu_config_validate_value "$var" "$value"
    then
        value=$BU_RET
    else
        bu_log_err "Invalid value for $var: $BU_RET"
        bu_scope_pop_function
        return 1
    fi
elif ! "$is_unset" && [[ "${BU_CONFIG_PROPERTIES[$var,registered]:-}" != true ]]
then
    bu_log_warn "$var is not a registered setting; storing anyway (register it with bu_config_register)"
fi

if "$is_dry_run"
then
    if "$is_unset"; then
        bu_log_info "Would unset $var in $file"
    else
        bu_log_info "Would set $var=$value in $file"
    fi
    bu_scope_pop_function
    return 0
fi

# ── Layer resolution ─────────────────────────────────────────

if "$file_explicit" && [[ -n "$layer" ]]
then
    bu_log_warn "--file and --layer both given; --file takes precedence, ignoring --layer $layer"
    layer=
elif [[ -n "$layer" ]]
then
    if ! bu_config_layer_file "$layer"
    then
        bu_scope_pop_function
        return 1
    fi
    file=$BU_RET
    # Cross-layer warning: writing to a layer other than the natural one
    if [[ "${BU_CONFIG_PROPERTIES[$var,registered]:-}" == true ]]
    then
        local _natural_layer=${BU_CONFIG_PROPERTIES[$var,layer]:-local}
        if [[ "$layer" != "$_natural_layer" ]]
        then
            bu_log_warn "Writing $var to layer '$layer' but its natural layer is '$_natural_layer'; the cascade may shadow this value"
        fi
    fi
elif ! "$file_explicit" && [[ "${BU_CONFIG_PROPERTIES[$var,registered]:-}" == true ]]
then
    # No --file, no --layer: use the setting's natural layer if registered
    local _natural_layer=${BU_CONFIG_PROPERTIES[$var,layer]:-}
    if [[ -n "$_natural_layer" && "$_natural_layer" != local ]]
    then
        if ! bu_config_layer_file "$_natural_layer"
        then
            bu_scope_pop_function
            return 1
        fi
        file=$BU_RET
    fi
fi

# ── Managed block file helpers ───────────────────────────────

# Parse the managed block from file content. Reads $file into a string
# and locates the opener/closer marker lines.
#
# Sets these locals directly (caller must declare them):
#   _mb_before   – content before the opener (may be empty)
#   _mb_inside   – content between opener and closer (the old block body)
#   _mb_after    – content after the closer (may be empty)
#   _mb_ok       – true if markers are valid (0/0 or 1/1), false on degeneracy
__bu_set_config_parse_block()
{
    local content
    if [[ -f "$file" ]]
    then
        content=$(cat "$file")
    fi

    _mb_before=
    _mb_inside=
    _mb_after=
    _mb_ok=true

    local oc cc
    oc=$(grep -cF "$__BU_SET_CONFIG_OPENER" <<<"$content" || true)
    cc=$(grep -cF "$__BU_SET_CONFIG_CLOSER" <<<"$content" || true)

    if (( oc == 0 && cc == 0 ))
    then
        _mb_before=$content
        return 0
    fi

    if (( oc != 1 || cc != 1 ))
    then
        _mb_ok=false
        _mb_oc=$oc
        _mb_cc=$cc
        return 0
    fi

    # Find line numbers of markers
    local ol cl
    ol=$(grep -nF "$__BU_SET_CONFIG_OPENER" <<<"$content" | head -1 | cut -d: -f1)
    cl=$(grep -nF "$__BU_SET_CONFIG_CLOSER" <<<"$content" | head -1 | cut -d: -f1)

    if (( cl <= ol ))
    then
        _mb_ok=false
        return 0
    fi

    # Split: before, inside, after
    local total_lines
    total_lines=$(wc -l <<<"$content")

    if (( ol > 1 ))
    then
        _mb_before=$(head -n $((ol - 1)) <<<"$content")
        # head strips trailing blank lines; preserve the trailing newline
        if [[ "$_mb_before" != *$'\n' ]]
        then
            _mb_before+=$'\n'
        fi
    fi

    if (( cl > ol + 1 ))
    then
        # Lines between opener and closer
        _mb_inside=$(sed -n "$((ol + 1)),$((cl - 1))p" <<<"$content")
        if [[ -n "$_mb_inside" && "$_mb_inside" != *$'\n' ]]
        then
            _mb_inside+=$'\n'
        fi
    fi

    if (( cl < total_lines ))
    then
        _mb_after=$(tail -n $((total_lines - cl)) <<<"$content")
    fi
}

# Read managed pairs from the inside block content.
# Sets _mb_pairs as an associative array: NAME → value
__bu_set_config_read_pairs()
{
    local inside=$1
    local line name val
    while IFS= read -r line
    do
        [[ -z "$line" ]] && continue
        name=${line%%=*}
        val=${line#*=}
        [[ -n "$name" ]] && _mb_pairs[$name]=$val
    done <<<"$inside"
}

# Build the new file content and write atomically.
# Args: the new managed block body (one NAME=value per line, sorted).
__bu_set_config_write_block()
{
    local new_body=$1
    mkdir -p "${file%/*}"
    local tmpfile
    tmpfile=$(mktemp "$file.XXXXXX")

    {
        if [[ -n "$_mb_before" ]]
        then
            printf '%s' "$_mb_before"
            # Ensure before content ends with exactly one newline
            [[ "$_mb_before" != *$'\n' ]] && printf '\n'
        fi
        printf '%s\n' "$__BU_SET_CONFIG_OPENER"
        if [[ -n "$new_body" ]]
        then
            printf '%s' "$new_body"
            [[ "$new_body" != *$'\n' ]] && printf '\n'
        fi
        printf '%s\n' "$__BU_SET_CONFIG_CLOSER"
        if [[ -n "$_mb_after" ]]
        then
            printf '%s' "$_mb_after"
            [[ "$_mb_after" != *$'\n' ]] && printf '\n'
        fi
    } > "$tmpfile"

    mv "$tmpfile" "$file"
}

# Check for hand-written assignments of $var OUTSIDE the managed block
# and emit an advisory warning. Never blocks the write.
# Position-aware: after-block lines override the managed value;
# before-block lines lose to it.
__bu_set_config_warn_outside_assignments()
{
    local name=$1
    local pattern='^[[:space:]]*(export[[:space:]]+)?'"$name"'='
    local match_line

    # 1. Check AFTER the block first — these override the managed value
    if [[ -n "$_mb_after" ]]
    then
        match_line=$(grep -nE "$pattern" <<<"$_mb_after" 2>/dev/null | head -1 || true)
        if [[ -n "$match_line" ]]
        then
            local lineno=${match_line%%:*}
            bu_log_warn "note: $name is also assigned AFTER the managed block (line $lineno in the after-block region) — that hand-written line overrides the value just set (file order wins)"
            return 0
        fi
    fi

    # 2. Check BEFORE the block — the managed value wins
    if [[ -n "$_mb_before" ]]
    then
        match_line=$(grep -nE "$pattern" <<<"$_mb_before" 2>/dev/null | head -1 || true)
        if [[ -n "$match_line" ]]
        then
            local lineno=${match_line%%:*}
            bu_log_warn "note: $name also assigned before the managed block (line $lineno); the managed value wins by source order"
        fi
    fi
}

# ── Main file operation ──────────────────────────────────────

local -A _mb_pairs=()
local _mb_before _mb_inside _mb_after _mb_ok _mb_oc _mb_cc

__bu_set_config_parse_block

if ! "$_mb_ok"
then
    bu_log_err "Managed block markers in $file are inconsistent (expected 0 or 1 opener+closer pair, found ${_mb_oc:-0} opener(s) and ${_mb_cc:-0} closer(s))."
    bu_log_err "Please hand-edit the file to fix or remove the markers, then retry."
    bu_scope_pop_function
    return 1
fi

# Read existing managed pairs
if [[ -n "$_mb_inside" ]]
then
    __bu_set_config_read_pairs "$_mb_inside"
fi

if "$is_unset"
then
    # Remove the pair from the managed block
    unset '_mb_pairs[$var]'

    # Rebuild block body: sorted NAME=value lines
    local -a _sorted_keys=()
    local _key
    for _key in "${!_mb_pairs[@]}"
    do
        [[ -n "${_mb_pairs[$_key]}" ]] && _sorted_keys+=("$_key")
    done
    local _new_body=
    if ((${#_sorted_keys[@]} > 0))
    then
        local _sorted
        _sorted=$(printf '%s\n' "${_sorted_keys[@]}" | sort)
        while IFS= read -r _key
        do
            _new_body+="${_key}=${_mb_pairs[$_key]}"$'\n'
        done <<<"$_sorted"
    fi

    __bu_set_config_write_block "$_new_body"

    if [[ -n "${BU_CONFIG_PROPERTIES[$var,default]:-}" ]]
    then
        declare -g "$var=${BU_CONFIG_PROPERTIES[$var,default]}"
    else
        unset "$var"
        source "$BU_DIR"/config/bu_config_dynamic.sh
    fi
    printf 'Unset %s in %s (default applies)\n' "$var" "$file"
    bu_scope_pop_function
    return 0
fi

# Set: update/add the pair
_mb_pairs[$var]=$value

# Warn about outside assignments
__bu_set_config_warn_outside_assignments "$var"

# Rebuild block body: sorted NAME=value lines
local -a _sorted_keys=()
local _key
for _key in "${!_mb_pairs[@]}"
do
    [[ -n "${_mb_pairs[$_key]}" ]] && _sorted_keys+=("$_key")
done
local _new_body=
if ((${#_sorted_keys[@]} > 0))
then
    local _sorted
    _sorted=$(printf '%s\n' "${_sorted_keys[@]}" | sort)
    while IFS= read -r _key
    do
        _new_body+="${_key}=${_mb_pairs[$_key]}"$'\n'
    done <<<"$_sorted"
fi

__bu_set_config_write_block "$_new_body"

# Take effect immediately in the current shell (this command is sourced).
declare -g "$var=$value"

printf 'Set %s=%s in %s\n' "$var" "$value" "$file"
bu_scope_pop_function
}

__bu_bu_set_config_main "$@"
