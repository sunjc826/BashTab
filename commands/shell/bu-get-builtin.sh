#!/usr/bin/env bash
# Pipeline: producer
# Dispatch: source
# Synopsis: List or filter bash builtin commands
function __bu_bu_get_builtin_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local filter=
local format=auto
local is_help=false
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
    -h|--help)# _FLAG
        # Print help
        is_help=true
        ;;
    *)
        if [[ -z "$filter" ]]
        then
            filter=$1
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
List bash builtins with enabled status and override detection (structured enable -a).
Each record: name, enabled (boolean), overridden (boolean), override_type
(\"alias\" or \"function\", null if not overridden).

Builtins can be shadowed by aliases (first in lookup order), then by
functions, and also explicitly disabled via 'enable -n' (shown as
enabled=false). See also bu get-command for BashTab commands,
bu get-alias for the CLI's registered aliases, and bu get-shell-alias
for bash shell aliases.
" \
        --example "All builtins" "" \
        --example "One builtin" "printf" \
        --example "Find overridden builtins" "| bu where '.overridden'"
    return 0
fi

# Collect names that shadow builtins: function names and alias names.
# We produce two space-separated lists for jq to check against.
local override_functions override_aliases
override_functions=$(compgen -A function 2>/dev/null | paste -sd ' ' -)
override_aliases=$(alias 2>/dev/null | sed -n "s/^alias \([^=]*\)=.*/\1/p" | paste -sd ' ' -)

# enable -a prints 'enable NAME' or 'enable -n NAME' (disabled)
enable -a | jq -R -c \
    --arg filter "$filter" \
    --arg fns "$override_functions" \
    --arg als "$override_aliases" \
'
    select(. != "")
    | if startswith("enable -n ")
      then {name: .[10:], enabled: false}
      else sub("^enable "; "") | {name: ., enabled: true}
      end
    | . as $r
    | ($als | split(" ") | index($r.name)) as $aliasIdx
    | ($fns | split(" ") | index($r.name)) as $funcIdx
    | if $aliasIdx != null then
        $r + {overridden: true, override_type: "alias"}
      elif $funcIdx != null then
        $r + {overridden: true, override_type: "function"}
      else
        $r + {overridden: false, override_type: null}
      end
    | select($filter == "" or (.name | test($filter)))
' | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_get_builtin_main "$@"
