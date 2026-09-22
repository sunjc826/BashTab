# expect: unfixed
# `|`-alternative starting with a single dash, `)` immediately followed by a
# comment. The external scanner requires whitespace after `)` to close a case
# pattern. A scanner fix is possible but was not attempted: see patches.js on
# why this fork stays out of scanner.c.
case "$1" in
--foreground|-f)# _FLAG
    is_fg=true
    ;;
esac
