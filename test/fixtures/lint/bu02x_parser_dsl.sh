f() {
while (($#)); do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --dropped)# VALUE
        bu_parse_positional $# --hint "never read"
        ;;
    --dup|--dup)# _FLAG
        is_dup=true
        ;;
    --bad-target)# _FLAG
        bu_parse_positional $# --as-if no-such-command as-if--
        value=${!shift_by}
        ;;
    esac
    shift "$shift_by"
done
}
