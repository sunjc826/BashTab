# expect: unfixed
# Concatenated quoted globs in a case pattern. A single *"A"* parses.
case "$desc" in
*"Unicode text"*|*"UTF-8"*"text"*) echo text ;;
esac
