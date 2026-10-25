# !/usr/bin/env bash
# bash-ide parse-func-sig
function __bu_tmux_on_click_main()
{
    local -a filename
    read -r -a filename
    local script_name=$(basename -- "$BASH_SOURCE")
    local script_dir=$(realpath -- "$(dirname -- "$BASH_SOURCE")")
    pushd "$script_dir"
    source ../../bu_entrypoint.sh
    popd &>/dev/null

    {
        echo "Args: $*"
        echo "Cwd: $PWD"
        echo "${filename[@]}"
        if ! command -v code 2>/dev/null
        then
            echo code undefined
            return 1
        fi

        if [[ -e "${filename[0]}" ]]
        then
            printf '%s\n' "${filename[0]} is a file"
        elif [[ -e "${filename[0]%:*}" ]]
        then
            printf '%s\n' "${filename[0]} is probably a file name and line number"
        else
            printf '%s\n' "${filename[0]} does not exist"
        fi

        if ! code --add "${filename[0]}"
        then
            echo code failed
            return 1
        fi
    } &>"$BU_LOG_DIR"/bu_tmux_on_click.log
}

__bu_tmux_on_click_main "$@"
