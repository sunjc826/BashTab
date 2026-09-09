#!/usr/bin/env bash
# Pipeline: consume
# Requires-All: text
# Dispatch: source
# Synopsis: Write content to the system clipboard
function __bu_bu_set_clipboard_main()
{
# --is-compatible: magic flag checked by the framework at registration time.
# Exit 0 if this command can run on the current system, non-zero otherwise.
# stderr becomes the reason shown in `bu` help.
if [[ "$1" == "--is-compatible" ]]; then
    command -v pbcopy &>/dev/null && exit 0
    command -v wl-copy &>/dev/null && exit 0
    command -v xclip &>/dev/null && exit 0
    command -v xsel &>/dev/null && exit 0
    echo "a clipboard tool is required (pbcopy, wl-copy, xclip, or xsel)" >&2
    exit 1
fi
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local text=
local is_help=false
local is_dry_run=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --text)# TEXT
        # Text to copy to the clipboard (also accepts pipeline input by structural typing)
        bu_parse_positional $# --hint "Clipboard text"
        text=${!shift_by}
        ;;
    --dry-run|--what-if) # _FLAG
        is_dry_run=true
        ;;
    -h|--help)# _FLAG
        # Print help
        is_help=true
        ;;
    *)
        if [[ -z "$text" ]]
        then
            text=$1
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
Write text to the system clipboard (PowerShell Set-Clipboard).
Text comes from the positional argument, or from stdin when no argument
is given (e.g. 'bu get-process --format jsonl | bu set-clipboard').
Uses the first available backend: pbcopy (macOS), wl-copy (Wayland),
xclip, xsel (X11).
" \
        --example "Copy a string" "'hello clipboard'" \
        --example "Copy a pipeline" ""
    return 0
fi

# No argument: take stdin. If the stream is JSONL records, extract .text from each
# one (joined with newlines); otherwise copy raw stdin verbatim.
if [[ -z "$text" ]]
then
    if [[ -t 0 ]]
    then
        error_msg="Missing text to copy (argument or stdin)"
        bu_autohelp
        bu_scope_pop_function
        return 1
    fi
    # Try structural typing: extract .text fields from JSONL records
    local jq_text
    jq_text=$(jq -r '.text // empty' 2>/dev/null)
    if [[ -n "$jq_text" ]]
    then
        text=$jq_text
    else
        text=$(cat)
    fi
fi

if "$is_dry_run"; then
    bu_log_info "Would copy to clipboard: $(echo "$text" | head -c 100)"
    bu_scope_pop_function
    return 0
fi

if command -v pbcopy &>/dev/null
then
    printf '%s' "$text" | pbcopy
elif command -v wl-copy &>/dev/null
then
    printf '%s' "$text" | wl-copy
elif command -v xclip &>/dev/null
then
    printf '%s' "$text" | xclip -selection clipboard -i
elif command -v xsel &>/dev/null
then
    printf '%s' "$text" | xsel --clipboard --input
else
    error_msg="No clipboard tool found (pbcopy, wl-copy, xclip, or xsel)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

bu_scope_pop_function
}

__bu_bu_set_clipboard_main "$@"
