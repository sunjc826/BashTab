#!/usr/bin/env bash
# Sourced only by the demo recorder's fresh Bash shell.
# Discard exported state from an embedding project (e.g. another module's CLI).
for bu_demo_variable in "${!BU_@}"; do
    unset "$bu_demo_variable"
done
unset bu_demo_variable

export BU_OUT_DIR=${BASHTAB_DEMO_OUT_DIR:?Run docs/render_demos.sh}
export BU_COMMAND_CACHE_ENABLED=false
# Short tables remain on screen; long tables still demonstrate the pager.
export BU_TABLE_PAGER=preset:less-quit
export LESSCHARSET=utf-8
export HISTFILE=/dev/null

if [[ ${BASHTAB_DEMO_MODULE:-} == devbox ]]; then
    source ./activate --example devbox >"$BU_OUT_DIR/activation.log" 2>&1 || return 1
else
    source ./activate >"$BU_OUT_DIR/activation.log" 2>&1 || return 1
fi
type bu >/dev/null || return 1

if [[ ${BASHTAB_DEMO_TRANSFORMS:-false} == true ]]; then
    bu_preinit_register_line_transform wrap-timeout \
        --match '{line}' --replace 'timeout 30s {line}' \
        --description 'Give the command a 30-second time limit'
    # The selector is opt-in, not a default BashTab binding.
    bind -x '"\et":__bu_bind_transform_selector'
fi

PROMPT_COMMAND=
PS1='$ '
clear
return 0
