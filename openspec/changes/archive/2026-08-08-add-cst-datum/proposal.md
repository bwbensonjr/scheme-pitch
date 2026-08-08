## Why

`add-cst-layer` shipped the tree and layer 0 and deferred this work, citing the
comparator that must terminate on cyclic structure. That risk has now been
measured rather than assumed, and it is much smaller than it looked: if
`cst->datum` produces host Scheme data, the comparator is `equal?`, which R6RS
*requires* to terminate on circular arguments. Chez 10.4.1 does, correctly, for
cyclic pairs and cyclic vectors alike. What remains is graph reconstruction,
which is mechanical and which the vendored reader already demonstrates.

Layer 2 is the weaker of the two output checks and is kept anyway, for one
reason: it runs through a *different code path* from layer 1. If the token
comparator is itself wrong, layer 2 is an independent witness. Building it now,
before either the printer or the token comparator exists, means neither can be
written against it — the witness is independent because it was written first.

There is also a class of input defect that nothing currently detects. The parser
sees brackets and delimiters; it does not resolve datum labels or validate
bytevector elements. `(#1#)` parses clean today, and so does `#vu8(300)`. Those
are real defects that must reach a caller before it decides a file is safe to
format, and `cst->datum` is where they become visible.

## What Changes

- `cst->datum`, projecting a CST to host Scheme data: pairs, vectors,
  bytevectors, symbols, strings, characters, numbers, booleans and the empty
  list. Comparison is then plain `equal?`, with no representation of our own to
  write a comparator for.
- The projection reads `token-value`, the value the lexer already computed, and
  never re-parses `token-text`. This is what makes `#!fold-case` correct for
  free: folding happened at lex time, so the directive folds both sides of a
  comparison identically without `cst->datum` knowing it exists.
- Trivia contribute nothing. A `#;` datum comment is one opaque trivia leaf, so
  the datum it elides is absent from the projection by construction rather than
  by a skip rule.
- Abbreviations expand: a prefix node becomes `(quote x)`, `(quasiquote x)`,
  `(unquote-splicing x)` and so on. The abbreviation token's `token-value` is
  already the expansion symbol.
- Datum labels are reconstructed into a graph, including cyclic ones, scoped per
  top-level datum as the standards require.
- **Defects invisible to the parser become diagnostics**: an unresolvable `#1#`,
  a duplicate `#0=`, a label reference where one cannot be patched in, and a
  bytevector element that is not an octet. `cst->datum` returns
  `(values data diagnostics)` — the shape `parse` already returns — so callers
  merge two lists rather than juggling a list and an exception.
- A layer 2 check built on `equal?`, comparing the data of two texts.
- A differential test asserting `cst->datum` agrees with Chez's own `read` over
  the in-repo corpus and targeted cases.

Explicitly not in scope:

- **Layer 2 cannot run end to end yet**, because there is no printer and so no
  output to re-read. What ships is the mechanism plus tests that exercise it on
  hand-written text pairs differing only in whitespace, and on negative pairs
  that must compare unequal. Wiring it to a formatter is the formatter's change.
- The vacuousness rule still governs the eventual check and is specified here so
  that it constrains whoever wires it up: layer 2 must compare against text
  re-read from the formatter's output, never an in-memory tree against itself.
- Layer 1 token equivalence and layer 3 idempotence.
- The multi-implementation differential matrix. Chibi and Gauche are not
  installed; that matrix belongs to the CI and corpus proposal, which
  `docs/DESIGN.md` §7 identifies as the real cost of dual-dialect support.
- Any change to `src/pitch/reader.sls`, `src/pitch/cst.sls`, or
  `src/pitch/parse.sls`. This change adds a consumer of the CST, not a
  modification to it.
- Annotations. `read-annotated` exists upstream and is untouched; `cst->datum`
  produces plain data, and provenance from datum back to node is not built.

## Capabilities

### New Capabilities

- `cst-datum`: the projection from a CST to host Scheme data — what each node
  kind becomes, how spelling is deliberately discarded, datum-label graph
  reconstruction, and the diagnostics for defects the parser cannot see.
- `datum-equivalence`: the layer 2 check — comparing the data of two sources,
  termination on cyclic structure, what the check must and must not compare
  against, and agreement with a host reader as a test oracle.

### Modified Capabilities

None. `cst-representation`, `cst-construction` and `cst-round-trip` describe the
tree, which this change consumes unchanged.

## Impact

- New `src/pitch/datum.sls` — `cst->datum` and label resolution. Kept out of
  `(pitch cst)` so the tree library stays free of value construction.
- New `src/pitch/check.sls` — the layer 2 check over two sources.
- New `tests/test-datum.sps` — projection, label, diagnostic and layer 2
  coverage, plus the Chez differential test, added to the `test` target in the
  `Makefile`.
- `docs/DESIGN.md` §1 — "Comparator details" says a hand-written comparator over
  our own representation will not terminate on cycles unless written to. That
  premise no longer holds once the representation is host data; the subsection
  should record the decision and the measurement instead.
- `README.md` — the layer 2 row can name `cst->datum` as shipped rather than
  planned.
- `src/pitch/reader.sls` and `vendor/laesare/` untouched. `make vendor-verify`
  and the 196-test baseline must keep passing.
