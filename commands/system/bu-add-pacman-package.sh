#!/usr/bin/env bash
# Pipeline: consume
# Requires-All: name
# Dispatch: source
# Synopsis: Install one or more Arch Linux packages
function __bu_bu_add_pacman_package_main()
{
if [[ "$1" == "--is-compatible" ]]; then
    command -v pacman &>/dev/null || { echo "pacman is required" >&2; exit 1; }
    exit 0
fi
local -r invocation_dir=$PWD
source "$BU_NULL"
bu_scope_push_function
bu_run_log_command "$@"

local -a names=()
local is_yes=false
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
    bu_autohelp --description "Install packages (pacman -S).  Accepts names as positional args or piped .name records."         --example "Install" "nginx vim" --example "Dry run" "--dry-run nginx"
    return 0
fi
if ((${#names[@]} == 0)) && read -t 0 2>/dev/null; then
    local line; while IFS= read -r line; do
        local n; n=$(jq -r '.name // empty' <<<"$line" 2>/dev/null) || true
        [[ -n "$n" ]] && names+=("$n")
    done
fi
if ((${#names[@]} == 0)); then error_msg="No packages specified."; bu_autohelp; bu_scope_pop_function; return 1; fi
if "$is_dry_run"; then
    for n in "${names[@]}"; do bu_out_record name="$n" action="would-install" dry_run:=true | bu_out --format jsonl; done
else
    local -a cmd=(pacman -S); "$is_yes" && cmd+=(-y)
    "${cmd[@]}" "${names[@]}" 2>/dev/null || { error_msg="pacman -S failed (try with sudo?)"; bu_autohelp; bu_scope_pop_function; return 1; }
    for n in "${names[@]}"; do bu_out_record name="$n" action="installed" | bu_out --format jsonl; done
fi
bu_scope_pop_function
}
__bu_bu_add_pacman_package_main "$@"
