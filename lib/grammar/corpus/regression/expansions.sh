a=${b:-default}
c=${d:+alt}
e=${f:0:5}
g=${h:0:$n}
i=${j#prefix}
k=${l%%suffix}
m=${#n}
o=${p//search/replace}
q=${arr[-1]}
r=${arr[@]}
s="$((x + y))"
t="$(( 10#${month} ))"
declare -A map=([key]=value)
u=${map[key]}
