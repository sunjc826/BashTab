# expect: unfixed
# Substring with a variable offset and NO length. `${L:0:$P}` parses; this does
# not. Produces a MISSING node rather than an ERROR node.
f "${READLINE_LINE:$READLINE_POINT}"
