#!/usr/bin/env bash
# Pipeline: producer
# Dispatch: source
# Synopsis: List installed RPM packages
# Fields: name version release arch summary
function __bu_bu_get_rpm_package_main()
{
# --is-compatible: magic flag checked by the framework at registration time.
# Exit 0 if this command can run on the current system, non-zero otherwise.
# stderr becomes the reason shown in `bu` help.
if [[ "$1" == "--is-compatible" ]]; then
    command -v rpm &>/dev/null || { echo "rpm is required" >&2; exit 1; }
    exit 0
fi

local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local is_help=false
local format=auto
local name=
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
    --name)# PATTERN
        # Filter packages by name glob pattern (e.g. 'kernel*')
        bu_parse_positional $# --hint "Package name glob"
        name=${!shift_by}
        ;;
    --search)# PATTERN
        # Search query (searches repos with --remote)
        bu_parse_positional $# --hint "Search term"
        search=${!shift_by}
        ;;
    --remote)# _FLAG
        # Search remote repositories (dnf search) instead of listing installed
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
        --description "List RPM packages (installed by default, --remote for dnf search)." \
        --example "All packages" "" \
        --example "Filter by name" "--name 'kernel*'" \
        --example "Search repos" "--remote --search nginx"
    return 0
fi

if "$is_remote"; then
    local dnf_cmd
    dnf_cmd=$(command -v dnf 2>/dev/null || command -v yum 2>/dev/null || echo "dnf")
    local -a cmd=("$dnf_cmd" search)
    [[ -n "$search" ]] && cmd+=("$search")
    if ((${#remaining_options[@]} > 0)); then cmd+=("${remaining_options[@]}"); fi
    # dnf search output: "name.arch  summary" or "name  :  summary"
    "${cmd[@]}" 2>/dev/null | awk -F' : |  ' '{
        name = $1; sub(/\.[^.]+$/, "", name)
        summary = $2
        if (name) printf "%s\t%s\n", name, summary
    }' | bu_out_from_tsv --columns name,summary \
      | bu_out --format "$format"
else

local -a rpm_args=(-qa --queryformat '%{NAME}\t%{VERSION}\t%{RELEASE}\t%{ARCH}\t%{SUMMARY}\n')
[[ -n "$name" ]] && rpm_args+=("$name")
if ((${#remaining_options[@]} > 0)); then rpm_args+=("${remaining_options[@]}"); fi
{
    rpm "${rpm_args[@]}" 2>/dev/null
} | bu_out_from_tsv --columns name,version,release,arch,summary \
  | bu_out --format "$format"
fi

bu_scope_pop_function
}

__bu_bu_get_rpm_package_main "$@"
