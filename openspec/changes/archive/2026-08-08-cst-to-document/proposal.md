## Why

Every layer exists and none of them are connected. The reader records positions,
the CST round-trips byte for byte, `cst->datum` projects, layers 1 and 2 compare
two texts, and the Πe engine resolves a document to a cost-minimal layout. What
is missing is the one function that turns a tree into a document — and until it
exists, `README.md`'s architecture diagram has a hole in the middle of it, the
safety checks have no output to re-read, and the cost objective cannot be tuned
because there are no real Scheme documents to tune it against.

This is also where the actually hard problem lives. Every layer below was chosen
so that a comment cannot be lost by accident: trivia are ordinary children, text
is owned by tokens, the leaf sequence is the token vector. All of that protects
the *representation*. Deciding where a comment goes when the line it was on no
longer exists is a decision the translation has to make explicitly, and it is the
decision that has sunk every datum-based Scheme pretty-printer.

## What Changes

- **A translation, `(pitch print)`.** `cst->document` maps a CST node to a
  `(pitch doc)` document. It is a pure function of the tree: no I/O, no state, no
  dialect. Every node kind is covered — document, list, vector, bytevector,
  prefix, leaf, error — and every token's text reaches the document verbatim,
  since the declared-normalizations list is empty and nothing here is entitled to
  respell a lexeme.

- **One generic shape, and the seam a style table will plug into.** Every list is
  laid out by a single default rule: flat if it fits, otherwise the head on the
  first line and the remaining elements aligned beneath the first argument. This
  is not a placeholder to be replaced — `docs/DESIGN.md` §5 requires it as the
  graceful-degradation behavior for any form a table does not match, so it has to
  exist and be correct regardless. The per-form table is a later change; this one
  defines the single point it will be consulted from, so that adding it does not
  mean rewriting the translation.

- **A `verbatim` combinator in `(pitch doc)`, the one addition to an existing
  library.** `text` refuses a line ending, which is right, but a token's text may
  legally contain one: a multi-line string literal, a `#|...|#` block spanning
  lines, a `#;` eliding a datum written across lines. Emitting such a token needs
  the string split at its endings and the pieces joined by breaks that add no
  indentation — indentation inside a string would change its value, and inside a
  comment it would rewrite comment contents. That is one combinator, it needs the
  line-ending set the algebra already owns, and it knows nothing about Scheme, so
  it belongs beside the restriction that makes it necessary rather than as a
  private copy of the ending set in the printer.

- **Comment placement, stated as requirements rather than left to the cost
  function.** A line comment is always followed by a line break, asserted where
  it is emitted — `docs/DESIGN.md` §6 has been asking for this assertion since
  the engine shipped, and this is the change that owes it. A comment on the same
  line as preceding code stays trailing it; a comment on its own line stays on
  its own line. No comment moves across a code token, which is not a taste
  decision but the thing layer 1 will refuse to let us do.

- **Blank lines survive, capped.** At most one consecutive blank line inside a
  form, at most two between top-level forms, per `README.md`'s preserved-
  formatting promise. Every other whitespace leaf is discarded and re-derived,
  which is what "reflows from scratch" means.

- **A pipeline, `(pitch format)`.** `format-source` runs tokenize → parse →
  `cst->document` → `layout`, then runs `check-output` over the input text and
  the text it just produced. An unclean parse is refused rather than formatted,
  as `docs/DESIGN.md` §3 requires. This is the first time the safety checks see a
  real output, and the first time the vacuousness trap the whole design is
  organized around is actually avoidable in practice rather than in principle.

- **Layer 3, idempotence.** `format-source` applied twice equals it applied once,
  asserted over the test corpus. It needs no new mechanism — only a formatter to
  run twice — so it lands here rather than waiting for the CI change.

Explicitly not in scope:

- **The per-form style table.** The SRFI 272 style grammar, the starter table of
  §5, dialect parameterization, and the `define-record-type` collision are data
  and a lookup, and they are a change of their own. Nothing here branches on a
  head symbol; `CLAUDE.md` forbids it and the seam is the whole point.
- **Dialects.** No sniffing, no `--dialect`, no bracket canonicalization. Bracket
  shape is reproduced from the tokens, which is what the empty normalization list
  already requires.
- **A CLI.** No argument parsing, no file rewriting, no exit codes. `format-source`
  is text to text; the program that writes files is separate and small.
- **A tuned cost objective.** The default factory ships as-is. Tuning it —
  the dedented-closer reward in particular — wants a corpus to measure against,
  and measuring is the corpus change's job. This change is what makes tuning
  possible, not what does it.
- **`; fmt: off`.** Still open in `docs/DESIGN.md` §2.

## Capabilities

### New Capabilities

- `cst-translation`: the mapping from CST node kinds to documents — that it is
  total over the node kinds, that every token's text appears verbatim exactly
  once and in order, the default shape for a compound node, that a prefix binds
  tightly to its datum, and the single point at which a per-form rule will be
  looked up.
- `comment-placement`: what happens to each kind of comment — the invariant that
  a line comment is followed by a line break and the assertion enforcing it,
  trailing versus own-line placement, `#|...|#` and `#;` as inline-capable
  documents, and the prohibition on a comment crossing a code token.
- `preserved-formatting`: the one thing that is not re-derived — blank-line runs,
  their caps inside a form and between top-level forms, and the fact that all
  other whitespace is discarded.
- `format-pipeline`: the end-to-end operation — the stages it runs, its refusal
  to format an unclean parse, that it verifies its own output by re-reading the
  text it produced rather than the tree it walked, what it reports when a check
  fails, and idempotence.

### Modified Capabilities

- `document-algebra`: one derived combinator added, `verbatim`, for a string that
  may contain a line ending. Nothing existing changes: `text` still refuses,
  every other constructor behaves identically, and `verbatim` is defined in terms
  of the core like every other derived combinator.

No requirement in `cst-representation`, `layout-resolution`, `layout-cost`,
`token-equivalence`, `datum-equivalence`, or `output-verification` changes;
`output-verification`'s runner is called for the first time, which is what it was
built for.

## Impact

- `src/pitch/print.sls` — new. `cst->document` and the emitters for each node
  kind. Imports `(pitch cst)` and `(pitch doc)`; imports neither `(pitch layout)`
  nor `(pitch check)`, so the translation stays a value-producing function.
- `src/pitch/format.sls` — new. `format-source`, the pipeline, and the refusal
  path. This is the only library that knows about both a CST and a check.
- `src/pitch/doc.sls` — one added export, `verbatim`, and its tests in
  `tests/test-doc.sps`. No existing behavior changes.
- `src/pitch/lines.sls` — new. The line-ending set, defined once. It has four
  consumers now rather than the two that could tolerate a copy each, and
  `check.sls` must not import the layout algebra, so it belongs to none of them.
  `doc.sls` and `check.sls` drop their private copies and import it; a pure
  refactor, confirmed by the existing suite and the differential oracle.
- `tests/test-print.sps`, `tests/test-format.sps` — new, joining `make test`.
  `test-format.sps` is where idempotence and the end-to-end checks live.
- `Makefile` — the two new test programs in the `test` target.
- `docs/DESIGN.md` — §6's owed printer assertion is discharged; §2's blank-line
  rule moves from stated to specified. The open question about whether the
  combined runner grows layers 0 and 3 (§1) is answered: the formatter's pipeline
  owns them, and the runner stays the two-text pair.
- `README.md` — the architecture diagram's middle stage stops being aspirational;
  layer 3 moves from planned to shipped; the note that layers 1 and 2 are not
  wired end to end comes out.
- `src/pitch/reader.sls`, `vendor/laesare/`, and every existing library: untouched.
