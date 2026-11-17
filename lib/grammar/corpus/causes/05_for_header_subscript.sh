# expect: unfixed
# Array subscript in a C-style for header. The header uses a separate, smaller
# expression grammar (_c_expression_not_assignment). Adding $.subscript there
# BROKE plain `for ((i=0; i<3; i++))` — see corpus/regression/for_loops.sh.
for ((i=op_idx_stack[-1]+1; i < ${#token_stack[@]}; i++)); do :; done
