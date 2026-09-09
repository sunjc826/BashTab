#!/usr/bin/env bash
# Pipeline: standalone
# Dispatch: source
# Synopsis: Add or remove a persistent named location
# Help-Topic: locations
function __bu_bu_new_location_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local file=${BU_LOCATION_LOCAL_FILE:-"$BU_DIR"/config/bu_locations_local.sh}

# Managed block markers (same structural contract as `bu set-config`).
local -r __BU_NEW_LOCATION_OPENER='# >>> bu new-location managed block -- do not hand-edit inside'
local -r __BU_NEW_LOCATION_CLOSER='# <<< bu new-location managed block'

local name=
local path_expr=
local kind=dir
local kind_explicit=false
local -a aliases=()
local description=
local tags=
local on_enter=
local is_repo=false
local gh_host=
local gh_slug=
local is_remove=false
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --path)# PATH
        # Path expression (single-quote it: '$MY_PROJECT_DIR/build')
        bu_parse_positional $# --hint "Path expression (single-quoted, lazy \$-vars ok)"
        path_expr=${!shift_by}
        ;;
    --kind)# KIND
        # Location kind (dir default, file, multi)
        bu_parse_positional $# --enum dir file multi enum-- --hint "Location kind"
        kind=${!shift_by}
        kind_explicit=true
        ;;
    --alias)# ALIAS
        # Short alias for the location (repeatable)
        bu_parse_positional $# --hint "Alias name"
        aliases+=("${!shift_by}")
        ;;
    --description)# DESCRIPTION
        # Human-readable description
        bu_parse_positional $# --hint "Description"
        description=${!shift_by}
        ;;
    --tags)# TAGS
        # Comma-separated tags
        bu_parse_positional $# --hint "Comma-separated tags"
        tags=${!shift_by}
        ;;
    --on-enter)# ON_ENTER
        # Function name run after cd (dir kind only)
        bu_parse_positional $# --hint "on-enter function name"
        on_enter=${!shift_by}
        ;;
    --repo)# _FLAG
        # Register as a repo (bu_repo_register line instead)
        is_repo=true
        ;;
    --gh-host)# GH_HOST
        # GitHub host (with --repo)
        bu_parse_positional $# --hint "GitHub host (e.g. github.com)"
        gh_host=${!shift_by}
        ;;
    --gh-slug)# GH_SLUG
        # GitHub OWNER/REPO slug (with --repo)
        bu_parse_positional $# --hint "OWNER/REPO"
        gh_slug=${!shift_by}
        ;;
    --remove|--rm)# _FLAG
        # Remove the named location from the local file and the registry
        is_remove=true
        ;;
    -h|--help)# _FLAG
        # Print help
        is_help=true
        ;;
    *)
        if bu_env_is_in_autocomplete && [[ "$1" != -* ]]
        then
            autocompletion=(--stdout bu_location_names --with-aliases stdout-- --hint "Location name")
        fi
        if [[ -z "$name" ]]
        then
            name=$1
        else
            bu_parse_error_enum "$1"
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
    bu_autohelp \
        --description "
Add or remove a persistent named location. Writes a registration line into a
managed block in $file and applies it to the current shell immediately.
Path expressions are stored unexpanded — single-quote them so lazy \$VAR
references survive re-sourcing (e.g. --path '\$MY_PROJECT_DIR/build').
Resolver-based entries belong in code, not this file: --path is required.
" \
        --example "Add a directory shortcut" "myproj --path '\$HOME/src/myproj' --alias mp --tags work" \
        --example "Add a repo" "myrepo --path '\$HOME/src/myrepo' --repo --gh-slug owner/repo" \
        --example "Remove a shortcut" "--remove myproj"
    return 0
fi

# ── Validation (before touching the file or the registry) ──
if [[ -z "$name" ]]
then
    error_msg="Missing location name (bu new-location NAME --path 'EXPR' | --remove NAME)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

if "$is_remove"
then
    :
elif "$is_repo" && "$kind_explicit" && [[ "$kind" != dir ]]
then
    error_msg="--kind is not allowed with --repo (repos are always dir)"
    bu_autohelp
    bu_scope_pop_function
    return 1
elif [[ -z "$path_expr" ]]
then
    error_msg="--path is required (single-quote the expression, e.g. --path '\$HOME/myproj')"
    bu_autohelp
    bu_scope_pop_function
    return 1
elif ! __bu_location_validate_path_expr "$path_expr"
then
    error_msg="--path contains forbidden characters (\$(, backtick, ;, &, |, <, >, newline): $path_expr"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

# ── Managed block helpers ──────────────────────────────────
local _mb_before _mb_inside _mb_after _mb_ok _mb_oc _mb_cc
local -A _lines=()

__bu_new_location_parse_block()
{
    local content=
    [[ -f "$file" ]] && content=$(cat "$file")
    _mb_before=
    _mb_inside=
    _mb_after=
    _mb_ok=true

    local oc cc
    oc=$(grep -cF "$__BU_NEW_LOCATION_OPENER" <<<"$content" || true)
    cc=$(grep -cF "$__BU_NEW_LOCATION_CLOSER" <<<"$content" || true)

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

    local ol cl
    ol=$(grep -nF "$__BU_NEW_LOCATION_OPENER" <<<"$content" | head -1 | cut -d: -f1)
    cl=$(grep -nF "$__BU_NEW_LOCATION_CLOSER" <<<"$content" | head -1 | cut -d: -f1)
    if (( cl <= ol ))
    then
        _mb_ok=false
        return 0
    fi

    local total_lines
    total_lines=$(wc -l <<<"$content")

    if (( ol > 1 ))
    then
        _mb_before=$(head -n $((ol - 1)) <<<"$content")
        [[ "$_mb_before" != *$'\n' ]] && _mb_before+=$'\n'
    fi
    if (( cl > ol + 1 ))
    then
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

__bu_new_location_read_lines()
{
    local inside=$1
    _lines=()
    local line name rest
    while IFS= read -r line
    do
        [[ -z "$line" ]] && continue
        [[ "$line" == '#'* ]] && continue
        line=${line#"${line%%[![:space:]]*}"}
        rest=${line#* }
        name=${rest%%[[:space:]]*}
        [[ -n "$name" ]] && _lines[$name]=$line
    done <<<"$inside"
}

__bu_new_location_write_block()
{
    mkdir -p "${file%/*}"
    local tmpfile
    tmpfile=$(mktemp "$file.XXXXXX")
    {
        if [[ -n "$_mb_before" ]]
        then
            printf '%s' "$_mb_before"
            [[ "$_mb_before" != *$'\n' ]] && printf '\n'
        fi
        printf '%s\n' "$__BU_NEW_LOCATION_OPENER"
        local sorted
        sorted=$(printf '%s\n' "${!_lines[@]}" | sort)
        local n
        while IFS= read -r n
        do
            [[ -n "$n" ]] && printf '%s\n' "${_lines[$n]}"
        done <<<"$sorted"
        printf '%s\n' "$__BU_NEW_LOCATION_CLOSER"
        if [[ -n "$_mb_after" ]]
        then
            printf '%s' "$_mb_after"
            [[ "$_mb_after" != *$'\n' ]] && printf '\n'
        fi
    } > "$tmpfile"
    mv "$tmpfile" "$file"
}

# ── Main file operation ─────────────────────────────────────
__bu_new_location_parse_block
if ! "$_mb_ok"
then
    bu_log_err "Managed block markers in $file are inconsistent (expected 0 or 1 opener+closer pair, found ${_mb_oc:-0} opener(s) and ${_mb_cc:-0} closer(s))."
    bu_log_err "Please hand-edit the file to fix or remove the markers, then retry."
    bu_scope_pop_function
    return 1
fi
__bu_new_location_read_lines "$_mb_inside"

local enc_name
printf -v enc_name '%q' "$name"

if "$is_remove"
then
    if [[ -z "${_lines[$enc_name]:-}" ]]
    then
        bu_log_warn "location[$name] has no managed line in $file"
    else
        unset "_lines[$enc_name]"
    fi
    __bu_new_location_write_block
    bu_location_unregister "$name" 2>/dev/null || true
    printf 'Removed %s from %s\n' "$name" "$file"
    bu_scope_pop_function
    return 0
fi

# Build the registration line (%q-quote values so lazy $VAR survives re-source).
local line
local q_name q_kind q_path
printf -v q_name '%q' "$name"
printf -v q_path '%q' "$path_expr"
if "$is_repo"
then
    line="bu_repo_register $q_name --path $q_path"
    if [[ -n "$gh_host" ]]; then printf -v q '%q' "$gh_host"; line+=" --gh-host $q"; fi
    if [[ -n "$gh_slug" ]]; then printf -v q '%q' "$gh_slug"; line+=" --gh-slug $q"; fi
else
    printf -v q_kind '%q' "$kind"
    line="bu_location_register $q_name --kind $q_kind --path $q_path"
fi

local a q
for a in "${aliases[@]}"
do
    printf -v q '%q' "$a"
    line+=" --alias $q"
done
if [[ -n "$description" ]]; then printf -v q '%q' "$description"; line+=" --description $q"; fi
if [[ -n "$tags" ]]; then printf -v q '%q' "$tags"; line+=" --tags $q"; fi
if [[ -n "$on_enter" ]]; then printf -v q '%q' "$on_enter"; line+=" --on-enter $q"; fi

_lines[$enc_name]=$line
__bu_new_location_write_block

# Apply immediately in the current shell (this command is sourced).
local -a reg_args=()
if "$is_repo"
then
    reg_args=(--path "$path_expr")
    [[ -n "$gh_host" ]] && reg_args+=(--gh-host "$gh_host")
    [[ -n "$gh_slug" ]] && reg_args+=(--gh-slug "$gh_slug")
else
    reg_args=(--kind "$kind" --path "$path_expr")
fi
for a in "${aliases[@]}"
do
    reg_args+=(--alias "$a")
done
[[ -n "$description" ]] && reg_args+=(--description "$description")
[[ -n "$tags" ]] && reg_args+=(--tags "$tags")
[[ -n "$on_enter" ]] && reg_args+=(--on-enter "$on_enter")

if "$is_repo"
then
    bu_repo_register "$name" "${reg_args[@]}" || {
        bu_log_err "Failed to apply repo registration (file was already updated)"
        bu_scope_pop_function
        return 1
    }
else
    bu_location_register "$name" "${reg_args[@]}" || {
        bu_log_err "Failed to apply location registration (file was already updated)"
        bu_scope_pop_function
        return 1
    }
fi

printf 'Added %s to %s\n' "$name" "$file"
bu_scope_pop_function
}

__bu_bu_new_location_main "$@"
