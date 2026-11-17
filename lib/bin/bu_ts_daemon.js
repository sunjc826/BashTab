#!/usr/bin/env node

/**
 * tree-sitter-bash daemon for BashTab.
 *
 * Reads one command per line from stdin in format:  CURSOR_OFFSET:COMMAND_LINE
 * Outputs one JSON line per parse.
 *
 * JSON fields:
 *   original       - the input command line (for text operations)
 *   nodes          - flat array of leaf nodes with type/subtypes
 *   pipeBefore     - text before the last pipeline separator
 *   pipeAfter      - text after the last pipeline separator
 *   cmdWords       - word-split of pipeAfter (for fzf's command_line array)
 *   cursor         - cursor position information
 *   cursorNode     - the deepest node at cursor position
 *   hasError       - whether tree-sitter reported a parse error
 */

const Parser = require("tree-sitter");
// BashTab's forked grammar when built, else stock. The fork matters more here
// than in the linter: completion parses command lines the user types, which
// cannot be rewritten to suit the grammar. See lib/grammar/.
const { load } = require("../grammar/load.js");
const { language: Bash } = load();
const parser = new Parser();
parser.setLanguage(Bash);

// Leaf-only nodes that carry meaning for completion
const LEAF_TYPES = new Set([
    "word", "variable_name", "string", "string_content",
    "simple_expansion", "expansion",
    "command_substitution", "process_substitution",
    "file_redirect", "heredoc_redirect",
    "(", ")", "{", "}", "\"", "'",
    "if", "then", "else", "elif", "fi",
    "for", "while", "do", "done",
    "case", "esac", "in",
    "|", "||", "&&", ";", "&",
    ">", ">>", "<", "<<", "<<-",
    "$", "${", "$(", "$((", "((",
]);

// Non-leaf nodes we want to collect because they represent
// completable units (their children are the leaf parts)
const COMPLETABLE_NON_LEAF = new Set([
    "simple_expansion",   // $VAR
    "expansion",          // ${VAR}
    "string",             // "..."
    "raw_string",         // '...'
    "ansi_c_string",      // $'...'
    "concatenation",      // adjacent expansions/strings
]);

// Map CST types to our completion-relevant kinds
function nodeKind(node) {
    switch (node.type) {
        case "word":               return "argument";
        case "string":
        case "raw_string":
        case "ansi_c_string":     return "string";
        case "string_content":     return "literal";
        case "simple_expansion":   return "dollar_word";    // $VAR
        case "expansion":          return "dollar_brace";   // ${VAR}
        case "variable_name":      return "var_name";
        case "command_substitution":   return "cmd_subst";
        case "process_substitution":   return "proc_subst";
        case "|": case "||": case "&&": case ";": case "&":
                                    return "separator";
        case ">": case ">>": case "<": case "<<": case "<<-":
                                    return "redirect_op";
        default: return node.type;
    }
}

function isPipelineSep(node) {
    return node.type === "|" || node.type === "||" || node.type === "&&" || node.type === ";";
}

// Collect leaf nodes and important non-leaf expansion nodes
function walk(node, source, nodes, depth) {
    if (node.childCount === 0) {
        // Leaf node
        if (node.text.trim().length > 0 || LEAF_TYPES.has(node.type)) {
            nodes.push({
                text:  node.text,
                type:  node.type,
                kind:  nodeKind(node),
                start: node.startIndex,
                end:   node.endIndex,
                depth: depth,
            });
        }
        return;
    }

    // Collect completable non-leaf nodes (e.g. simple_expansion, expansion, string)
    if (COMPLETABLE_NON_LEAF.has(node.type)) {
        nodes.push({
            text:  node.text,
            type:  node.type,
            kind:  nodeKind(node),
            start: node.startIndex,
            end:   node.endIndex,
            depth: depth,
        });
    }

    // Recurse into children
    for (let i = 0; i < node.childCount; i++) {
        walk(node.child(i), source, nodes, depth + 1);
    }
}

// Find the deepest leaf at a byte offset
function findNodeAt(nodes, offset) {
    let best = null;
    for (const n of nodes) {
        if (offset >= n.start && offset <= n.end) {
            if (!best || n.depth > best.depth) {
                best = n;
            }
        }
    }
    return best;
}

// Given the node at cursor, determine what to complete and what range to replace
function cursorInfo(nodes, nodeAtCursor, original) {
    if (!nodeAtCursor) return { nodeType: "none", replaceStart: 0, replaceEnd: 0 };

    let replaceStart = nodeAtCursor.start;
    let replaceEnd   = nodeAtCursor.end;
    let completeKind = nodeAtCursor.kind;

    // For variable_name, escalate to parent dollar_word / dollar_brace / expansion
    if (nodeAtCursor.type === "variable_name") {
        // Find the tightest containing non-leaf expansion node
        let best = null;
        for (const n of nodes) {
            if (n.start <= nodeAtCursor.start &&
                n.end >= nodeAtCursor.end &&
                (n.kind === "dollar_word" || n.kind === "dollar_brace")) {
                if (!best || n.end - n.start < best.end - best.start) {
                    best = n;
                }
            }
        }
        if (best) {
            replaceStart = best.start;
            replaceEnd   = best.end;
            completeKind = best.kind;
        } else {
            // No parent expansion node (e.g. parse error on incomplete ${VAR).
            // Search backwards in original text for ${ or $ to extend the range.
            const before = original.slice(0, replaceStart);
            const dbIdx  = before.lastIndexOf("${");
            const dIdx   = before.lastIndexOf("$");
            if (dbIdx >= 0 && /^\$\{[^}]*$/.test(before.slice(dbIdx))) {
                replaceStart = dbIdx;
                completeKind = "dollar_brace";
            } else if (dIdx >= 0 && before.slice(dIdx + 1).indexOf(" ") < 0) {
                replaceStart = dIdx;
                completeKind = "dollar_word";
            }
        }
    }

    return {
        nodeType:    nodeAtCursor.type,
        nodeKind:    nodeAtCursor.kind,
        nodeText:    nodeAtCursor.text,
        replaceStart,
        replaceEnd,
        replaceText: original.slice(replaceStart, replaceEnd),
        completeKind,
    };
}

const rl = require("readline").createInterface({ input: process.stdin });

rl.on("line", (line) => {
    const colonIdx = line.indexOf(":");
    if (colonIdx < 0) {
        process.stdout.write(JSON.stringify({ error: "invalid format" }) + "\n");
        return;
    }

    const cursorOffset = parseInt(line.slice(0, colonIdx), 10);
    const original = line.slice(colonIdx + 1);

    let tree;
    try {
        tree = parser.parse(original);
    } catch (e) {
        process.stdout.write(JSON.stringify({ error: "parse error: " + e.message }) + "\n");
        return;
    }

    const nodes = [];
    walk(tree.rootNode, original, nodes, 0);

    // Find pipeline separators by walking the CST. Tree-sitter
    // represents "a | b" as (pipeline (command ...) (command ...)) with
    // implicit "|" between sibling commands.
    let pipeBefore = "";
    let pipeAfter  = original;

    function findLastPipe(tree, offset) {
        let lastEnd = 0;
        function walk(node) {
            if (node.type === "pipeline" || node.type === "list" || node.type === "program") {
                for (let i = 1; i < node.childCount; i++) {
                    const prev = node.child(i - 1);
                    const curr = node.child(i);
                    // The separator is between prev.endIndex and curr.startIndex
                    const sepStart = prev.endIndex;
                    const sepEnd   = curr.startIndex;
                    if (sepStart <= offset && sepStart > lastEnd) {
                        lastEnd = sepEnd > offset ? sepEnd : sepEnd;
                    }
                }
            }
            for (let i = 0; i < node.childCount; i++) {
                walk(node.child(i));
            }
        }
        walk(tree.rootNode);
        return lastEnd;
    }

    const pipeEnd = findLastPipe(tree, cursorOffset);
    if (pipeEnd > 0) {
        pipeBefore = original.slice(0, pipeEnd);
        pipeAfter  = original.slice(pipeEnd).replace(/^\s+/, "");
    }

    // Word-split the after-pipe portion. Trim leading whitespace but preserve
    // trailing empty element for cases like "bu " (cursor after space).
    const trimmed = pipeAfter.replace(/^\s+/, "");
    const cmdWords = trimmed.split(/\s+/);
    if (cmdWords.length === 0) cmdWords.push("");

    // Find node at cursor
    const nodeAtCursor = findNodeAt(nodes, cursorOffset);
    const cursor = cursorInfo(nodes, nodeAtCursor, original);

    // Check if the cursor is inside a command substitution $(...) or process
    // substitution <(...).  If so, use the inner command's context instead of
    // the outer command's.
    let nestedContext = null;
    if (nodeAtCursor) {
        // Walk up the CST to find enclosing command_substitution / process_substitution
        let current = nodeAtCursor;
        // The nodeAtCursor from our flat list doesn't have parent links,
        // so search the tree directly.
        function findEnclosingCmdSubst(tree, offset) {
            function walk(node, result) {
                if (result.found) return;
                if (node.startIndex <= offset && node.endIndex >= offset) {
                    if (node.type === "command_substitution" || node.type === "process_substitution") {
                        result.node = node;
                    }
                    for (let i = 0; i < node.childCount; i++) {
                        walk(node.child(i), result);
                    }
                }
            }
            const result = {};
            walk(tree.rootNode, result);
            return result.node;
        }

        // Re-parse to get the full tree (our nodes list doesn't have parent links)
        // Actually, we already have the tree from the parse above. Let me restructure.
        const enclosing = findEnclosingCmdSubst(tree, cursorOffset);
        if (enclosing) {
            // Extract inner command text from CST children (skipping delimiters)
            // Children are: "$("/"<(" + content + ")"  (last may be MISSING)
            let innerText = "";
            for (let ci = 0; ci < enclosing.childCount; ci++) {
                const child = enclosing.child(ci);
                if (child.type === "$(" || child.type === "<(" || child.type === ">(" || child.type === ")" || child.type === "MISSING") continue;
                // Collect text of all non-delimiter children
                innerText += child.text;
            }
            if (innerText.length === 0) innerText = " ";
            // Include the opening delimiter ($( or <() in pipeBefore so
            // reconstruction produces "cmd $(completion" not "cmd completion"
            const delimLen = enclosing.type === "process_substitution" ? 2 : 2; // $( and <( are both 2 chars
            nestedContext = {
                pipeBefore: original.slice(0, enclosing.startIndex + delimLen),
                pipeAfter: innerText.trim(),
                cmdWords: innerText.trim().split(/\s+/).filter(w => w.length > 0),
            };
            if (nestedContext.cmdWords.length === 0) nestedContext.cmdWords.push("");

            // Re-run pipe detection on the inner text using CST structure
            let innerPipeEnd = 0;
            (function walkInner(node) {
                if (node.type === "pipeline" || node.type === "list" || node.type === "program") {
                    for (let i = 1; i < node.childCount; i++) {
                        const prev = node.child(i - 1);
                        const sepEnd = node.child(i).startIndex;
                        if (prev.endIndex <= cursorOffset && sepEnd > innerPipeEnd) {
                            innerPipeEnd = sepEnd;
                        }
                    }
                }
                for (let i = 0; i < node.childCount; i++) walkInner(node.child(i));
            })(enclosing);
            if (innerPipeEnd > 0) {
                nestedContext.pipeBefore = original.slice(0, innerPipeEnd);
                nestedContext.pipeAfter  = original.slice(innerPipeEnd, enclosing.endIndex - (enclosing.child(enclosing.childCount-1).type === ")" || enclosing.child(enclosing.childCount-1).type === ">" ? 1 : 0)).replace(/^\s+/, "");
                const innerTrimmed = nestedContext.pipeAfter.replace(/^\s+/, "");
                nestedContext.cmdWords = innerTrimmed.split(/\s+/).filter(w => w.length > 0);
                if (nestedContext.cmdWords.length === 0) nestedContext.cmdWords.push("");
            }
        }
    }

    // If cursor is inside a command substitution and the node is an argument,
    // check if it's actually a command name in the inner context
    if (nestedContext && cursor.completeKind === "argument") {
        function isInsideCommandName(t, offset) {
            let result = false;
            function walk(node) {
                if (node.startIndex <= offset && node.endIndex >= offset) {
                    if (node.type === "command_name") result = true;
                    for (let i = 0; i < node.childCount; i++) walk(node.child(i));
                }
            }
            walk(t.rootNode);
            return result;
        }
        if (isInsideCommandName(tree, cursorOffset)) {
            cursor.completeKind = "command";
        }
    }

    // For the command name: the first word of (possibly nested) pipeAfter
    let envVars = "";
    let cmdName = "";
    const wordsForCmd = nestedContext ? nestedContext.cmdWords : cmdWords;
    for (const w of wordsForCmd) {
        if (w.includes("=")) {
            envVars += w + " ";
        } else {
            cmdName = w;
            break;
        }
    }

    // Use nested context (inside $(...) or <(...)) if detected
    const outCmdWords = nestedContext ? nestedContext.cmdWords : cmdWords;
    const outPipeBefore = nestedContext ? nestedContext.pipeBefore : pipeBefore;
    const outPipeAfter  = nestedContext ? nestedContext.pipeAfter  : pipeAfter;

    process.stdout.write(JSON.stringify({
        original,
        nodes,
        cmdWords: outCmdWords,
        pipeBefore: outPipeBefore,
        pipeAfter: outPipeAfter,
        cmdName,
        envVars: envVars.trimEnd(),
        cursor,
        cursorNode: nodeAtCursor ? {
            type: nodeAtCursor.type,
            kind: nodeAtCursor.kind,
            text: nodeAtCursor.text,
            start: nodeAtCursor.start,
            end: nodeAtCursor.end,
        } : null,
        hasError: tree.rootNode.hasError,
    }) + "\n");
});

rl.on("close", () => process.exit(0));

process.stdout.write(JSON.stringify({ ready: true }) + "\n");
