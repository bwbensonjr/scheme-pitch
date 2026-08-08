## Why

Every layer below the printer is finished: the reader records positions, the CST
round-trips byte for byte, `cst->datum` projects, and layers 1 and 2 compare two
texts. What is missing is the thing that decides where the line breaks go.

`docs/DESIGN.md` §6 names the target and defers it: a `pretty-expressive`-style
engine implementing Πe from *A Pretty Expressive Printer* (Porncharoenwase,
Pombrio, Torlak, OOPSLA 2023), with the note that "porting it to R6RS is a real
subproject and should be scoped as its own OpenSpec proposal." This is that
proposal.

Πe is chosen over the Wadler/Leijen lineage for a specific reason. Wadler-style
`group` commits greedily: it takes the flat rendering whenever it fits, which is
a local decision that cannot see the cost it imposes downstream. Πe instead
*minimizes a user-supplied cost objective* over the whole document, with the
optimality result verified in Lean. That matters here because the cost factory is
where pitch's aesthetic preferences get to live — penalize overflow, penalize
height, reward dedented closing delimiters — instead of accumulating as `cond`
branches in a printer, which is exactly the failure mode `CLAUDE.md` prohibits
for style rules.

## What Changes

- **A document algebra**, `(pitch doc)`. The Πe core: `text`, `newline`,
  `concat`, `alt`, `nest`, `align`, `reset`, `full`, `cost`, `fail`, plus the
  derived combinators that make it usable (`group`, `flatten`, the append and
  concat families, and the standard constants). Documents are values with no
  knowledge of Scheme syntax, CSTs, or dialects.
- **A resolver**, `(pitch layout)`. The Πe algorithm proper: measure sets kept as
  a Pareto frontier, memoization on the resolution key, and the tainted-measure
  fallback that bounds the search. It returns the layout minimizing the cost
  objective, together with whether the result was tainted and what it cost.
- **A cost factory interface** — five fields: a total order on costs, an
  associative and commutative combine, the cost of text of a given length at a
  given column, the cost of a newline at a given indentation, and the computation
  width. Plus the paper's default factory: squared overflow past the page width,
  then line count, compared lexicographically.
- **Termination and taint are guaranteed, not hoped for.** Once resolution passes
  the computation width, the search stops comparing alternatives and falls back
  to a single *tainted* measure, which is what bounds the complexity. So a
  document that overflows still renders — it just renders without the optimality
  claim, and the result says so via `tainted?`. That is a distinct outcome from
  a document with no layout at all (one built from `fail`, or a `full` followed
  by text), which raises rather than inventing output.
- **`text` may not contain a line ending, and the engine enforces it.** Column
  arithmetic is the entire cost model, so a newline smuggled inside a `text`
  silently corrupts every measure downstream. It also has a specific meaning
  here: a line comment's token text *includes* the newline that terminates it,
  so the printer cannot emit a comment as `text` without first splitting off that
  newline and deciding explicitly what follows. That is `docs/DESIGN.md` §6's
  "a line comment token must always be followed by a line break" enforced by
  construction, one layer earlier than the printer assertion it still needs.
- **A differential oracle against the Racket original.** `make oracle-layout`
  renders a shared corpus of documents through both `(pitch layout)` and Racket's
  `pretty-expressive` and requires the rendered text, the cost, and the taint
  flag to agree. This is the same discipline the datum projection already uses
  with Chez's `read`, and for the same reason: a hand-checked expectation
  confirms the cases we thought of, while an independent implementation
  disagreeing is the only thing that finds the cases we did not.

Explicitly not in scope:

- **No CST knowledge.** Nothing here imports `(pitch cst)` or `(pitch parse)`.
  Translating a CST into a document is the printer's change, and it is where the
  hard problem — comment placement relative to siblings — actually lives.
- **Style tables.** The SRFI 272 style grammar, the starter table, and the
  dialect parameterization from `docs/DESIGN.md` §5 are data consumed by the
  translation, not by the engine. The engine never branches on a head symbol.
- **Pitch's cost objective.** The default factory ships because the paper
  specifies it and the oracle needs a shared one to compare against. The tuned
  objective that encodes pitch's taste — the dedented-closer reward in particular
  — needs real Scheme documents to tune against, and there are none until the
  translation exists.
- **The printer-time assertion that a line comment is followed by a line break.**
  `docs/DESIGN.md` §6 wants it asserted where it happens. It cannot be here: the
  engine has no notion of a comment. It belongs to the printer's change, as
  `token-equivalence`'s proposal already recorded.
- **Layer 3 idempotence and the end-to-end wiring of layers 1 and 2.** Still
  blocked on a printer, not on this.
- **Racket's `special`.** It exists to pass non-string values through a Racket
  output port. Pitch renders to a string. Omitted, and the oracle corpus avoids
  it.

## Capabilities

### New Capabilities

- `document-algebra`: the document language — every constructor, what each means,
  the invariant that `text` contains no line ending, how `align`, `nest` and
  `reset` compose, and the derived combinators defined in terms of the core.
- `layout-resolution`: the resolver — that it returns a cost-minimal layout, the
  measure-set and Pareto-frontier discipline that makes that tractable, the
  tainted fallback and the guarantee that every document renders, the reported
  `tainted?` and cost, the entry points and their parameters, and the requirement
  that the port be differentially tested against the reference implementation.
- `layout-cost`: the cost factory interface, the algebraic laws its fields must
  satisfy, and the default factory's objective.

### Modified Capabilities

None. This change adds three libraries with no dependency on any existing one,
and changes no existing behavior. `document-algebra` and `layout-cost` are pure
data; `layout-resolution` imports only those two.

## Impact

- `src/pitch/doc.sls` — new. The document algebra.
- `src/pitch/layout.sls` — new. The resolver and its entry points.
- `src/pitch/cost.sls` — new. The cost factory record and the default factory.
  Separate from `layout.sls` because the resolver is parameterized over it, and a
  caller supplying a factory should not have to import the resolver to build one.
- `tests/test-doc.sps`, `tests/test-layout.sps` — new, and joining the `test`
  target in the `Makefile`. The paper's worked examples are the spine of
  `test-layout.sps`.
- `tests/oracle/` and `Makefile` — a new `oracle-layout` target running the
  differential comparison. It requires the Racket `pretty-expressive` package,
  which is not currently installed; the target reports how to install it and
  skips rather than failing, following `vendor-verify`'s handling of a missing
  laesare clone. It is not part of `make test`, since `make test` must run
  without Racket.
- `docs/DESIGN.md` §6 — the open question "`pretty-expressive` is Racket, porting
  it is a real subproject" is answered. Record the settled surface, the decision
  to omit `special`, and the taint semantics.
- `README.md` — the layout engine moves from planned to shipped, with the
  qualification that nothing calls it yet.
- `src/pitch/reader.sls`, `vendor/laesare/`, and every existing library and test:
  untouched.
