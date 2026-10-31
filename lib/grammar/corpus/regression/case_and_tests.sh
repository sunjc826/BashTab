case "$1" in
-h|--help) : ;;
--format) : ;;
*"literal"*) : ;;
*) : ;;
esac
if [[ "$x" == pattern* ]]; then :; fi
if [[ "$x" =~ ^[a-z]+$ ]]; then :; fi
if [[ -n "$x" && -z "$y" ]]; then :; fi
