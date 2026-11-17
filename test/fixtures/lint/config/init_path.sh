# Init-path file: config/*.sh is sourced while a user's shell starts.
bu_config_register SOMETHING --default x
bu_config_register OTHER --default y || true
return 1
f() {
    return 1
}
