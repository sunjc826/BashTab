#!/usr/bin/env node

/**
 * bu lint — tree-sitter rule engine for BashTab command scripts and core
 * libraries.
 *
 * Why tree-sitter and not a regex/awk pass: every rule here asks a
 * STRUCTURAL question that text matching answers wrongly.
 *
 *   ((i++))        is a (compound_statement) whose first child is `((`
 *   x=$((i++))     is an (arithmetic_expansion)  — a different node entirely
 *   if ((i > 0))   is the same compound_statement, but in CONDITION position
 *
 * A regex that matches the first without matching the others has to anchor on
 * line position, which then misses `for f in ...; do ((i++)); done`.  The CST
 * has no such tension.
 *
 * Rule shape:
 *   { id, severity, summary, explain, node: "<cst type>", test(n, ctx) }
 *     - `node` rules are dispatched during a single cursor walk.
 *     - `file` rules run once per file over raw lines (headers are a
 *       line-oriented format — the framework's own header parser treats them
 *       that way, with 8- and 30-line recognition windows).
 *   `test` returns false, true, or a rule id to re-label the finding.
 *
 * Output: TSV (file, line, rule, severity, message, snippet) for
 * bu_out_from_tsv, or JSON with --json.
 *
 * Exit: 0 clean, 1 errors present, 2 warnings present with --strict.
 */

"use strict";

const fs = require("fs");
const path = require("path");

// Resolve the bindings from BashTab's own node_modules no matter the cwd.
const MODULE_ROOT = path.resolve(__dirname, "..", "..", "node_modules");
function requireBinding(name) {
    try {
        return require(name);
    } catch (e) {
        try {
            return require(path.join(MODULE_ROOT, name));
        } catch (e2) {
            process.stderr.write(
                `bu lint: cannot load '${name}'. Run 'pnpm install' in ${path.resolve(__dirname, "..", "..")}.\n`
            );
            process.exit(3);
        }
    }
}

const Parser = requireBinding("tree-sitter");
const Bash = requireBinding("tree-sitter-bash");

const parser = new Parser();
parser.setLanguage(Bash);

// ── helpers ──────────────────────────────────────────────────────────────

const hasAncestor = (n, type) => {
    for (let p = n.parent; p; p = p.parent) if (p.type === type) return true;
    return false;
};
const wordsOf = (n) => n.children.filter((c) => c.type === "word").map((c) => c.text);
const commandsIn = (n) => n.children.filter((c) => c.type === "command");
const commandName = (n) => {
    const first = n.child(0);
    return first && first.type === "command_name" ? first.text : "";
};
/** The `# _FLAG` / `# HINT` annotation: the comment directly after `)`. */
const caseAnnotation = (n) => {
    const closeIdx = n.children.findIndex((c) => c.type === ")");
    if (closeIdx < 0) return null;
    const next = n.children[closeIdx + 1];
    return next && next.type === "comment" ? next : null;
};

// ── rule registry ────────────────────────────────────────────────────────

const RULES = [
    {
        id: "BU000",
        severity: "warning",
        kind: "file",
        summary: "file did not parse cleanly — rule coverage is incomplete",
        explain:
            "tree-sitter-bash could not parse part of this file. The file is usually still\n" +
            "VALID bash (check with `bash -n`) — these are grammar gaps, not defects in\n" +
            "your script. Known gaps in tree-sitter-bash 0.25.1, all seen in this repo:\n" +
            "\n" +
            "    case pattern `--a|-b)#comment`   (no space before the comment)\n" +
            "    `${VAR:+true|false}`             (alternation inside an expansion)\n" +
            "    `$((10#$month))`                 (base-prefixed arithmetic)\n" +
            "    `exec {FD}<>\"$file\"`            (varname file descriptor)\n" +
            "\n" +
            "Rules still run over the rest of the file; findings inside the unparsed\n" +
            "regions are suppressed rather than guessed at. This rule exists so that\n" +
            "reduced coverage is always announced — a linter that silently reports\n" +
            "'clean' on a file it could not read is worse than no linter.",
        // Emitted by the driver, which knows the error positions; listed here
        // so --explain and --list-rules see it.
        test: () => [],
    },
    {
        id: "BU001",
        severity: "warning",
        kind: "node",
        node: "compound_statement",
        summary: "arithmetic command at statement position",
        explain:
            "`((x++))` evaluates to the PRE-increment value and uses it as the exit\n" +
            "status, so when x is 0 the command returns 1. Under `set -e` that aborts —\n" +
            "and for a `Dispatch: source` command, the shell it aborts is the user's.\n" +
            "\n" +
            "    ✗ ((count++))\n" +
            "    ✓ : $((count++))\n" +
            "\n" +
            "Condition position (`if ((x))`, `while ((x))`) and `|| true` consume the\n" +
            "status, so those are not reported.",
        message: "arithmetic command returns 1 when the expression evaluates to 0 — use `: $((x++))`",
        test(n) {
            if (n.child(0) === null || n.child(0).type !== "((") return false;
            if (!/(\+\+|--|\+=|-=)/.test(n.text)) return false;
            const p = n.parent;
            if (p && ["if_statement", "while_statement", "until_statement", "elif_clause"].includes(p.type)) {
                // Is this the CONDITION (before `then`/`do`) rather than the body?
                const kw = p.children.find((c) => c.type === "then" || c.type === "do");
                if (!kw || n.startIndex < kw.startIndex) return false;
            }
            // `((x++)) || true` / `((x++)) && f` — the status is consumed.
            if (p && p.type === "list") return false;
            return true;
        },
    },
    {
        id: "BU010",
        severity: "error",
        kind: "node",
        node: "declaration_command",
        summary: "declare without -g at file scope",
        explain:
            "After activation `source` is not the builtin — bu_def_source is a FUNCTION,\n" +
            "so a file-scope `declare` inside a sourced file creates a local of that\n" +
            "function and vanishes when source returns. The failure is silent: the\n" +
            "globals are simply missing afterwards.\n" +
            "\n" +
            "    ✗ declare -A MY_MAP=()\n" +
            "    ✓ declare -A -g MY_MAP=()\n" +
            "\n" +
            "Plain assignments are fine; associative arrays and readonly REQUIRE declare,\n" +
            "so they must carry -g (reported as BU011). Declarations inside a function\n" +
            "body are correct as-is and are not reported.",
        message: "file-scope declare without -g is lost when source() returns",
        test(n) {
            const kw = n.child(0) ? n.child(0).text : "";
            if (kw !== "declare" && kw !== "typeset") return false;
            const words = wordsOf(n);
            // -g present, or -f/-p (function/print attributes, not variables).
            if (words.some((w) => /^-[a-zA-Z]*[gfp]/.test(w))) return false;
            if (hasAncestor(n, "function_definition")) return false;
            return words.some((w) => /^-[a-zA-Z]*[Ar]/.test(w)) ? "BU011" : true;
        },
    },
    {
        id: "BU011",
        severity: "error",
        kind: "alias",
        summary: "associative/readonly declare without -g at file scope",
        explain:
            "Same mechanism as BU010, escalated: for `-A` and `-r` there is no plain\n" +
            "assignment fallback, so the declaration MUST carry -g or the value is lost.",
        message: "associative/readonly declare without -g becomes a local of the source() wrapper",
    },
    {
        id: "BU021",
        severity: "error",
        kind: "node",
        node: "case_item",
        summary: "`# _FLAG` annotation contradicts the parser call",
        explain:
            "Case-pattern comments drive autohelp only; runtime arity is decided solely\n" +
            "by the bu_parse_* calls. When a branch is annotated `# _FLAG` but calls\n" +
            "bu_parse_positional, --help documents an option that actually consumes an\n" +
            "argument. Fix whichever side is wrong — the annotation or the call.",
        message: "`# _FLAG` on a branch that calls bu_parse_positional — autohelp will lie about arity",
        test(n) {
            const annot = caseAnnotation(n);
            if (!annot || !/_FLAG/.test(annot.text)) return false;
            return commandsIn(n).some((c) => commandName(c) === "bu_parse_positional");
        },
    },
    {
        id: "BU024",
        severity: "error",
        kind: "node",
        node: "command",
        summary: "autocomplete DSL list opened without its terminator",
        explain:
            "The DSL lists (--enum, --stdout, --ret, --as-if, --delimited) are terminated\n" +
            "by a sentinel word (enum--, stdout--, ...). Without it the master helper\n" +
            "consumes the rest of argv as list members, so later DSL arguments are\n" +
            "silently swallowed and completion goes quiet.",
        message: "DSL list opened without its terminator sentinel",
        test(n) {
            if (!/^bu_parse/.test(commandName(n))) return false;
            const words = wordsOf(n);
            const pairs = [
                ["--enum", "enum--"],
                ["--stdout", "stdout--"],
                ["--ret", "ret--"],
                ["--as-if", "as-if--"],
                ["--delimited", "delimited--"],
            ];
            for (const [open, close] of pairs) {
                if (words.includes(open) && !words.includes(close)) {
                    return { message: `${open} without its \`${close}\` terminator` };
                }
            }
            return false;
        },
    },
    {
        id: "BU032",
        severity: "error",
        kind: "file",
        summary: "--is-compatible handled after entrypoint sourcing",
        explain:
            "The framework probes gated commands with `bash <script> --is-compatible`.\n" +
            "If the entrypoint is sourced first, that probe runs a full command scan,\n" +
            "which probes every gated command again — infinite recursion that hangs the\n" +
            "probe until Ctrl-C. The --is-compatible branch must exit BEFORE any\n" +
            "entrypoint sourcing.",
        message: "--is-compatible handled after entrypoint sourcing (the probe recurses and hangs)",
        test(_lines, ctx) {
            if (!ctx.isCommandScript) return [];
            if (ctx.entrypointIndex < 0 || ctx.isCompatIndex < 0) return [];
            if (ctx.isCompatIndex <= ctx.entrypointIndex) return [];
            return [{ line: ctx.lineOf(ctx.isCompatIndex) }];
        },
    },
    {
        id: "BU040",
        severity: "warning",
        kind: "file",
        summary: "missing command header",
        explain:
            "Command scripts declare metadata in `# Key: value` headers near the top.\n" +
            "`# Synopsis:` feeds the command catalog and `bu get-help`; `# Dispatch:`\n" +
            "decides whether the command runs in a new process, the current shell, or as\n" +
            "a function. A missing Dispatch header means the dispatch type is implicit.",
        test(lines, ctx) {
            if (!ctx.isCommandScript) return [];
            const found = new Set();
            lines.slice(0, 30).forEach((l) => {
                const m = /^#\s*([A-Za-z][A-Za-z0-9-]*):\s/.exec(l);
                if (m) found.add(m[1]);
            });
            const out = [];
            for (const key of ["Synopsis", "Dispatch"]) {
                if (!found.has(key)) out.push({ line: 1, message: `missing # ${key}: header` });
            }
            return out;
        },
    },
    {
        id: "BU041",
        severity: "error",
        kind: "file",
        summary: "recognized header outside its recognition window",
        explain:
            "Directive headers (Dispatch, Tab-Execute, Tab-Execute-Field) are honored only\n" +
            "within the first 8 lines; every other recognized header within the first 30.\n" +
            "Past that window the header parses as an ordinary comment and is silently\n" +
            "ignored — the metadata looks declared but never takes effect.",
        test(lines) {
            const DIRECTIVE = ["Dispatch", "Tab-Execute", "Tab-Execute-Field"];
            const OTHER = ["Synopsis", "Fields", "Pipeline", "Help-Topic"];
            const out = [];
            lines.forEach((l, i) => {
                const m = /^#\s*([A-Za-z][A-Za-z0-9-]*):\s/.exec(l);
                if (!m) return;
                const key = m[1];
                const isDirective = DIRECTIVE.includes(key);
                if (!isDirective && !OTHER.includes(key)) return;
                const win = isDirective ? 8 : 30;
                if (i + 1 > win) {
                    out.push({
                        line: i + 1,
                        message: `header \`${key}:\` past its line-${win} window — silently ignored`,
                    });
                }
            });
            return out;
        },
    },
];

const RULE_BY_ID = new Map(RULES.map((r) => [r.id, r]));
const NODE_RULES = new Map();
for (const r of RULES.filter((r) => r.kind === "node")) {
    if (!NODE_RULES.has(r.node)) NODE_RULES.set(r.node, []);
    NODE_RULES.get(r.node).push(r);
}
const FILE_RULES = RULES.filter((r) => r.kind === "file" && r.id !== "BU000");

// ── grammar assertion ────────────────────────────────────────────────────
//
// Node type names are grammar-version state: a tree-sitter-bash bump can
// rename them, and every rule would then silently match nothing.  Assert the
// types this engine depends on still exist, against a known fixture.

const GRAMMAR_PROBE = `x=0
((x++))
declare -A M=()
case "$1" in
-h)# _FLAG
    :
    ;;
esac
`;

function assertGrammar() {
    const seen = new Set();
    const cur = parser.parse(GRAMMAR_PROBE).walk();
    let done = false;
    while (!done) {
        seen.add(cur.nodeType);
        if (cur.gotoFirstChild()) continue;
        while (!cur.gotoNextSibling()) {
            if (!cur.gotoParent()) {
                done = true;
                break;
            }
        }
    }
    const required = ["compound_statement", "declaration_command", "case_item", "comment", "command"];
    const missing = required.filter((t) => !seen.has(t));
    if (missing.length) {
        process.stderr.write(
            "bu lint: tree-sitter-bash grammar is incompatible with this rule set.\n" +
                `  expected node types not produced: ${missing.join(", ")}\n` +
                "  The rules match on CST node names; a grammar bump can rename them.\n" +
                "  Pin tree-sitter-bash to a known-good version or update lib/lint/bu_lint.js.\n"
        );
        process.exit(3);
    }
}

// ── baseline ─────────────────────────────────────────────────────────────

/** Stable key: rule + file + normalized snippet. Line numbers deliberately
 *  excluded so a baseline survives unrelated edits above a finding. */
function baselineKey(f) {
    const norm = f.snippet.replace(/\s+/g, " ").trim();
    let h = 0x811c9dc5;
    for (let i = 0; i < norm.length; i++) {
        h ^= norm.charCodeAt(i);
        h = Math.imul(h, 0x01000193) >>> 0;
    }
    return `${f.rule}\t${f.file}\t${h.toString(16)}`;
}

// ── driver ───────────────────────────────────────────────────────────────

const SEVERITY_RANK = { info: 0, warning: 1, error: 2 };

function lintFile(file, opts) {
    const src = fs.readFileSync(file, "utf8");
    // Paths are reported relative to --root so findings and baselines are
    // portable between checkouts and CI. Files outside root keep their path.
    const reported = opts.root && file.startsWith(opts.root + path.sep) ? file.slice(opts.root.length + 1) : file;
    const lines = src.split("\n");
    const findings = [];
    const push = (rule, line, message, snippet) =>
        findings.push({
            file: reported,
            line,
            rule: rule.id,
            severity: rule.severity,
            message,
            snippet: (snippet || "").split("\n")[0].replace(/\t/g, " ").trim().slice(0, 60),
        });

    const tree = parser.parse(src);

    const ctx = {
        isCommandScript: /(^|\/)commands\/[^/]+\/bu-[^/]+\.sh$/.test(file.replace(/\\/g, "/")),
        entrypointIndex: -1,
        isCompatIndex: -1,
        lineOf(index) {
            return src.slice(0, index).split("\n").length;
        },
    };

    // Single cursor walk. `cur.nodeType` is a cheap property; `cur.currentNode`
    // materializes a JS object across the native boundary, so it is read only
    // for node types that actually have a rule.
    const cur = tree.walk();
    const parseErrorRows = [];
    let done = false;
    while (!done) {
        const type = cur.nodeType;
        if (type === "ERROR" || cur.nodeIsMissing) parseErrorRows.push(cur.startPosition.row + 1);
        const rules = NODE_RULES.get(type);
        if (rules) {
            const node = cur.currentNode;
            for (const r of rules) {
                const verdict = r.test(node);
                if (!verdict) continue;
                // Suppress only if the MATCHED CONSTRUCT is itself damaged.
                // Testing for an ERROR *ancestor* is far too coarse: one
                // localized grammar gap makes tree-sitter wrap the whole file
                // in a single ERROR node, which would blind every rule over
                // thousands of sound lines. A subtree that parsed cleanly is
                // trustworthy no matter what failed elsewhere in the file.
                if (node.hasError) continue;
                const effective = typeof verdict === "string" ? RULE_BY_ID.get(verdict) : r;
                const message = (verdict && verdict.message) || effective.message || r.message;
                push(effective, node.startPosition.row + 1, message, node.text);
            }
            // Facts for file-scope rules, gathered from the same walk.
            if (type === "command" && /bu_entrypoint\.sh/.test(node.text) && ctx.entrypointIndex < 0)
                ctx.entrypointIndex = node.startIndex;
            if (/--is-compatible/.test(node.text) && ctx.isCompatIndex < 0) ctx.isCompatIndex = node.startIndex;
        } else if (type === "test_command") {
            const node = cur.currentNode;
            if (/--is-compatible/.test(node.text) && ctx.isCompatIndex < 0) ctx.isCompatIndex = node.startIndex;
        }
        if (cur.gotoFirstChild()) continue;
        while (!cur.gotoNextSibling()) {
            if (!cur.gotoParent()) {
                done = true;
                break;
            }
        }
    }

    if (parseErrorRows.length) {
        const rows = parseErrorRows.slice(0, 3).join(", ");
        push(
            RULE_BY_ID.get("BU000"),
            parseErrorRows[0],
            `tree-sitter could not parse ${parseErrorRows.length} region(s) (line(s) ${rows}) — ` +
                "rules were skipped there; run `bash -n` to confirm the file itself is valid",
            lines[parseErrorRows[0] - 1] || ""
        );
    }

    for (const r of FILE_RULES) {
        for (const hit of r.test(lines, ctx)) {
            push(r, hit.line, hit.message || r.message, lines[hit.line - 1] || "");
        }
    }

    return findings;
}

function main(argv) {
    const opts = {
        json: false,
        rules: null,
        severity: "info",
        baseline: null,
        writeBaseline: null,
        root: null,
        strict: false,
        files: [],
    };
    for (let i = 0; i < argv.length; i++) {
        const a = argv[i];
        if (a === "--json") opts.json = true;
        else if (a === "--strict") opts.strict = true;
        else if (a === "--rules") opts.rules = new Set(argv[++i].split(",").map((s) => s.trim()).filter(Boolean));
        else if (a === "--severity") opts.severity = argv[++i];
        else if (a === "--root") opts.root = path.resolve(argv[++i]);
        else if (a === "--baseline") opts.baseline = argv[++i];
        else if (a === "--write-baseline") opts.writeBaseline = argv[++i];
        else if (a === "--list-rules") {
            for (const r of RULES) {
                if (r.kind === "alias") continue;
                process.stdout.write(`${r.id}\t${r.severity}\t${r.summary}\n`);
            }
            return 0;
        } else if (a === "--explain") {
            const r = RULE_BY_ID.get(argv[++i].toUpperCase());
            if (!r) {
                process.stderr.write("bu lint: unknown rule\n");
                return 3;
            }
            process.stdout.write(`${r.id}  [${r.severity}]  ${r.summary}\n\n${r.explain}\n`);
            return 0;
        } else opts.files.push(a);
    }

    assertGrammar();

    let findings = [];
    for (const file of opts.files) {
        try {
            findings = findings.concat(lintFile(file, opts));
        } catch (e) {
            process.stderr.write(`bu lint: ${file}: ${e.message}\n`);
            return 3;
        }
    }

    if (opts.writeBaseline) {
        const keys = findings.map(baselineKey).sort();
        fs.writeFileSync(
            opts.writeBaseline,
            "# bu lint baseline — pre-existing findings CI should not fail on.\n" +
                "# Regenerate with: bu validate-script --all --write-baseline <file>\n" +
                keys.join("\n") +
                (keys.length ? "\n" : "")
        );
        process.stderr.write(`bu lint: wrote ${keys.length} baseline entries to ${opts.writeBaseline}\n`);
        return 0;
    }

    if (opts.baseline && fs.existsSync(opts.baseline)) {
        const known = new Set(
            fs
                .readFileSync(opts.baseline, "utf8")
                .split("\n")
                .filter((l) => l && !l.startsWith("#"))
        );
        findings = findings.filter((f) => !known.has(baselineKey(f)));
    }

    const floor = SEVERITY_RANK[opts.severity] !== undefined ? SEVERITY_RANK[opts.severity] : 0;
    findings = findings.filter((f) => SEVERITY_RANK[f.severity] >= floor);
    if (opts.rules) findings = findings.filter((f) => opts.rules.has(f.rule));

    if (opts.json) {
        process.stdout.write(JSON.stringify(findings, null, 2) + "\n");
    } else {
        for (const f of findings)
            process.stdout.write([f.file, f.line, f.rule, f.severity, f.message, f.snippet].join("\t") + "\n");
    }

    if (findings.some((f) => f.severity === "error")) return 1;
    if (opts.strict && findings.length) return 2;
    return 0;
}

process.exit(main(process.argv.slice(2)));
