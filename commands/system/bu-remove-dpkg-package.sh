#!/usr/bin/env bash
# Pipeline: transform
# Requires-All: name
# Fields: name action dry_run
# Dispatch: source
# Synopsis: Uninstall Debian packages
function __bu_bu_remove_dpkg_package_main()
{
if [[ "$1" == "--is-compatible" ]]; then
    command -v apt-get &>/dev/null || { echo "apt-get is required" >&2; exit 1; }
    exit 0
fi
local -r invocation_dir=$PWD
source "$BU_NULL"
bu_scope_push_function
bu_run_log_command "$@"

local -a names=()
local is_yes=false
local is_purge=false
local is_dry_run=false
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#)); do
    bu_parse_multiselect $# "$1"
    case "$1" in
    -y|--yes) # _FLAG
        is_yes=true
        ;;
    --purge) # _FLAG
        is_purge=true
        ;;
    --dry-run|--what-if) # _FLAG
        is_dry_run=true
        ;;
    -h|--help) # _FLAG
        is_help=true
        ;;
    *)
        names+=("$1")
        ;;
    esac
    if "$is_help"; then break; fi
    if (( $# < shift_by )); then bu_parse_error_argn "$1" $#; break; fi
    shift "$shift_by"
done
if bu_env_is_in_autocomplete; then bu_autocomplete; return 0; fi
if "$is_help"; then
    bu_autohelp --description "Uninstall Debian/Ubuntu packages (apt-get remove/purge)." \
        --example "Remove" "nginx vim" --example "Purge configs" "--purge nginx" --example "Dry run" "--dry-run nginx"
    return 0
fi
if ((${#names[@]} == 0)) && read -t 0 2>/dev/null; then
    local line; while IFS= read -r line; do
        local n; n=$(jq -r '.name // empty' <<<"$line" 2>/dev/null) || true
        [[ -n "$n" ]] && names+=("$n")
    done < <(__bu_out_strict_guard "remove-dpkg-package")
fi
if ((${#names[@]} == 0)); then error_msg="No packages specified."; bu_autohelp; bu_scope_pop_function; return 1; fi

local verb=remove; local action=remove
"$is_purge" && { verb=purge; action=purge; }

if "$is_dry_run"; then
    for n in "${names[@]}"; do bu_out_record name="$n" action="would-${action}" dry_run:=true | bu_out --format jsonl; done
else
    local -a cmd=(apt-get "$verb"); "$is_yes" && cmd+=(-y)
    "${cmd[@]}" "${names[@]}" 2>/dev/null || { error_msg="apt-get $verb failed (try with sudo?)"; bu_autohelp; bu_scope_pop_function; return 1; }
    for n in "${names[@]}"; do bu_out_record name="$n" action="$action" | bu_out --format jsonl; done
fi
bu_scope_pop_function
}
__bu_bu_remove_dpkg_package_main "$@"
