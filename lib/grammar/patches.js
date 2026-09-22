"use strict";

/**
 * BashTab's patch set for tree-sitter-bash.
 *
 * Each patch is an exact string replacement against upstream `grammar.js`,
 * with an assertion on the anchor: if upstream changes the code we patch, the
 * build fails loudly instead of silently producing an unpatched parser.
 *
 * Rules for adding a patch here:
 *
 *   1. It must fix a construct that is VALID BASH (`bash -n` accepts it) and
 *      that tree-sitter-bash rejects. Add the repro to corpus/causes/.
 *   2. It must not regress anything: `node lib/grammar/test.js` parses every
 *      shell script in this repo with both parsers and fails on any file the
 *      fork breaks that upstream handled. This is not optional — an earlier
 *      one-line patch adding `$.subscript` to the C-style for() expression
 *      language silently broke `for ((i=0; i<3; i++))`, the most common loop
 *      in the language, and only the sweep caught it.
 *   3. Prefer grammar.js over src/scanner.c. Nothing here touches the external
 *      scanner: keeping scanner.c byte-identical to upstream makes rebasing a
 *      grammar.js-only exercise.
 */

module.exports = [
    {
        id: "rw-redirect",
        cause: "10_rw_redirect",
        summary: "`exec 3<>file` — the <> read-write redirect operator is missing",
        detail:
            "file_redirect lists every other operator ('<', '>', '>>', '&>', '&>>',\n" +
            "'<&', '>&', '>|') but not '<>'. Affects any read-write redirect, with a\n" +
            "numeric or a {varname} descriptor alike.",
        find: "choice('<', '>', '>>', '&>', '&>>', '<&', '>&', '>|'),",
        replace: "choice('<', '>', '>>', '&>', '&>>', '<&', '>&', '>|', '<>'),",
    },
    {
        id: "subscript-index",
        cause: "06_nested_subscript, 07_ternary_subscript",
        summary: "`${a[b[-1]]}` and `${T[p > m ? p : m]}` — subscript index is too narrow",
        detail:
            "A subscript index accepts _literal | binary | unary | compound_statement |\n" +
            "subshell, but bash evaluates the index as a full arithmetic expression, so\n" +
            "a ternary or a nested subscript is legal there. Adding $.subscript makes\n" +
            "the rule self-referential, which needs the conflict declared below.",
        find:
            "field('index', choice($._literal, $.binary_expression, $.unary_expression, $.compound_statement, $.subshell)),",
        replace:
            "field('index', choice($._literal, $.binary_expression, $.unary_expression, $.ternary_expression, $.subscript, $.compound_statement, $.subshell)),",
    },
    {
        id: "subscript-conflict",
        cause: "06_nested_subscript",
        summary: "declare the LR conflict introduced by nested subscripts",
        detail:
            "tree-sitter generate reports an unresolved conflict for\n" +
            "`variable_name [ variable_name [ ... ] • _concat` once subscript can nest,\n" +
            "and names this as the resolution itself.",
        find: "    [$.pipeline],\n  ],",
        replace: "    [$.pipeline],\n    [$.subscript],\n  ],",
    },
    {
        id: "arith-base-prefix",
        cause: "03_arith_base_prefix",
        summary: "`$((10#$month))` — base prefix followed by an unbraced expansion",
        detail:
            "The number rule already handles `10#12` and `10#${month}`, but its choice\n" +
            "for the post-# operand omits simple_expansion, so the very common\n" +
            "zero-padding idiom `10#$month` fails.",
        find: "seq(/-?(0x)?[0-9]+#/, choice($.expansion, $.command_substitution)),",
        replace: "seq(/-?(0x)?[0-9]+#/, choice($.expansion, $.simple_expansion, $.command_substitution)),",
    },
];
