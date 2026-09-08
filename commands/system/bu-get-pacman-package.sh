#!/usr/bin/env bash
# Pipeline: producer
# Dispatch: source
# Synopsis: List installed Arch Linux packages
# Fields: name version description architecture url licenses groups provides depends_on optional_deps required_by optional_for conflicts replaces installed_size packager build_date install_date
function __bu_bu_get_pacman_package_main()
{
# --is-compatible: magic flag checked by the framework at registration time.
# Exit 0 if this command can run on the current system, non-zero otherwise.
# stderr becomes the reason shown in `bu` help.
if [[ "$1" == "--is-compatible" ]]; then
    command -v pacman &>/dev/null || { echo "pacman is required" >&2; exit 1; }
    command -v jc &>/dev/null    || { echo "jc is required" >&2; exit 1; }
    exit 0
fi

local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local is_help=false
local format=auto
local is_explicit=false
local is_foreign=false
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
    -e|--explicit)# _FLAG
        # Only explicitly installed packages (not pulled as dependencies)
        is_explicit=true
        ;;
    -m|--foreign)# _FLAG
        # Only foreign/AUR packages (not from sync databases)
        is_foreign=true
        ;;
    --search)# PATTERN
        # Search query (searches repos with --remote)
        bu_parse_positional $# --hint "Search term"
        search=${!shift_by}
        ;;
    --remote)# _FLAG
        # Search remote repositories (pacman -Ss) instead of listing installed
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
        --description "List Pacman packages (installed by default, --remote for repository search)." \
        --example "All packages" "" \
        --example "Explicitly installed" "--explicit" \
        --example "AUR/foreign packages" "--foreign" \
        --example "Search repos" "--remote --search nginx"
    return 0
fi

if "$is_remote"; then
    local -a cmd=(pacman -Ss)
    [[ -n "$search" ]] && cmd+=("$search")
    if ((${#remaining_options[@]} > 0)); then cmd+=("${remaining_options[@]}"); fi
    # pacman -Ss output: "repo/name version\n    description"
    "${cmd[@]}" 2>/dev/null | awk '
        /^[^[:space:]]/ {
            if (name) printf "%s\t%s\t%s\t%s\n", name, version, repo, desc
            repo_name = $1; version = $2
            split(repo_name, parts, "/")
            repo = parts[1]; name = parts[2]
            desc = ""
            next
        }
        /^[[:space:]]/ {
            gsub(/^[[:space:]]+/, "")
            desc = desc $0 " "
        }
        END { if (name) printf "%s\t%s\t%s\t%s\n", name, version, repo, desc }
    ' | bu_out_from_tsv --columns name,version,repo,description \
      | bu_out --format "$format"
else
    local -a cmd=(pacman -Qi)
    if "$is_explicit"; then cmd=(pacman -Qei); fi
    if "$is_foreign"; then cmd=(pacman -Qmi); fi
    if ((${#remaining_options[@]} > 0)); then cmd+=("${remaining_options[@]}"); fi
    "${cmd[@]}" 2>/dev/null | jc --pacman 2>/dev/null | jq -c 'if type == "array" then .[] else . end' 2>/dev/null | bu_out --format "$format"
fi

bu_scope_pop_function
}

__bu_bu_get_pacman_package_main "$@"
