#!/usr/bin/env bash
# Pipeline: producer
# Dispatch: source
# Synopsis: List installed Debian packages
# Fields: codes name version architecture description desired status
function __bu_bu_get_dpkg_package_main()
{
# --is-compatible: magic flag checked by the framework at registration time.
# Exit 0 if this command can run on the current system, non-zero otherwise.
# stderr becomes the reason shown in `bu` help.
if [[ "$1" == "--is-compatible" ]]; then
    command -v dpkg &>/dev/null || { echo "dpkg is required" >&2; exit 1; }
    command -v jc &>/dev/null   || { echo "jc is required" >&2; exit 1; }
    if [[ -f /etc/os-release ]]; then
        local _id _id_like
        _id=$(grep -oP '^ID=\K.*' /etc/os-release | tr -d '"')
        _id_like=$(grep -oP '^ID_LIKE=\K.*' /etc/os-release | tr -d '"')
        case " $_id $_id_like " in
            *" debian "*|*" ubuntu "*) : ;;
            *) echo "requires Debian-based system" >&2; exit 1 ;;
        esac
    fi
    exit 0
fi

local -r invocation_dir=$PWD

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
        # Search query (searches remote repos with --remote, filters installed otherwise)
        bu_parse_positional $# --hint "Search term"
        search=${!shift_by}
        ;;
    --remote)# _FLAG
        # Search remote repositories (apt-cache search) instead of listing installed
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
        # Any unrecognized arg: pass through to the underlying command, replacing the default
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
        --description "List Debian packages (installed by default, --remote for apt-cache search)." \
        --example "Installed packages" "" \
        --example "Search repos" "--remote --search nginx" \
        --example "With extra flags" "-- -la /var/log"
    return 0
fi

if "$is_remote"; then
    # Remote search via apt-cache: name - description
    local -a apt_args=(apt-cache search)
    [[ -n "$search" ]] && apt_args+=("$search")
    if ((${#remaining_options[@]} > 0)); then apt_args+=("${remaining_options[@]}"); fi
    {
        "${apt_args[@]}" 2>/dev/null | while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local name="${line%% -*}"
            local description="${line#* - }"
            printf '%s\t%s\n' "$name" "$description"
        done
    } | bu_out_from_tsv --columns name,description \
      | bu_out --format "$format"
else
    if ! command -v jc &>/dev/null; then
        error_msg="jc is required. Install with: pip install jc"
        bu_autohelp
        bu_scope_pop_function
        return 1
    fi
    local -a cmd=()
    if [[ -n "$search" ]] || ((${#remaining_options[@]} > 0)); then
        cmd=(dpkg -l)
        [[ -n "$search" ]] && cmd+=("$search")
        ((${#remaining_options[@]} > 0)) && cmd+=("${remaining_options[@]}")
    else
        cmd=(dpkg -l)
    fi
    "${cmd[@]}" 2>/dev/null | jc --dpkg-l 2>/dev/null | jq -c 'if type == "array" then .[] else . end' 2>/dev/null | bu_out --format "$format"
fi

bu_scope_pop_function
}

__bu_bu_get_dpkg_package_main "$@"
