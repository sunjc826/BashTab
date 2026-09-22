"use strict";

/**
 * bu lint — rule registry.
 *
 * A rule is one of three kinds:
 *
 *   node   dispatched during a single cursor walk, on one CST node type.
 *          test(node, ctx) -> false | true | "RULEID" | {message}
 *   file   runs once per file. test(lines, ctx) -> [{line, message?}]
 *   alias  not dispatched; a label another rule re-tags a finding with.
 *
 * `ctx` carries: file, src, lines, tree, isCommandScript, isInitScript,
 * dispatch, knownCommands, helpTopics, lineOf(byteIndex).
 *
 * Ship discipline: run a new rule over the whole repo before believing it.
 * A rule whose corpus run is mostly false positives is worse than no rule —
 * one earlier candidate fired 210 times on a healthy codebase and was cut.
 * Findings that are real but pre-existing belong in .bulintbaseline, not in
 * a weakened rule.
 */

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

const LOOP_TYPES = ["while_statement", "for_statement", "c_style_for_statement"];
/** Is this node inside a loop body? (used by the fork-in-a-loop rules) */
const inLoop = (n) => LOOP_TYPES.some((t) => hasAncestor(n, t));
/** Nearest enclosing function_definition, or null. */
const enclosingFunction = (n) => {
    for (let p = n.parent; p; p = p.parent) if (p.type === "function_definition") return p;
    return null;
};
/** Direct and nested command nodes under a node. */
const allCommands = (n) => {
    const out = [];
    const walk = (x) => {
        if (x.type === "command") out.push(x);
        for (const c of x.namedChildren) walk(c);
    };
    walk(n);
    return out;
};
const helpers = { hasAncestor, wordsOf, commandsIn, commandName, caseAnnotation, inLoop, enclosingFunction, allCommands };

// ── rules ────────────────────────────────────────────────────────────────

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
    // ── Group A: `set -e` safety ─────────────────────────────────────────
    {
        id: "BU002",
        severity: "error",
        kind: "node",
        node: "command",
        summary: "non-zero return on the shell-initialization path",
        explain:
            "Config and preinit scripts are sourced while a user's shell is starting.\n" +
            "A non-zero return there aborts the whole sourcing under `set -e` — it kills\n" +
            "the user's shell, not a subprocess. Functions that can fail normally (a\n" +
            "cache miss, an absent optional tool) must log a warning and return 0.",
        message: "non-zero return in a script sourced during shell init — return 0 and log instead",
        test(n, ctx) {
            if (!ctx.isInitScript) return false;
            if (helpers.commandName(n) !== "return") return false;
            // Inside a function the return is that function's contract; only a
            // file-scope return aborts the sourcing outright.
            if (helpers.enclosingFunction(n)) return false;
            const arg = n.namedChildren[1];
            return !!arg && arg.type === "number" && arg.text !== "0";
        },
    },
    {
        id: "BU003",
        severity: "warning",
        kind: "node",
        node: "command",
        summary: "unguarded call on the shell-initialization path",
        explain:
            "AGENTS.md asks init call sites to be written `f || true` even when f already\n" +
            "returns 0 — defensive redundancy, because the callee's contract can change\n" +
            "without the call site noticing. This flags file-scope calls to bu_* helpers\n" +
            "in init scripts that carry no guard.",
        message: "call on the init path without `|| true`",
        test(n, ctx) {
            if (!ctx.isInitScript) return false;
            const name = helpers.commandName(n);
            if (!/^(bu_|__bu_)/.test(name)) return false;
            if (helpers.enclosingFunction(n)) return false; // only file-scope calls run at source time
            const p = n.parent;
            if (!p) return false;
            // `f || true`, `f && g`, `if f`, `while f`, `! f` all consume the status.
            if (["list", "negated_command", "if_statement", "while_statement", "until_statement", "elif_clause", "pipeline"].includes(p.type))
                return false;
            return true;
        },
    },
    {
        id: "BU004",
        severity: "error",
        kind: "node",
        node: "declaration_command",
        summary: "`local x=$(cmd)` masks the command's exit status",
        explain:
            "`local` is itself a command, so its exit status is local's, not the command\n" +
            "substitution's: `$?` afterwards is always 0 and the failure is invisible.\n" +
            "Declare first, assign second:\n" +
            "\n" +
            "    local x\n" +
            "    x=$(cmd) || return 1",
        message: "`local x=$(cmd)` then `$?` — local's status masks the command's",
        test(n) {
            if (n.child(0) === null || n.child(0).text !== "local") return false;
            if (!/\$\(/.test(n.text)) return false;
            const next = n.nextNamedSibling;
            return !!next && /\$\?/.test(next.text);
        },
    },
    {
        id: "BU005",
        severity: "warning",
        kind: "file",
        summary: "lint suppression without a reason",
        explain:
            "`# bu-lint: disable=BU001` silences a rule. Without a stated reason the next\n" +
            "reader cannot tell whether it is still justified, and the escape hatch\n" +
            "quietly becomes the default. Write why:\n" +
            "\n" +
            "    # bu-lint: disable=BU001 -- counter is only reported, never an exit status",
        message: "suppression has no reason — add `-- why` after the rule ids",
        test(lines) {
            const out = [];
            lines.forEach((l, i) => {
                const m = /#\s*bu-lint:\s*disable=([A-Za-z0-9_,*]+)(.*)$/.exec(l);
                if (m && !/\S/.test(m[2].replace(/^\s*--/, ""))) out.push({ line: i + 1 });
            });
            return out;
        },
    },

    // ── Group B: the custom source() wrapper ─────────────────────────────
    {
        id: "BU013",
        severity: "info",
        kind: "node",
        node: "command",
        summary: "source-wrapper bypass without an explanation",
        explain:
            "`builtin source` and `bu_ext_source` deliberately bypass bu_def_source, which\n" +
            "means no --__bu-once, no autopushd, and different scoping. That is sometimes\n" +
            "right, but it is never obvious — say why on the line above.",
        message: "source-wrapper bypass with no comment saying why",
        test(n, ctx) {
            const name = helpers.commandName(n);
            const isBypass = name === "bu_ext_source" || (name === "builtin" && helpers.wordsOf(n)[0] === "source");
            if (!isBypass) return false;
            const prev = ctx.lines[n.startPosition.row - 1] || "";
            return !/^\s*#/.test(prev);
        },
    },

    // ── Group C: the case-block parser DSL ───────────────────────────────
    {
        id: "BU022",
        severity: "warning",
        kind: "node",
        node: "case_item",
        summary: "parsed positional is never read",
        explain:
            "bu_parse_positional consumes an argument and exposes it as ${!shift_by}. A\n" +
            "branch that calls it but never reads shift_by silently drops the value the\n" +
            "user typed.",
        message: "bu_parse_positional consumes an argument the branch never reads",
        test(n) {
            const cmds = helpers.commandsIn(n);
            if (!cmds.some((c) => helpers.commandName(c) === "bu_parse_positional")) return false;
            return !n.namedChildren.some(
                (c) =>
                    helpers.commandName(c) !== "bu_parse_positional" &&
                    (/shift_by/.test(c.text) || /"\$[2-9]"/.test(c.text))
            );
        },
    },
    {
        id: "BU025",
        severity: "error",
        kind: "node",
        node: "command",
        summary: "`--as-if` names a command that does not exist",
        explain:
            "`--as-if cmd ... as-if--` delegates completion to another command. A typo\n" +
            "produces no completions and no error. Only literal targets are checked; a\n" +
            "target built from an expansion is left alone.",
        message: "--as-if target is not a known command",
        test(n, ctx) {
            const kids = n.children;
            for (let i = 0; i < kids.length - 1; i++) {
                if (kids[i].type !== "word" || kids[i].text !== "--as-if") continue;
                let target = kids[i + 1];
                if (target && target.type === "word" && target.text === "bu") target = kids[i + 2];
                if (!target || target.type !== "word") return false; // expansion — not statically checkable
                if (/^--/.test(target.text)) return false;
                if (!ctx.knownCommands.has(target.text))
                    return { message: `--as-if target '${target.text}' is not a known command` };
            }
            return false;
        },
    },
    {
        id: "BU026",
        severity: "error",
        kind: "node",
        node: "case_item",
        summary: "duplicate alternative in a case pattern",
        explain:
            "The same alternative listed twice in one pattern. Harmless at runtime, but it\n" +
            "means one of the two was meant to be a different option — and completion will\n" +
            "show the group once, hiding the mistake.",
        message: "duplicate alternative in the case pattern",
        test(n) {
            const pats = [];
            let current = "";
            for (const c of n.children) {
                if (c.type === ")") break;
                if (c.type === "|") {
                    pats.push(current);
                    current = "";
                } else if (c.type !== "(") current += c.text;
            }
            if (current) pats.push(current);
            const seen = new Set();
            for (const p of pats) {
                if (seen.has(p)) return { message: `duplicate alternative '${p}' in the case pattern` };
                seen.add(p);
            }
            return false;
        },
    },
    {
        id: "BU027",
        severity: "warning",
        kind: "node",
        node: "case_statement",
        summary: "argument parser with no `*)` fallback",
        explain:
            "Without a catch-all calling bu_parse_error_enum, an unknown option falls\n" +
            "through the case silently: the parser shifts past it and the user gets no\n" +
            "error, just surprising behavior.",
        message: "argument-parsing case has no `*)` fallback — unknown options pass silently",
        test(n) {
            const scrutinee = n.namedChildren[0];
            if (!scrutinee || scrutinee.text !== '"$1"') return false;
            if (!helpers.hasAncestor(n, "while_statement")) return false;
            let loop = n.parent;
            while (loop && loop.type !== "while_statement") loop = loop.parent;
            if (!loop || !/bu_parse_multiselect/.test(loop.text)) return false;
            return !n.namedChildren.some(
                (c) => c.type === "case_item" && c.children.some((x) => x.type === "extglob_pattern" && x.text === "*")
            );
        },
    },
    {
        id: "BU028",
        severity: "warning",
        kind: "node",
        node: "while_statement",
        summary: "argument parser without the shift_by bounds guard",
        explain:
            "The template checks `(( $# < shift_by ))` before shifting, so an option whose\n" +
            "argument is missing reports a parse error instead of shifting past the end of\n" +
            "the argument list.",
        message: "argument-parsing loop has no `(( $# < shift_by ))` guard before the shift",
        test(n) {
            if (!/bu_parse_multiselect/.test(n.text)) return false;
            return !/\(\(\s*\$#\s*<\s*shift_by\s*\)\)/.test(n.text);
        },
    },

    // ── Group D: command template invariants ─────────────────────────────
    {
        id: "BU030",
        severity: "error",
        kind: "node",
        node: "function_definition",
        summary: "scope pushed but never popped",
        explain:
            "bu_scope_push_function opens a scope whose cleanups run at bu_scope_pop_function.\n" +
            "A function that pushes and never pops leaks the scope into its caller — the\n" +
            "cleanups then run at the wrong time, or not at all.\n" +
            "\n" +
            "Early `return 0` in the autocomplete and help branches is by design and is not\n" +
            "reported; only a function with no pop at all is.",
        message: "bu_scope_push_function with no matching bu_scope_pop_function",
        test(n) {
            const name = n.namedChildren[0] ? n.namedChildren[0].text : "";
            if (/^bu_scope_/.test(name)) return false; // the scope helpers themselves
            const calls = helpers.allCommands(n).map(helpers.commandName);
            return calls.includes("bu_scope_push_function") && !calls.includes("bu_scope_pop_function");
        },
    },
    {
        id: "BU031",
        severity: "warning",
        kind: "file",
        summary: "executable command without an exit handler",
        explain:
            "Commands that run in their own process set up bu_exit_handler_setup so an\n" +
            "unexpected exit still runs scope cleanups and reports the failing line.\n" +
            "`Dispatch: source` commands run in the user's shell and correctly do not.",
        message: "executable command does not call bu_exit_handler_setup",
        test(lines, ctx) {
            if (!ctx.isCommandScript) return [];
            if (ctx.dispatch && ctx.dispatch !== "execute") return [];
            if (/bu_exit_handler_setup/.test(ctx.src)) return [];
            return [{ line: 1 }];
        },
    },
    {
        id: "BU033",
        severity: "warning",
        kind: "file",
        summary: "command without an autocomplete guard",
        explain:
            "Every command is executed during completion. Without the\n" +
            "`if bu_env_is_in_autocomplete; then bu_autocomplete; return 0; fi` guard, the\n" +
            "command's real work runs on every Tab press.",
        message: "command has no bu_env_is_in_autocomplete guard — its body runs on every Tab",
        test(lines, ctx) {
            if (!ctx.isCommandScript) return [];
            return /bu_env_is_in_autocomplete/.test(ctx.src) ? [] : [{ line: 1 }];
        },
    },
    {
        id: "BU034",
        severity: "warning",
        kind: "file",
        summary: "`--help` parsed but never acted on",
        explain: "A branch sets is_help=true and nothing ever calls bu_autohelp, so --help does nothing.",
        message: "is_help is set but bu_autohelp is never called",
        test(lines, ctx) {
            if (!/is_help=true/.test(ctx.src)) return [];
            return /bu_autohelp/.test(ctx.src) ? [] : [{ line: 1 }];
        },
    },

    // ── Group E: headers and metadata ────────────────────────────────────
    {
        id: "BU042",
        severity: "error",
        kind: "file",
        summary: "unknown Dispatch value",
        explain:
            "Dispatch decides how the command runs: `execute` (new process), `source`\n" +
            "(current shell), `function`, or `alias`. Anything else is not recognized and\n" +
            "the command falls back to the default dispatch.",
        test(lines, ctx) {
            const valid = ["execute", "source", "function", "alias"];
            if (!ctx.dispatch || valid.includes(ctx.dispatch)) return [];
            const i = lines.findIndex((l) => /^#\s*Dispatch:/.test(l));
            return [{ line: i + 1, message: `Dispatch: '${ctx.dispatch}' is not one of ${valid.join(", ")}` }];
        },
    },
    {
        id: "BU044",
        severity: "warning",
        kind: "file",
        summary: "producer without a Fields declaration",
        explain:
            "`Pipeline: producer` tells completion this command starts an object pipeline,\n" +
            "but without `# Fields:` the field-aware completion after a pipe has nothing to\n" +
            "offer: `bu <cmd> | bu select <TAB>` goes quiet.",
        message: "Pipeline: producer with no # Fields: header — downstream field completion is empty",
        test(lines, ctx) {
            if (!ctx.isCommandScript) return [];
            const head = lines.slice(0, 30).join("\n");
            if (!/^#\s*Pipeline:\s*producer\s*$/m.test(head)) return [];
            return /^#\s*Fields:/m.test(head) ? [] : [{ line: 1 }];
        },
    },
    {
        id: "BU045",
        severity: "error",
        kind: "file",
        summary: "Help-Topic points at a topic that does not exist",
        explain: "`# Help-Topic: X` must name a page in help/X.help.sh, or the cross-reference is dead.",
        test(lines, ctx) {
            const i = lines.findIndex((l) => /^#\s*Help-Topic:/.test(l));
            if (i < 0) return [];
            const topic = /^#\s*Help-Topic:\s*(\S+)/.exec(lines[i])[1];
            if (ctx.helpTopics.size === 0) return [];
            return ctx.helpTopics.has(topic) ? [] : [{ line: i + 1, message: `Help-Topic '${topic}' has no page in help/` }];
        },
    },

    // ── Group F: object pipeline and cost ────────────────────────────────
    {
        id: "BU050",
        severity: "info",
        kind: "node",
        node: "command",
        summary: "bu_out_record called in a loop",
        explain:
            "bu_out_record forks a jq per call. In a loop that is one process per record.\n" +
            "Emit TSV in the loop and recordify once:\n" +
            "\n" +
            "    { for x in ...; do printf '%s\\t%s\\n' \"$a\" \"$b\"; done; } \\\n" +
            "        | bu_out_from_tsv --columns a,b",
        message: "bu_out_record inside a loop forks a jq per record — emit TSV and recordify once",
        test(n) {
            return helpers.commandName(n) === "bu_out_record" && helpers.inLoop(n);
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

module.exports = { RULES, RULE_BY_ID, NODE_RULES, FILE_RULES, helpers };
