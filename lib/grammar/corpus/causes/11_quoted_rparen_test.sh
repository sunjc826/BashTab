# expect: unfixed
# A single-quoted `)` as the right operand of `=` inside [[ ]]. The grammar
# parses that operand as a regex, and the regex token wins at lexer level, so
# allowing raw_string there in grammar.js alone does not fix it.
if [[ "${token_stack[-1]}" = ')' ]]; then :; fi
