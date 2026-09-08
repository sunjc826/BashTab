#!/usr/bin/env bash
# Pipeline: producer
# Dispatch: source
# Synopsis: List installed npm packages with metadata
# Fields: name version resolved depth _path _parent_path
function __bu_bu_get_npm_package_main()
{
# --is-compatible: magic flag checked by the framework at registration time.
# Exit 0 if this command can run on the current system, non-zero otherwise.
# stderr becomes the reason shown in `bu` help.
if [[ "$1" == "--is-compatible" ]]; then
    command -v npm &>/dev/null || { echo "npm is required" >&2; exit 1; }
    exit 0
fi
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local project_path=.
local is_help=false
local format=auto
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
    --cwd)# CWD
        # Project directory (default: current directory)
        bu_parse_positional $# --hint "Project directory path"
        project_path=${!shift_by}
        ;;
    *)
        bu_parse_error_enum "$1"
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
        --description "
List npm packages in a project as flat JSONL records (npm ls --json wrapper).
Emits one record per package in the dependency tree, with depth and parent
path tracking. The root project is at depth 0.

Fields: name, version, resolved, depth, _path, _parent_path
" \
        --example "Current project" "" \
        --example "Specific directory" "--cwd /path/to/project" \
        --example "Filter top-level deps only" "| bu where '.depth == 1'" \
        --example "Find packages in a subtree" "| bu where '._path | startswith(\"debug\")'"
    return 0
fi

if ! command -v npm &>/dev/null
then
    error_msg="npm is required. Install Node.js from https://nodejs.org"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

# Run npm ls --all --json from the project directory, flatten the tree to JSONL.
# --all shows the logical dependency tree (including transitive deps nested
# under their parents). npm may exit non-zero with warnings about extraneous
# or missing optional/peer dependencies; we capture stdout and ignore exit code.
local npm_output
npm_output=$(cd "$project_path" && npm ls --all --json 2>/dev/null) || true

if [[ -z "$npm_output" || "$npm_output" == "{}" || "$npm_output" == "[]" ]]
then
    bu_scope_pop_function
    return 0
fi

# Flatten the recursive dependency tree into flat records.
# def walk: recursively descends into .dependencies, emitting one record per node.
# Each record carries name, version, resolved, depth, _path, _parent_path.
jq -c '
    def walk($depth; $parent_path; $path):
        . as $node
        | {
            name,
            version,
            resolved: (.resolved // null),
            depth: $depth,
            _path: $path,
            _parent_path: $parent_path
        }
        | .,
          (if $node.dependencies
           then ($node.dependencies | to_entries[] | .key as $k | .value * {name: $k} | select(.missing != true and .extraneous != true) | walk($depth + 1; $path; (if $path == "" then $k else "\($path)/\($k)" end)))
           else empty
           end);
    walk(0; null; .name // "")
' <<<"$npm_output" 2>/dev/null | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_get_npm_package_main "$@"
