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

// BashTab's forked grammar when it has been built, else the stock parser.
// The fork fixes constructs upstream cannot parse (see lib/grammar/); without
// it those files simply report BU000 coverage warnings.
const { load } = require(path.join(__dirname, "..", "grammar", "load.js"));
const { language: Bash, forked: USING_FORK } = load();

const parser = new Parser();
parser.setLanguage(Bash);

const { RULES, RULE_BY_ID, NODE_RULES, FILE_RULES, helpers } = require("./rules.js");
const { hasAncestor } = helpers;

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

// ── project facts (computed once, shared by every file) ──────────────────

const REPO = path.resolve(__dirname, "..", "..");

function scanOnce(fn) {
    let value;
    let done = false;
    return () => {
        if (!done) {
            try {
                value = fn();
            } catch (e) {
                value = new Set();
            }
            done = true;
        }
        return value;
    };
}

/** Command names the framework would register, from the command filenames. */
const knownCommands = scanOnce(() => {
    const out = new Set();
    const walk = (dir) => {
        for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
            const p = path.join(dir, e.name);
            if (e.isDirectory()) walk(p);
            else if (/^bu-.+\.sh$/.test(e.name)) out.add(e.name.replace(/^bu-/, "").replace(/\.sh$/, ""));
        }
    };
    walk(path.join(REPO, "commands"));
    return out;
});

/** Help topics, from help/<topic>.help.sh. */
const helpTopics = scanOnce(() => {
    const out = new Set();
    for (const f of fs.readdirSync(path.join(REPO, "help"))) {
        const m = /^(.+)\.help\.sh$/.exec(f);
        if (m) out.add(m[1]);
    }
    return out;
});

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
    // `# bu-lint: disable=BU001,BU010 -- reason` on the finding's own line or
    // the line above it suppresses those rules there. BU005 separately flags a
    // suppression with no reason, so the escape hatch cannot become the norm.
    const suppressedAt = (line, ruleId) => {
        for (const candidate of [lines[line - 1], lines[line - 2]]) {
            if (!candidate) continue;
            const m = /#\s*bu-lint:\s*disable=([A-Za-z0-9_,]+)/.exec(candidate);
            if (!m) continue;
            const ids = m[1].split(",").map((x) => x.trim());
            if (ids.includes(ruleId) || ids.includes("*")) return true;
        }
        return false;
    };

    const push = (rule, line, message, snippet) => {
        if (rule.id !== "BU005" && suppressedAt(line, rule.id)) return;
        findings.push({
            file: reported,
            line,
            rule: rule.id,
            severity: rule.severity,
            message,
            snippet: (snippet || "").split("\n")[0].replace(/\t/g, " ").trim().slice(0, 60),
        });
    };

    const tree = parser.parse(src);

    const unix = file.replace(/\\/g, "/");
    const ctx = {
        file,
        src,
        lines,
        tree,
        isCommandScript: /(^|\/)commands\/[^/]+\/bu-[^/]+\.sh$/.test(unix),
        // Files sourced while a user's shell is initializing: a non-zero return
        // here aborts that shell (see AGENTS.md, "set -e safety").
        isInitScript:
            /(^|\/)config\/[^/]+\.sh$/.test(unix) ||
            /_bu_preinit\.sh$/.test(unix) ||
            /bu_entrypoint\.sh$/.test(unix) ||
            /(^|\/)lib\/core\/bu_core_(init|early_init|preinit|var)\.sh$/.test(unix),
        dispatch: (/^#\s*Dispatch:\s*(\S+)/m.exec(lines.slice(0, 8).join("\n")) || [])[1] || "",
        knownCommands: knownCommands(),
        helpTopics: helpTopics(),
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
                const verdict = r.test(node, ctx);
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
                "rules were skipped there; run `bash -n` to confirm the file itself is valid" +
                (USING_FORK ? "" : " (BashTab's grammar fork is not built: node lib/grammar/build.js)"),
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
