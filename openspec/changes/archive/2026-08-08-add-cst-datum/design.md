## Context

The CST layer is in place: `parse` returns a document node and a diagnostics
list, `cst->text` reproduces the input byte for byte, and the tree's leaves are
exactly the token vector. Layer 0 is checked over the in-repo corpus.

What is missing is the second, independent projection. `docs/DESIGN.md` §1 keeps
layer 2 despite it being strictly weaker than layer 1, because it runs through a
different code path and is therefore a witness if the token comparator is wrong.
That argument only holds if the two are genuinely independent, which argues for
writing this before either the printer or the token comparator exists.

Constraints from `CLAUDE.md`:

- Pitch never calls a host implementation's `read` at runtime. `cst->datum` is
  ours. Host readers appear only in CI, as differential-test oracles.
- Every check compares against text re-read from the formatter's output.
  Comparing an in-memory tree against itself is vacuous.
- The CST and layout engine never branch on dialect. `cst->datum` is a consumer
  of the CST and inherits that.
- `src/pitch/reader.sls` stays minimally diffed from upstream.

Three decisions were settled before this document: host Scheme data, a
diagnostics list for defects the parser cannot see, and Chez-only differential
testing.

## Goals / Non-Goals

**Goals:**

- A datum projection whose comparator is something we did not write.
- Surface the input defects that currently reach nobody: unresolvable labels,
  duplicate labels, non-octet bytevector elements.
- Independence from layer 1, preserved by construction ordering.
- A layer 2 mechanism specified tightly enough that wiring it to a printer later
  cannot accidentally make it vacuous.

**Non-Goals:**

- Running layer 2 end to end. There is no printer.
- Layer 1, layer 3, the style table, the layout engine, the CLI.
- Provenance from a datum back to the node that produced it.
- Modifying the reader, the CST, or the parser.

## Decisions

### Host Scheme data, so the comparator is `equal?`

`cst->datum` produces pairs, vectors, bytevectors, symbols, strings, characters,
numbers, booleans and the empty list — ordinary values of the host.

The deferral in `add-cst-layer` cited a comparator that must terminate on cyclic
structure. That cost is specific to inventing a representation. R6RS requires
`equal?` to terminate on circular arguments, so choosing host data moves the
obligation onto the implementation. Measured on Chez 10.4.1 before committing to
this:

| Case | Result |
|---|---|
| two structurally identical cyclic lists | `#t`, terminates |
| two cyclic lists differing in one element | `#f`, terminates |
| two structurally identical cyclic vectors | `#t`, terminates |

*Alternative considered:* our own value records, which could carry provenance
back to the CST node that produced each datum. Rejected because the comparator
becomes ours — and a comparator that must be written to terminate on cycles is
exactly the kind of subtle, rarely-exercised code that a *checking* layer must
not contain. A check nobody trusts is worse than no check. Provenance can be
added later as a side table without changing the values.

*Alternative considered:* host data plus an `eq?`-keyed provenance table.
Rejected for now as unbuilt scope; nothing needs it yet, and diagnostics carry
tokens, which is where positions actually come from.

### `datum=?` is a named wrapper over `equal?`

The spec names `datum=?` rather than saying "use `equal?`", so there is one
place to hang a future divergence and one name for tests to exercise. Today it
*is* `equal?`, and a test asserts termination on cyclic input rather than
trusting the standard's promise.

### The projection reads `token-value`, never `token-text`

Every leaf's contribution to the datum is the value the lexer already computed.
`cst->datum` contains no number parser, no string unescaper, no character-name
table.

This is not only about avoiding duplicated work. `#!fold-case` is handled
correctly *for free*: the reader applies folding at lex time, so `token-value`
for an identifier is already folded, and the directive folds both sides of a
comparison identically without `cst->datum` knowing the directive exists. A
projection that re-parsed `token-text` would have to track fold state itself,
and would be a second lexer to keep in agreement with the first.

It also means the deliberate information loss is inherited rather than
implemented. `#xff` and `255` have the same `token-value`; that layer 2 cannot
tell them apart is the documented weakness that layer 1 exists to cover.

### Abbreviations expand; trivia contribute nothing

A prefix node becomes a two-element list of the expansion symbol and the datum,
so `'x` is `(quote x)`. The abbreviation token's `token-value` is already the
symbol, so no table maps `'` to `quote`.

Trivia are skipped, and `#;` needs no rule at all: the lexer made it one opaque
trivia leaf, so the datum it elides is absent from the projection by
construction. This is the payoff for a decision made two layers down.

### Labels are patched in, scoped per top-level datum

Cyclic structure cannot be built without mutation, so label resolution mirrors
what the vendored reader does: a label registers its datum, a reference
registers a patcher, and after the enclosing top-level datum is built each
patcher runs — `set-car!`/`set-cdr!` for pairs, `vector-set!` for vectors.

Scope is per top-level datum, matching the standards and matching upstream,
where `read-datum` allocates a fresh label table per call. `#0=1 #0#` as two
top-level data therefore has an unresolvable reference in the second.

A reference inside a **bytevector** cannot be patched: elements are octets, not
object slots. This is a diagnostic, as it is upstream.

### Defects the parser cannot see become diagnostics

`cst->datum` returns `(values data diagnostics)` — the same shape `parse`
returns, so a caller merges two lists.

| Defect | Visible to parser? | Handling |
|---|---|---|
| `(#1#)` unresolvable reference | no | diagnostic |
| `#0=1 #0=2` duplicate label | no | diagnostic, first binding kept |
| `#vu8(300)` non-octet element | no | diagnostic, element omitted |
| `#vu8(#0#)` reference in bytevector | no | diagnostic |
| `(a (b` unclosed | yes, at parse | projected as if closed |
| `'` prefix with no datum | yes, at parse | diagnostic, omitted |

*Alternative considered:* raising on these. Rejected because it splits input
defects across two mechanisms — a mismatched bracket would be a diagnostic while
a missing label would be an exception, though both are the same kind of thing to
the person who typed the file.

The governing rule, stated as a requirement rather than left implicit: **a datum
whose diagnostics list is non-empty must not be trusted**. That is what licenses
the recovery behaviors above to be lossy. Nothing downstream may compare, format
or otherwise rely on a datum that came with diagnostics.

### `cst->datum` never raises

It handles any tree, clean or not, and where a node cannot be projected it
records a diagnostic and omits it. Parsing already refuses to raise for the same
reason — editors hold half-typed buffers — and a projection that raised would
put that behavior back one layer up.

### Layer 2 compares two sources, and the spec forbids the vacuous form

The check takes two *texts*, parses each, projects each, and compares with
`datum=?`. Diagnostics on either side are a failure.

Taking texts rather than trees is the whole point. The eventual call site is
`check(input-text, formatted-output-text)`, and a signature that accepted trees
would let a caller pass the same tree twice, or pass the tree the printer walked
— which is Black's `--safe` mistake inverted, and which passes no matter how
badly the printer misbehaved. The spec states the requirement on the check's
inputs so that constraint survives into the change that wires it up.

Since there is no printer, tests exercise it on hand-written pairs: texts
differing only in whitespace must compare equal, and texts differing in a datum
must compare unequal. The negative cases matter more than the positive ones — a
comparator that returns `#t` unconditionally passes every positive test.

### Chez as a differential oracle, in tests only

CI asserts `cst->datum` agrees with `(read)` from Chez over the in-repo corpus
and targeted cases. This is a *test* oracle; nothing at runtime calls it, per
the invariant.

Chez is the host and is an R6RS reader, so the in-repo corpus — which is R6RS —
is fully covered. Chibi and Gauche are not installed. Guile and Racket are, but
each diverges from both standards in its reader, so a meaningful share of the
work would become adjudicating whose reader is wrong rather than testing ours.

### Module layout

`src/pitch/datum.sls` as `(pitch datum)` — `cst->datum`, `datum=?`, label
resolution. Kept out of `(pitch cst)` so the tree library holds no value
construction.

`src/pitch/check.sls` as `(pitch check)` — the layer 2 check over two texts.
Separate because it is the first module whose job is verification rather than
representation, and layers 1 and 3 will join it.

## Risks / Trade-offs

**The differential oracle can only cover what the oracle accepts.** Chez will
reject or misread R7RS-only syntax — `#u8(`, `#true`, `#!fold-case` — so exactly
the constructs where the two dialects diverge are the ones it cannot check. →
Scope the differential test to what Chez accepts and cover R7RS-only syntax with
hand-written expectations. Say so in the test, so a later reader does not
mistake the differential pass for full coverage.

**`equal?` edge cases on numbers.** `equal?` defers to `eqv?` for numbers, so
`1` and `1.0` compare unequal, which is correct and wanted. But `+nan.0` and
`-0.0` have implementation-sensitive `eqv?` behavior. → Test both explicitly
rather than reasoning about them; if Chez's answers are surprising, record what
they are instead of working around them, since layer 2 only needs the two sides
of a comparison to be treated consistently.

**Non-octet bytevector elements are omitted, changing the datum's length.** →
Only reachable with a non-empty diagnostics list, and the requirement forbids
trusting such a datum. The alternative — a placeholder element — would compare
unequal to everything and give a worse failure message.

**Layer 2 is weaker than it looks, and shipping it may create false
confidence.** Datum equivalence passes with every comment deleted, every bracket
flipped, every abbreviation expanded. → This is why it is layer 2 and not layer
1. Both the spec and `README.md` should keep saying so; the value here is
independence from layer 1, not strength.

**Untestable end to end until a printer exists.** → Positive tests use text
pairs differing only in whitespace, which is precisely what a formatter produces,
so the mechanism is exercised on realistic input even without the producer.

**Deep or highly shared structure recurses.** → Real source files do not
approach any plausible limit, and Chez's `equal?` handles sharing without
blowing up. Not mitigated further.

## Open Questions

- Whether `datum=?` should ever diverge from `equal?`. Nothing motivates it now;
  the wrapper exists so the answer can change without a spec change.
- Whether provenance from a datum back to its CST node is wanted, for reporting
  *where* two data diverged rather than merely that they do. Deferred until
  there is a printer producing real mismatches to diagnose.
- Whether the layer 2 check should report the first differing subtree rather
  than a boolean. Same dependency: worth designing against real failures.
