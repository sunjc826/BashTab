# The loop a patch to _c_expression_not_assignment silently broke. Keep it.
for ((i=0; i<3; i++)); do :; done
for ((i=0; i < ${#items[@]}; i++)); do echo "${items[i]}"; done
for ((;;)); do break; done
for item in "${items[@]}"; do :; done
while (($#)); do shift; done
