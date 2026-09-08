#!/usr/bin/env bash
# Pipeline: producer
# Dispatch: source
# Synopsis: List installed Alpine Linux packages
# Fields: name version
function __bu_bu_get_apk_package_main()
{
# --is-compatible: magic flag checked by the framework at registration time.
# Exit 0 if this command can run on the current system, non-zero otherwise.
# stderr becomes the reason shown in `bu` help.
if [[ "$1" == "--is-compatible" ]]; then
    command -v apk &>/dev/null || { echo "apk is required" >&2; exit 1; }
    exit 0
fi

local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local is_help=false
local format=auto
local search=
local is_remote=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --format)# FORMAT
        # Output format
        bu_parse_positional $# --enum ${BU_OUT_FORMATS[@]} enum-- --hint "Output format"
        format=${!shift_by}
        ;;
    --search)# PATTERN
        # Filter packages by name glob pattern
        bu_parse_positional $# --hint "Package name pattern"
        search=${!shift_by}
        ;;
    --remote)# _FLAG
        # Search remote repositories instead of listing installed packages
        is_remote=true
        ;;
    -h|--help)# _FLAG
        is_help=true
        ;;
    --)
        shift
        break
        ;;
    *)
        break
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
local remaining_options=("$@")
if bu_env_is_in_autocomplete
then
    bu_autocomplete
    return 0
fi

if "$is_help"
then
    bu_autohelp \
        --description "List APK packages (installed by default, --remote for repository search).

Wraps apk info -v for installed, apk search for remote.  Each line
(name-version or name-description) is split into name and version fields." \
        --example "Installed packages" "" \
        --example "Filter by name" "--search 'bash*'" \
        --example "Search repos" "--remote --search nginx"
    return 0
fi

if "$is_remote"; then
    # Remote repository search: apk search outputs "name-version description"
    local -a apk_args=(search)
    [[ -n "$search" ]] && apk_args+=("$search")
    if ((${#remaining_options[@]} > 0)); then apk_args+=("${remaining_options[@]}"); fi
    {
        apk "${apk_args[@]}" 2>/dev/null | while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local name version description
            name="${line%%-*}"
            local rest="${line#*-}"
            # Try to extract version: digits followed by something before space
            if [[ "$rest" =~ ^([0-9][^[:space:]]*)[[:space:]](.*) ]]; then
                version="${BASH_REMATCH[1]}"
                description="${BASH_REMATCH[2]}"
            else
                version=
                description="$rest"
            fi
            printf '%s\t%s\t%s\n' "$name" "$version" "$description"
        done
    } | bu_out_from_tsv --columns name,version,description \
      | bu_out --format "$format"
else

# apk info -v outputs "name-version" per line.
# Split into name and version: version is everything after the first
# dash that's followed by a digit (e.g. "busybox-1.36.1-r29").
local -a apk_args=(info -v)
[[ -n "$search" ]] && apk_args+=("$search")
if ((${#remaining_options[@]} > 0)); then apk_args+=("${remaining_options[@]}"); fi
{
    apk "${apk_args[@]}" 2>/dev/null | while IFS= read -r line; do
        local name version
        name=$(echo "$line" | sed -E 's/-[0-9].*$//')
        version=${line#"$name-"}
        printf '%s\t%s\n' "$name" "$version"
    done
} | bu_out_from_tsv --columns name,version \
  | bu_out --format "$format"
fi

bu_scope_pop_function
}

__bu_bu_get_apk_package_main "$@"
