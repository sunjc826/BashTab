#!/usr/bin/env bash
# tree-sitter-bash 0.25.1 cannot parse `--a|-b)#comment` (valid bash).
f() {
case "$1" in
--foreground|-f)# _FLAG
    is_fg=true
    ;;
esac
}
