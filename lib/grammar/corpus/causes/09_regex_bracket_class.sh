# expect: unfixed
# `]` as the first character of a negated bracket class inside =~.
if [[ "$cur_word" =~ ^(\$\{[#!]?)([A-Za-z0-9_]*)\[([^]]*)$ ]]; then :; fi
