exec 3>"$out"
exec 4<"$in"
exec 3>&-
cmd >file 2>&1
cmd &>/dev/null
x=${a[0]}
y=${a[i+1]}
z=${a[${#a[@]}-1]}
((count++))
: $((count++))
if ((count > 0)); then :; fi
