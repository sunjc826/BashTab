---
layout: page
title: Structured Output
permalink: /structured-output/
nav_order: 6
---

# Structured Output (PowerShell-inspired)

BashTab commands can emit **records instead of text**. Instead of parsing
columns with awk/grep, you filter and shape fields with SQL-style cmdlets or
raw jq, and presentation (table vs JSON) is decided automatically at the end
of the pipeline — just like PowerShell's `Out-Default`.

Everything is built on one idea: **JSONL (one JSON object per line) is the
object stream**, and **jq is the engine**. All of it lives in
[`lib/core/bu_core_out.sh`](../lib/core/bu_core_out.sh).

## Quick tour

```bash
# On a terminal, bu commands render tables
$ bu get-command
name                  type    definition                                  synopsis
--------------------  ------  ------------------------------------------  --------------------------------------------
convert-from-lines    source  commands/pipeline/bu-convert-from-lines.sh   Convert line-oriented text to JSONL records
get-command           source  commands/core/bu-get-command.sh              List registered commands and their properties
...

# Piped, the same command emits JSONL — jq is your Where-Object
$ bu get-command | jq -r 'select(.type == "source") | .name'

# SQL-style cmdlets compose the same operations
$ bu get-command | bu where '.type == "source"' \
    | bu select name,verb | bu sort verb

# ...or as a single query
$ bu get-command | bu query-object where '.type == "source"' \
    select name,verb order-by verb

# Grouping and aggregation
$ bu get-command | bu query-object group-by verb agg count order-by count desc
verb         count
-----------  -----
convert-from 2
convert-to   3
format       2
...
```

## The pipeline model

```
producer → recordify → transform → sink
(raw)      (→JSONL)    (JSONL→JSONL)  (→display)
```

| Layer | Core functions | Cmdlets |
|---|---|---|
| Recordifiers | `bu_out_record`, `bu_out_from_tsv`, `bu_out_from_lines` | `bu new-record`, `bu convert-from-tsv`, `bu convert-from-lines` |
| Transforms | `bu_out_where`, `bu_out_select`, `bu_out_sort_by`, `bu_out_group_by`, `bu_out_distinct` | `bu where`, `bu select`, `bu sort`, `bu query-object`, `bu distinct-object` |
| Sinks | `bu_format_table`, `bu_format_list`, `bu_format_json`, `bu_format_jsonl`, `bu_format_tsv` | `bu format-table`, `bu format-list`, `bu convert-to-json`, `bu convert-to-jsonl`, `bu convert-to-tsv` |
| Dispatcher | `bu_out` | `bu out-default` |

The **functions** are the scripting API — pure JSONL in/out. The **cmdlets**
wrap them for interactive use and add two behaviors:

1. **Implicit Out-Default**: every cmdlet pipes through `bu_out`. At the end
   of a terminal pipeline you get a table; anywhere mid-pipeline you get
   JSONL. No explicit formatter needed.
2. **Pipeline-aware completion** (see below).

### Out-Default format resolution

First match wins:

1. Explicit `--format` flag (`auto table list json jsonl tsv`)
2. `BU_OUTPUT_FORMAT` environment variable
3. stdout is a terminal → `table`; otherwise → `jsonl`

### Stream vs buffer

| Behavior | Formatters / stages |
|---|---|
| Streams (O(1) latency) | `jsonl`, `tsv`, `list`, `where`, `select`, `distinct`¹, `table --stream` |
| Buffers all input | `table` (auto-width), `json` (array envelope), `sort`, `group-by` |

¹ `distinct` streams first occurrences but remembers keys seen so far —
inherent to dedupe.

## Authoring structured commands

The pattern — zero forks in the record loop, exactly two jq processes:

```bash
{
    for entry in "${entries[@]}"; do
        printf '%s\t%s\t%s\n' "$name" "$version" "$path"   # builtin printf only
    done
} | bu_out_from_tsv --columns name,version,path | bu_out --format "$format"
```

- Values must not contain tabs/newlines in TSV mode; for arbitrary strings use
  `bu_out_record key="$value"` per record (one jq fork each).
- Expose `--format` (enum `auto table list json jsonl tsv`) and `--columns`
  (comma list, supports `key:Label` display labels) for free via the standard
  `bu_parse_positional` autocomplete DSL — see `commands/bu-get-command.sh`.
- Hints for humans (e.g. "No modules registered") go to **stderr** via
  `bu_log_info` so they never pollute the structured stream.

Register your command's fields so completion can offer them downstream:

```bash
# In your module's preinit script
bu_register_output_fields "bu get-pokemon" name id type hp attack
```

### PowerShell mapping

| PowerShell | BashTab |
|---|---|
| `[PSCustomObject]@{...}` | `bu new-record k=v` / `bu_out_record` |
| ConvertFrom-Csv | `bu convert-from-tsv`, `bu convert-from-lines` |
| Where-Object | `bu where '<jq expr>'` (or raw `jq`) |
| Select-Object | `bu select a,b=version` |
| Sort-Object | `bu sort key [--desc]` |
| Group-Object + Measure-Object | `group-by` + `agg` (flat records, not nested) |
| Select-Object -Unique | `bu distinct-object` |
| Format-Table / Format-List | `bu format-table` / `bu format-list` |
| ConvertTo-Json | `bu convert-to-json` (+ `jsonl`, `tsv`) |
| Out-Default | `bu out-default` (implicit in every cmdlet) |
| `Get-Cmdlet | Select -First 5` | `first 5` in query-object |

## `bu query-object` — SQL in one command

Clause keywords work **bare or dashed** (`select` / `--select`) and in **any
order**; execution always follows SQL logical order:

```
where → group-by → having → select → distinct → order-by → first
```

| Clause | Semantics |
|---|---|
| `where '<jq expr>'` | Pre-group filter, **source** field names. Repeatable, ANDed. |
| `grep 'pattern'` | Search a pattern across any field value of each record (grep of a row). Default regex; `-like`/`-ilike` glob (`*`/`?`, bare = substring); `-i`/`-ilike` case-insensitive. Repeatable, ANDed. |
| `group-by a[,b]` | Collapse to one record per (composite) key. No `agg` = SELECT DISTINCT keys. |
| `agg [name=]func[:field]` | Aggregates, repeatable and/or comma-separated. `count`, `sum:f`, `avg:f` (numeric only), `min:f`, `max:f`, `first:f`, `last:f`, `collect:f` (array of values). Default name: `func_field`. |
| `having '<jq expr>'` | Post-group filter on group/aggregate fields. Repeatable, ANDed. |
| `select a,b=version` | Project/reorder/rename (`new=old`). |
| `distinct` | Dedupe whole records (first occurrence wins, order preserved, key-order canonicalized). |
| `order-by field [--desc]` | Sort by **output** field names (SELECT aliases, like SQL). |
| `first N` | LIMIT; streams, short-circuits slow producers. |
| `--format`, `--columns` | Output control (`--columns` accepts `key:Label`). |

```bash
bu get-command | bu query-object where '.type == "source"' \
    group-by verb agg count,collect:noun having '.count > 1' \
    select v=verb,n=count order-by n desc first 3

# grep a pattern across any field (regex), or glob/case-insensitive:
bu get-command | bu query-object grep '^get-' select name,verb
bu get-command | bu query-object grep -like command select name
bu get-command | bu query-object grep -ilike get-* select name
```

Design notes:

- Records missing a group key form a `null` group.
- `select x distinct` ≡ `group-by x` once sorted; `distinct` preserves
  original order, `group-by` sorts.
- Composition is eval-free: each clause is a function stage, absent clauses
  are `cat`.

## Tables

`bu_format_table` (buffered, the default sink):

- Column widths from data, then widest columns shrink until the table fits
  `$COLUMNS`; overflow truncated with `…`.
- Header is bold on a terminal; rows are right-trimmed (no trailing spaces).
- `--columns a,b:Label` — order/select fields, rename headers.
- `--colors name=green,version=yellow` — per-column color (keys, not labels).
- `--style name` — table border/separator style (see below); default
  `classic`, overridable via `BU_TABLE_STYLE`.
- `--stream` — emit immediately with proportional widths from `$COLUMNS`
  (requires `--columns`). Use for large/slow streams.
- Empty input → no output (PowerShell semantics).

### Table styles

`bu format-table --style <name>` (or `BU_TABLE_STYLE=<name>`) picks a
border/separator look. `classic` (bold header, dashed underline, two-space
gutter) is the default and unchanged. The rest:

| Style | Look |
|---|---|
| `plain` | Padded columns only — no header underline, no bold |
| `ascii` | `+`/`-`/`\|` box |
| `unicode` | Single-line box-drawing (`┌─┬┐ │ ├┼┤ └┴┘`) |
| `double` | Double-line box-drawing (`╔═╦╗ ║ ╠╬╣ ╚╩╝`) |
| `clickhouse` | ClickHouse `PrettyCompact` — single-line box, no header rule |
| `markdown` | `\| a \| b \|` + `\|---\|---\|` header (GitHub-flavoured) |
| `mysql` | `+----+` borders between every row |
| `psql` | Postgres-style `-+-` header separator only |

Styles are registered in `__BU_TABLE_STYLES` (a name → JSON-descriptor
assoc) and extended with `bu_register_table_style <name> <descriptor>`,
e.g. from a module preinit script. A descriptor sets `left`/`vsep`/`right`
(line wrappers) and optional `top`/`hsep`/`rsep`/`bottom` rule specs
(`{left,char,join,right,min,pad}`) plus `header_bold`.

`bu_format_list` renders `key : value` blocks — good for wide records on
narrow terminals.

## Pipeline-aware completion

After a pipe, field names of the producer's records are offered:

```bash
bu get-command | bu select <TAB>     # name verb noun namespace type definition synopsis fields stage input output requires_all requires_any module shadows shadowed_by
bu get-command | bu select name,<TAB>  # comma-aware: the remaining fields
bu get-command | bu where <TAB>      # .name .verb .noun .namespace .type .definition .synopsis .fields .stage .input .output .requires_all .requires_any
```

Sources, in order:

1. **Static registry** `BU_OUT_PRODUCER_FIELDS` (longest producer-prefix
   match, so flags and later stages don't break it). Seeded for the builtins;
   extend with `bu_register_output_fields`.
2. **Opt-in probing**: `BU_OUT_PROBE_PIPELINE=true` plus the producer head in
   `BU_OUT_PROBE_COMMANDS` executes the producer as typed and reads keys off
   the first JSONL record. Off by default — it runs user-typed text.

Producer text is resolved from the completion bindings via dynamic scope
(`command_line_front_before_pipe` for the legacy parser, `pipe_before` for
tree-sitter), with a `COMP_WORDS` pipe-walk fallback.

### Command completion after a pipe

At the command position after a pipe (`bu get-command | <TAB>`), candidate
commands are filtered by compatibility with the upstream stream:

- **Format** — a command is offered only if its `input` format token matches
  the upstream `output` (e.g. after `bu convert-to-tsv`, jsonl consumers like
  `bu select` are hidden; `bu convert-from-tsv` and `bu convert-from-lines`
  remain). Unknown formats are never filtered out — only positively-known
  mismatches are hidden.
- **Fields** — a command with a `# Requires-All:` contract is offered only when
  the upstream producer's fields are statically known to include every
  required field; a `# Requires-Any:` contract is satisfied when at least one
  is present. Static resolution uses multi-stage analysis, the field
  registry, and `# Fields:` headers (no producer execution).

### Static pipeline validation

`bu validate-pipeline '<pipeline>'` statically checks a pipeline's field
references and reports any field a stage reads that is not produced
upstream — the runtime analogue of the completion filter:

```bash
bu validate-pipeline 'bu get-command | bu sort madeup'   # {"field":"madeup"}
bu validate-pipeline 'bu get-command | bu select name'   # (no output = valid)
```

Only structurally-parseable reads are checked: `sort`/`select`/`where`/
`group-by` field arguments and `# Requires-All:`/`# Requires-Any:` contracts.
Raw jq expressions, `order-by` aliases, and `grep` patterns are skipped;
unknown producers make validation skip rather than report false positives.

### Inferred output schema

`bu get-shape <producer>` runs a producer once and infers the record shape:
one record per field with its observed JSON type(s), whether it is present
on every record, and presence/null counts:

```bash
bu get-shape get-command    # name/type/types/required/count/null_count per field
```

Declared fields from the producer's `# Fields:` header are listed first (in
declared order), even when the producer emitted no records; inferred-only
fields follow. This is the type-level complement to the name-only `# Fields:`
header — types are inferred, never hand-authored.

### Runtime strict mode

`BU_OUT_STRICT=true` makes pipeline consumers (`# Pipeline: consume`)
validate the first incoming record against their `# Requires-All:` /
`# Requires-Any:` contract and warn to stderr when it is unsatisfied, instead
of silently producing empty output:

```bash
printf '{"index":1}\n' | BU_OUT_STRICT=true bu remove-git-tag
# WARN  ... [remove-git-tag] needs field(s) [name] not present in upstream record
```

Records are always passed through unchanged, so strict mode only adds
diagnostics; it never alters the stream. Off by default (a plain `cat`).

### Alias merging in option completion

Case-pattern alternatives equal modulo leading `-`/`+` and case
(`--select|select|SELECT`) collapse into one row: the **first** form wins
(the row switches to a typed prefix so `compgen` keeps it), metadata lists
`aka <other forms>`, and using any form excludes the group. Alternatives that
differ after normalization (`-v|--verb`, `--json|--yaml`) stay separate rows.
Put the preferred insert form first in the pattern.

### Multi-word verbs

Command name parsing honors `BU_MULTI_WORD_VERBS` (default `convert-to`,
`convert-from`), longest match first — `bu-convert-to-jsonl.sh` registers
verb=`convert-to`, noun=`jsonl`. Extend the array for custom multi-word verbs.

## Configuration reference

| Variable | Default | Purpose |
|---|---|---|
| `BU_OUTPUT_FORMAT` | *(empty)* | Force output format when `--format auto` |
| `BU_TABLE_STYLE` | `classic` | Default table style. `plain`, `ascii`, `unicode`, `double`, `clickhouse`, `markdown`, `mysql`, or `psql` (see [Table styles](#table-styles)). Overridden per-call by `--style`. |
| `BU_TABLE_PAGER` | *(empty)* | Pager for tables. `preset:less` → `less -R`, `preset:bat` → `bat --paging=always`, `preset:never` → cat, or a raw command like `less -R`. Empty disables. |
| `BU_OUT_PRODUCER_FIELDS` | builtins | Assoc: producer prefix → field list |
| `BU_OUT_PROBE_PIPELINE` | `false` | Master switch for live probing during completion |
| `BU_OUT_PROBE_COMMANDS` | *(empty)* | Assoc allowlist of probe-safe producer heads |
| `BU_PIPELINE_CONTRACT_WARN` | `true` | Scan-time warnings for commands missing a `# Pipeline:` header or field contract (`false` silences) |
| `BU_MULTI_WORD_VERBS` | `convert-to convert-from` | Multi-word verb list for name parsing |

**Dependency**: `jq` (≥1.6) is required for all of the above; the module
checks at source time and errors with install instructions otherwise.

## Command discovery and the `# Synopsis` convention

Every command may declare a static one-line description via a `# Synopsis:`
comment in the first 30 lines of its script file:

```bash
#!/usr/bin/env bash
# Synopsis: List registered commands and their properties
```

Rules:
- One sentence, imperative, <100 characters, no trailing period.
- Plain text only — no variable interpolation, no command substitution,
  no ANSI color codes. The text is extracted verbatim.
- First match within the first 30 lines wins; scanning stops there.
- Non-file commands (aliases, functions) get synopses from the registry
  (set via `--synopsis` on registration functions). An alias without a
  registered synopsis has an empty synopsis; its expansion is exposed as
  the `definition` field of `bu get-command`.

### Pipeline contract headers

Command scripts declare their pipeline behavior with `# Key: value` headers
in the same first-30-lines block. All of them are read by a single shared
header parser (`__bu_command_header_get`), so adding a header is cheap and
needs no central registry.

```bash
#!/usr/bin/env bash
# Pipeline: codec            # stage effect: producer | passthrough | project |
                            #   query | transform | consume | standalone | sink |
                            #   codec | recordify_tsv | recordify_lines |
                            #   recordify_new | recordify_jc
# Requires-All: host port   # (optional) EVERY field must be present
# Requires-Any: unit name    # (optional) at least ONE field must be present
# Fields: name path version  # (optional) output fields this producer emits
```

- `# Pipeline:` — the pipeline stage effect. `input`/`output` format tokens
  in `bu get-command` are derived from it (and, for `codec`, from the noun:
  `convert-to-json` → `jsonl → json`). Function/alias commands that have no
  file register via `bu_register_stage_effect` instead.
  - `producer` — `none → jsonl`: emits records from its own data sources.
  - `transform` — `jsonl → jsonl`: consumes records and emits its own result
    records (output schema = its own `# Fields:`, falling back to input).
  - `consume` — `jsonl → none`: acts on each record, no stream out.
  - `standalone` — `none → none`: participates in no pipeline at all.
- `# Requires-All:` — field names a cmdlet must ALL receive on piped JSONL
  (AND; surfaced in `bu get-command` and the `--help` PIPELINE section).
- `# Requires-Any:` — field names a cmdlet accepts ANY one of (OR; the
  structural-typing fallback, e.g. services reading `.unit // .name`).
- `# Fields:` — output field names a producer emits, used for pipeline-aware
  completion after a pipe.

### Agent and script integration

Agents and scripts should enumerate capabilities via:

```bash
bu get-command --format jsonl
```

Each record includes all sixteen fields:

```json
{"name":"get-command","verb":"get","noun":"command","namespace":"bu",
 "type":"source","definition":"/path/to/commands/core/bu-get-command.sh",
 "synopsis":"List registered commands and their properties",
 "fields":"name verb noun namespace type definition synopsis fields stage input output requires_all requires_any module shadows shadowed_by",
 "stage":"producer","input":"none","output":"jsonl","requires_all":"","requires_any":""}
```

- `definition` — what the name resolves to: the script path for `execute`/`source`
  commands, the function name for `function` commands, or the full expansion spec
  for `alias` commands (e.g. `query-object --where {...}`)
- `synopsis` — one-line description (static, safe to parse)
- `fields` — output fields this command produces (space-joined, for pipeline composition)
- `stage` — pipeline stage effect: `producer`, `passthrough`, `project`, `query`,
  `transform`, `consume`, `standalone`, `sink`, `codec`, `recordify_*`, or empty
  if unregistered
- `input` / `output` — stream format tokens (`jsonl`, `json`, `tsv`, `csv`,
  `text`, `base64`, `display`, `none`): what the cmdlet accepts as pipeline
  input and what it emits. Derived from `stage` (and, for `codec`, the noun)
- `requires_all` — fields the cmdlet must ALL receive from upstream
  (`# Requires-All:` header, AND), space-joined
- `requires_any` — fields the cmdlet accepts ANY one of (`# Requires-Any:`
  header, OR), space-joined

This is a single fast call (~7ms awk scan) that gives agents a complete
manifest of available commands — no per-command `--help` forks needed.

New commands created with `bu new-command` get a placeholder `# Synopsis:` line
in the template so they never ship without one.

## Testing

`test/out_test.bats` (126 tests, run via `./bu_run_tests.sh`):

- All assertions are TTY-independent: captured stdout is a pipe, so
  Out-Default deterministically resolves to JSONL and headers are unbolded.
- Terminal behavior is covered with a real pty via `script(1)`.
- Completion is tested end-to-end through `bu_autocomplete_get_autocompletions`
  with binding locals (`command_line_front_before_pipe`, `pipe_before`)
  simulated per test.
