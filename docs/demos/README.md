# Demo coverage and recording

The [demo gallery](../README.md#demos) is a set of short, focused recordings.
The hero clip is a quick tour; each feature clip stands on its own.

## Feature and history audit

Reviewed against `9bbba42` (September 13, 2026 working baseline):

- `957f2b3` (August 22) last refreshed the demo **content**: discovery,
  external completions, help, object pipelines, and interactive queries.
- `e13c0b1` (September 11) changed **startup only**, adding `Hide`/`Show`
  around activation and replacing a hard-coded checkout path. It still used
  a two-second delay. MP4 intermediates are ignored by Git, so both media
  formats need regeneration when the tapes change.
- The sole later commit, `9bbba42`, enabled Unicode tables, a table pager,
  and full tracebacks by default. The new pager requires updated tape input.
- Comparing only `e13c0b1..HEAD` would miss the feature gap. Content review
  uses `git log 957f2b3..HEAD` as well as the current commands and docs.

| Feature | August demo coverage | Updated coverage | Relevant commits |
|---|---|---|---|
| Command discovery, external completion, help | Present | Refreshed hero, external, and help clips | `957f2b3`, `9bbba42` |
| Query clauses, fields, operators, values, connectors | Present | Query clip uses readable comma spacing and module projection | `bf22df9`, `0e0680a`, `347d77f` |
| Tables, JSONL, grouping, aggregates, grep | Present | Bounded output, current Unicode default, double and Markdown styles | `6404a4c`, `9bbba42` |
| File imports and schema-aware completion | Missing | File clip: TSV header completion, numeric filter, grouped count/average | `affe21c`, `8f20b87`, `0b7c470` |
| Pipeline contracts and compatible command completion | Missing | Contracts clip: recordifiers after TSV output | `69a0870`, `a221f23`, `61046b6`, `4744e83` |
| Static field validation and inferred types | Missing | Contracts clip: typo diagnostic, corrected pipeline, `get-shape` | `e020dd3`, `ca8b4bc` |
| Module composition, provenance, precedence, Git state | Text only | Modules clip: devbox + gitshelf, ranked modules and command ownership | `a91a7fa`, `ac2d584`, `3043897`, `870b021`, `41758ef` |
| Reversible line transforms | Missing | Transforms clip: opt-in selector, preview, automatic inverse | `874cad7` |

Some features still have no dedicated recording. These are deliberate
coverage gaps, not claims that every current feature appears in the gallery:

| Feature | Where to explore it / why no clip |
|---|---|
| SSH invocation and remote sessions | `bu invoke-command --help`, `bu enter-remote-session --help`; a useful demonstration needs a configured SSH host (`b118a3f`, `732415f`, `15aa7d0`) |
| Context origins and consumption logging | [Context variables](../context_variables.md); requires a project configuration and consuming command (`a714c8f`) |
| Runtime contract warnings and full tracebacks | [Structured output](../structured_output.md#runtime-strict-mode), `bu get-config`; diagnostics are best shown alongside an intentional failure (`8af2a78`, `650d3bf`) |
| Module requirements, caching, deferred compatibility probes | Module examples and activation code; primarily startup behavior (`92aa4f3`, `38627b5`) |
| Nested multiselect parsing, site hooks, capability resolution | Command-author APIs; need source walkthroughs (`329301e`, `b37a85a`, `b01dc20`) |
| Command shadowing, config/keybinding provenance | Inspect `get-command`, `get-config`, `get-key-binding`; the module clip shows ownership but does not manufacture a collision |
| File metadata, tree-sitter tokenization, command authoring | Existing highlights and guides; outside this refresh's focused pipeline/module clips |

## Regenerate

Install [VHS](https://github.com/charmbracelet/vhs) with `Wait` support
(recordings verified with 0.11.0), `ttyd`, `ffmpeg`, `jq`, `fzf`, and `less`.
Build the Fig specs with the repository's `./setup` before recording the
external-completion clips. VHS also needs a working Chromium installation.

From the repository root:

```bash
docs/render_demos.sh                         # all docs/demo*.tape
docs/render_demos.sh docs/demo-files.tape     # one clip
```

The renderer validates tapes before recording and converts MP4 to GIF with
ffmpeg. Commit GIFs and tape sources together; MP4s are ignored intermediates.
New `docs/demo-*.tape` files are discovered automatically.

Every tape imports [style.tape](./style.tape) first, applying display settings
and hiding capture before any per-clip environment directives. Then
[setup.tape](./setup.tape) sources [setup.sh](./setup.sh) and waits for the
final clean prompt before `Show`.
Activation, configuration, and screen clearing are outside captured frames:
there is no estimated number of seconds to trim afterward. Check the first
frame of **both** MP4 and GIF after rendering.

The setup discards inherited `BU_*` exports, uses a temporary output/cache
directory, disables the command cache to pick up the current checkout, and
uses `preset:less-quit` so small tables stay visible while long ones page.
Activation diagnostics are retained until rendering ends and printed if VHS
fails. The module and transform clips opt into their extra setup with tape
environment variables; Alt+T is not a default binding.

[services.tsv](./services.tsv) is a small, checked-in dataset so file queries
produce useful results on any host. [services.json](./services.json) contains
the same records with numeric latency values for `avg` (TSV imports retain
string values). No network service is required.

When editing interactions, check that fzf selections insert the intended
token, allow enough time for the menu to open, and explicitly exit pagers
before typing the next command. Inspect the first frame, each menu and
result, and the final frame. Run the demonstrated commands as smoke checks;
do not run the full BashTab test suite for a documentation refresh.

The help clip redirects stderr for `--help`: the current autohelp example
formatter emits a dispatch warning when resolving an absolute script path,
even for commands with a `Dispatch: source` header. This recording shows the
generated stdout page; it does not fix that diagnostic. Pipeline clips use
small filtered result sets to avoid existing broken-pipe diagnostics from
early termination of a large command stream.
