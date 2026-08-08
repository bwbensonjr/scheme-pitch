## Why

`(pitch print)` lays out every compound by one generic shape and consults no head
symbol at all, so `cond`, `let`, `define` and `lambda` come out looking wrong
today. That was the correct order to build in — the generic shape is what a form
no table matches must fall back to, so it had to exist and be correct first — but
it means pitch currently has no style. `README.md` says the tool encodes
configuration based on best practices, and the table *is* that encoded best
practice; it is the largest piece of hand-written, taste-dependent data in the
tool and the last stage of the architecture diagram that is not built.

The seam was designed for this. `compound-shape` is one function that ignores its
argument, and the whole point of it existing was that adding the table would be a
lookup rather than a rewrite. This change collects on that.

## What Changes

- **A style grammar, `(pitch style)`.** SRFI 272's style notation is the on-disk
  format, as `docs/DESIGN.md` §5 settles: `(_ h . body)`, `(_ i? fc* . body)`,
  `(_ e l . dc*)`. It is Scheme-native, community-vetted, and adopting it means
  not inventing notation. A style is read from that notation into a shape
  descriptor once, at table-construction time, and a malformed style is an
  assertion violation there rather than a surprise during layout. Only the
  grammar is borrowed: SRFI 272 is a datum printer that explicitly leaves the
  layout algorithm unspecified, which is the one property pitch sells.

- **A layout semantics for every terminal, which SRFI 272 does not supply.** This
  is the substantive design work of the change and it is stated as requirements,
  not left to the cost objective. Each terminal before the tail is a *slot* that
  stays on the opening line; the tail — `body`, `fill`, or a clause list — is laid
  out beneath it, indented two columns from the opening delimiter. Clause
  terminals recurse: `ec*` means every remaining element is itself a list styled
  `(test . body)`. `fill` needs no new combinator, only a per-gap
  `(alternatives space nl)`, so `(pitch doc)` is untouched.

- **`compound-shape` stops ignoring its argument.** It looks the head up in a
  table and returns a shape descriptor; the emitters dispatch on the descriptor.
  No other function in `print.sls` examines a head symbol, which is what makes
  `CLAUDE.md`'s "style tables are data, not code" a question with a one-function
  answer rather than an aspiration.

- **The head is matched by the token's *value*, not its text.** `token-value` is
  the symbol the reader produced, so `|let|` and, under `#!fold-case`, `LET` both
  match `let` — which is what they mean. This narrows an existing requirement:
  the translation still MUST NOT read a recorded offset, line, or column, and
  every character it *emits* still comes from token text, but a token's parsed
  value may now select a layout. Nothing about the empty declared-normalizations
  list changes, because a value influences which whitespace is emitted and never
  which characters are.

- **Three tables, and a dialect argument to select among them.**
  `define-record-type` is the one genuine R6RS/R7RS collision — same head symbol,
  incompatible shapes — and `docs/DESIGN.md` §5 is right that one is enough to
  settle the architecture. `cst->document` and `format-source` take an optional
  dialect naming a table; the default is the shared core, in which the colliding
  form has no entry and therefore degrades to the generic shape. A dialect here
  names a style table and nothing else. Sniffing, `--dialect`, and the reader
  profile and normalization policy that complete the bundle are not in this
  change.

- **The starter table.** The R7RS-small syntactic keywords and the R6RS core, per
  `docs/DESIGN.md` §5's draft, with the entries it marks as judgment calls
  settled and the taste decisions it defers — `import` filled versus one per
  line, `syntax-rules`, `syntax-case` — argued in `design.md`.

- **Graceful degradation, specified.** SRFI 272 has a non-matching form printed
  as a plain datum; pitch's version is that the generic shape is the fallback. A
  head that is not an identifier, a form with too few elements for its style, a
  slot expecting a list that gets an atom, an improper list, and an own-line
  comment landing inside the slot region all fall back rather than crash or
  mangle. A formatter meets `(let)` and `(if)` with wrong arity constantly, in
  macro-generating code and in half-saved buffers.

Explicitly not in scope:

- **A registry API and the `;; * pp-styles:` magic comment.** Both are SRFI 272
  features and both grow the configuration surface `README.md` fixes at width and
  dialect. The grammar remains the on-disk format, so a loader is additive
  whenever it is argued for.
- **Dialect selection.** No content sniffing, no `--dialect`, no CLI. The
  argument exists; choosing its value from a file does not.
- **Bracket canonicalization.** `raco fmt` normalizes `cond` clauses to `[...]`.
  Pitch cannot: the declared-normalizations list is empty and bracket shape comes
  from the delimiter tokens.
- **Cost-objective tuning.** The default factory ships unchanged. The table gives
  the corpus work something worth measuring; it does not do the measuring.
- **`; fmt: off`.** Still open in `docs/DESIGN.md` §2.

## Capabilities

### New Capabilities

- `style-grammar`: what a style is — the SRFI 272 notation pitch accepts, its
  well-formedness rules, that a table is data rather than code, how a head symbol
  is matched to a style, the three built-in tables and the dialect that selects
  among them, and the refusal of a malformed style at construction time.
- `style-layout`: what a style *renders as* — the document each terminal denotes,
  the slot-and-tail structure, body and fill and clause indentation measured from
  the opening delimiter, that a style adds no new alternative the cost objective
  must break ties among, and every degradation path back to the generic shape.

### Modified Capabilities

- `cst-translation`: the requirement that the per-form operation returns the same
  generic shape for every node is replaced by one that it consults a table; the
  requirement restricting what the translation may read is widened from token
  text alone to token text and token values, still excluding every recorded
  position; and the three-shape default becomes the fallback for a form no style
  matches rather than the only shape there is.
- `format-pipeline`: `format-source` accepts an optional dialect and passes it to
  the translation. Every existing stage, refusal, and check is unchanged.

No requirement in `comment-placement`, `preserved-formatting`, `document-algebra`,
`layout-resolution`, `layout-cost`, `cst-representation`, `token-equivalence`,
`datum-equivalence`, or `output-verification` changes. Comment placement in
particular is unaffected by design: a style chooses where breaks may go, and the
comment rules already decide where a comment goes before any shape is applied. A
style that cannot accommodate a comment degrades to the generic shape rather than
moving the comment, because moving it is what layer 1 refuses.

## Impact

- `src/pitch/style.sls` — new. The grammar reader, the shape descriptor, the
  three tables, and the lookup. Imports nothing from `(pitch cst)`, `(pitch doc)`
  or `(pitch reader)`: it maps a symbol to a descriptor and knows about neither
  trees nor documents, which is what keeps the table data.
- `src/pitch/print.sls` — `compound-shape` gains a table and a body; new emitters
  for the slot-and-tail, clause, and fill shapes; the generic shape becomes the
  fallback. `cst->document` gains an optional dialect argument. No other function
  examines a head.
- `src/pitch/format.sls` — `format-source` gains an optional dialect argument and
  threads it. The stage list, the refusals, and the checks are untouched.
- `tests/test-style.sps` — new. The grammar reader, well-formedness refusals,
  lookup, and the dialect split, with no documents involved.
- `tests/test-print.sps` — the styled shapes, each degradation path, and the
  interaction between a style and an interleaved comment.
- `tests/test-format.sps` — idempotence and the safety checks over styled output,
  including pitch's own sources under both dialects.
- `Makefile` — `tests/test-style.sps` joins the `test` target.
- `docs/DESIGN.md` — §5's starter table moves from draft to shipped, its judgment
  calls are settled, and the layout semantics SRFI 272 leaves unspecified are
  recorded. §6's note that the current output should not be read as pitch's
  intended style comes out.
- `README.md` — the architecture diagram's style table stops being the one stage
  not yet built; the paragraph saying every form gets one generic shape is
  replaced.
- `src/pitch/reader.sls`, `vendor/laesare/`, `src/pitch/doc.sls`,
  `src/pitch/cost.sls`, `src/pitch/layout.sls`, `src/pitch/check.sls`: untouched.
