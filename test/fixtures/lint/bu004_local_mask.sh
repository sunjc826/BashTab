f() {
    local x=$(some_command)
    if (( $? != 0 )); then echo bad; fi

    local y=$(other_command)
    eval "$y"
    code=$?
}
