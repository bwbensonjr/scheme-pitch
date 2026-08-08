## Why

The reader is finished: every token carries its exact source text, its offset
span, and its line and column span, and concatenating token text reproduces the
input byte for byte. That guarantee currently stops at a flat sequence. Nothing
above it knows that `(` and `)` bracket a list, that `'` prefixes the datum after
it, or that a comment sits between two elements rather than before both.

Every remaining layer needs the tree. The style table dispatches on a form's head
symbol, which requires knowing what a form is. The layout engine assigns costs to
nested groups. `cst->datum` walks structure. None of them can be designed, let
alone written, against a token vector.

The tree is also where losslessness stops being inherited and starts being
something we can lose. The token sequence is lossless because the lexer
accounts for every character; a tree is lossless only if its construction throws
nothing away. `docs/DESIGN.md` §3 chose floating trivia specifically so that
"concatenate the children" stays true by construction rather than by discipline,
and this change is where that claim gets a test attached to it.

## What Changes

- A CST representation. Leaf nodes hold a reader token. Interior nodes hold an
  ordered child sequence. Whitespace and comments are ordinary members of that
  sequence, not fields attached to a neighboring token — the model `DESIGN.md` §3
  settles, and the reason concatenation is trivially total.
- **Tokens own their text.** A leaf's text is the token's `token-text`; offsets
  and line/column remain on the token for diagnostics but are not the authority
  for output. This closes the "Text ownership" question left open in `DESIGN.md`
  §3. The reader already allocates a text string per token, so the alternative —
  root-held source plus spans — saves nothing unless the reader also stops
  recording text, and it would force the source string to be threaded through
  every printer and checker and retained after the port is closed.
- A `tokenize` step producing an explicit token vector, and a parser that
  consumes that vector. The intermediate artifact is deliberate: layer 0 and the
  future layer 1 token-equivalence check then compare against the same
  inspectable object, and a parser bug is distinguishable from a lexer bug by
  looking at it.
- Node kinds covering everything the lexer can emit: lists (distinguishing
  bracket shape), vectors and bytevectors as reflowable list-like nodes rather
  than opaque data, abbreviation prefixes retaining their `'`/`` ` ``/`,`/`,@`
  and syntax-flavored tokens, datum-label prefixes (`#0=`) and references
  (`#0#`), improper tails carrying the `.` as a token, and atoms.
- `#;` datum comments stay opaque: one leaf whose text spans the marker,
  intervening atmosphere, and the commented datum. The lexer has already made
  this choice and reflowing inside would require re-lexing.
- Error nodes for malformed input. The parser is tolerant — it always returns a
  tree, because a formatter is run from editors on half-typed buffers — and marks
  the tree unclean. Refusing to format is a property of the tree, available to
  the CLI when there is one.
- `cst->text`, and the layer 0 check built on it: parse a source, serialize the
  tree, compare to the original bytes.

Explicitly not in scope:

- `cst->datum` and layer 2. Datum labels make it graph reconstruction, which
  drags in a comparator that must terminate on cyclic structure. That is a
  separable problem with its own risk and deserves its own proposal.
- The layout engine, the style table, and any printing that changes whitespace.
  Nothing here reflows; `cst->text` reproduces, it does not format.
- Layer 1 token equivalence and layer 3 idempotence, both of which need a
  formatter to have something to check.
- The CLI. No entry point, no `--dialect`, no file writing.
- Any change to `src/pitch/reader.sls`. This change consumes the reader's
  published interface and does not extend it.

## Capabilities

### New Capabilities

- `cst-representation`: what a CST node is — the node kinds, trivia as ordinary
  children, leaves holding tokens as the authority for their text, and the
  prohibition on the representation branching on dialect.
- `cst-construction`: tokenizing a source into an explicit token vector and
  parsing that vector into a tree, including bracket matching, improper tails,
  prefix nesting, and the error nodes and cleanliness reporting that malformed
  input produces.
- `cst-round-trip`: `cst->text`, and the requirement that concatenating a tree
  reproduces its input byte for byte — checked against the original source text,
  for well-formed and malformed input alike.

### Modified Capabilities

None. `token-source-recording` and `reader-source-position` describe the reader,
which this change consumes unchanged.

## Impact

- New `src/pitch/cst.sls` — node record types, accessors, and `cst->text`.
- New `src/pitch/parse.sls` — `tokenize` and the token-vector parser.
- New `tests/test-cst.sps` — representation, parsing, error-node, and round-trip
  coverage, added to the `test` target in the `Makefile`.
- `docs/DESIGN.md` §3 — "Text ownership" stops being open and records the
  decision and its reasoning; "Malformed input" and "Node kinds needed" are
  amended to match what the specs settle.
- `README.md` — the architecture block's CST line can state the invariant now
  that it is enforced rather than intended.
- `src/pitch/reader.sls` and `vendor/laesare/` untouched. `make vendor-verify`
  and the 196-test baseline in `tests/test-reader.sps` must keep passing.
