case "${BASH_SOURCE}" in
*/*) pushd "${BASH_SOURCE%/*}" &>/dev/null ;; # Enter the current directory
*) pushd . &>/dev/null ;; # This seems like duplicate work but we need to match the popd later
esac

# bash-ide parse-func-sig
__bu_exit_handler_simple()
{
    local exit_code=$?
    set +xv
    local debug=false # Set to true if needed
    local dev
    if "$debug"
    then
        dev=/dev/tty
    else
        dev=/dev/stdout
    fi
    if "$debug" || [[ $- =~ e && "$exit_code" != 0 ]]
    then
        set +e
        {
        echo
        echo "Script exited with code: $exit_code"
        echo "Traceback (most recent call last):"
        local i
        for i in "${!BASH_LINENO[@]}"
        do
            if (( i == 0 ))
            then
                printf "    %s: %s at %s:%s\n" \
                    "$i" \
                    "$BU_ERR_COMMAND" \
                    "$(basename -- "${BASH_SOURCE[i+1]}")" "$BU_ERR_LINENO"
            else
                printf "    %s: %s at %s:%s%s\n" \
                    "$i" \
                    "${FUNCNAME[i+1]}" \
                    "$(basename -- "${BASH_SOURCE[i+1]}")" "${BASH_LINENO[i]}"
            fi
        done
        } >"$dev"
    fi

    set +e

    if "$debug"
    then
        sleep 120
    fi
    return "$exit_code"
}

trap 'BU_ERR_LINENO=$LINENO; BU_ERR_COMMAND=$BASH_COMMAND' ERR
trap __bu_exit_handler_simple EXIT

set -e
source ./bu_entrypoint.sh

# Get access to the bats binary
bu_env_append_path "$BU_DIR"/test/bats/bin

# Run .bats tests
bu_env_append_path "$BU_DIR"/test

set +e
popd &>/dev/null
