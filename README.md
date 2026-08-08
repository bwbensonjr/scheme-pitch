# Pitch

A reflowing, opinionated code formatter for the Scheme programming language,
modelled after [`black`](https://github.com/psf/black) for Python.

Pitch formats R6RS and R7RS source. It is itself written in R6RS Scheme and
developed against [Chez Scheme](https://github.com/cisco/chezscheme); the
dialect of the code being formatted is independent of the implementation pitch
runs on.

## Principles

- **Reflows from scratch.** Prior line breaks and indentation are discarded and
  layout is re-derived from the line width, with a short list of declared
  exceptions (see [Preserved formatting](#preserved-formatting)).
- **Line-length driven line breaking.** Default width 88.
- **Safety checks on every run.** Output is re-read and compared against the
  input; pitch refuses to write a file whose meaning it cannot prove unchanged.
- **Idempotence.** `pitch(pitch(x)) == pitch(x)`, enforced by the test suite.
- **Near-zero configuration.** Width and dialect. That is the whole surface.

## Non-goals

These are prohibitions, not deprioritized features. Each is a failure mode
observed in existing Scheme and Lisp formatters.

- **Pitch never reorders code.** Not top-level definitions, not `case` clauses,
  not quoted lists. Reordering is not formatting.
- **Pitch never rewrites comment contents**, only their placement.
- **Pitch never loses a comment, a `#;` form, or a `#| |#` block.** Comment loss
  is the defining flaw of every datum-based Scheme pretty-printer.
- **Pitch does not grow configuration.** Every additional knob moves it toward
  being a style engine rather than a canonical formatter.

## Architecture

```
source text
  → lossless lexer          (derived from laesare; tokens carry exact source text)
  → token vector            (materialized, so lexer and parser are separable)
  → CST                     (trivia are first-class; concatenation reproduces input)
  → cost-based optimal layout   (pretty-expressive / Πe style engine)
  → per-form style table    (SRFI 272 style grammar as the on-disk format)
  → formatted text
```

In the CST, whitespace and comments are ordinary members of a node's child
sequence rather than trivia attached to a neighbouring token, so concatenating a
tree reproduces its input by construction — there is no attachment decision at
which a comment can be dropped. Parsing is tolerant and always returns a tree,
but never guesses: no token is inserted, dropped, or substituted to repair
malformed input, and a tree is clean exactly when its diagnostic list is empty.

The CST and the layout engine are dialect-agnostic. A dialect is a bundle of a
reader profile, a style table, and a normalization policy, and nothing below
that seam branches on it.

Two references shape the design. [Racket's `fmt`](https://docs.racket-lang.org/fmt/index.html)
proves the whole pipeline works on a Lisp; its 183-form style table collapses to
about six distinct shapes, which is the vocabulary a style grammar needs.
[*A Pretty Expressive Printer*](https://arxiv.org/abs/2310.01530) (OOPSLA 2023)
supplies a layout core that provably minimizes a user-supplied cost objective —
which is where pitch's aesthetic preferences get encoded, rather than in ad-hoc
line-breaking heuristics.

That layout core is ported and shipped, as `(pitch doc)`, `(pitch cost)` and
`(pitch layout)`. Nothing calls it yet: turning a CST into a document is the
printer's work, and it is where comment placement — the actually hard problem —
lives. The cost objective it ships with is the reference implementation's, not
pitch's; the one encoding pitch's taste needs real Scheme documents to tune
against.

The port is checked against the original. `make oracle-layout` renders a corpus
through both `(pitch layout)` and Racket's `pretty-expressive` and requires the
text, the cost and the taint flag to agree — the same discipline the datum
projection uses with Chez's `read`, and for the same reason: written
expectations confirm the cases you thought of, and only an independent
implementation finds the ones you did not. It needs Racket, so it is not part of
`make test`, which runs on Chez alone.

## Safety checks

Scheme's `read` discards comments, bracket shape, quote abbreviations, numeric
lexemes, and string escape spelling, so datum comparison alone is a weak check.
Pitch layers four, and **every one re-reads the output text** — comparing an
in-memory tree against itself is vacuous and would pass regardless of what the
printer did.

| Layer | Check | Status |
|---|---|---|
| 0 | **Round-trip.** With formatting disabled, concatenating the CST reproduces the input byte for byte. | shipped |
| 1 | **Token equivalence.** Re-lex the output; compare token sequences with whitespace filtered out and comments retained in order. Primary check. | shipped |
| 2 | **Datum equivalence.** Via pitch's own `cst->datum`. An independent code path from layer 1. | shipped |
| 3 | **Idempotence.** `pitch(pitch(x)) == pitch(x)`. | planned |

Layers 1 and 2 are not yet wired end to end, because there is no printer and so
no output to re-read. Both take two source *texts* precisely so that whoever
wires them up cannot pass the tree the printer walked.

**Layer 1 is strictly stronger than layer 2**, and the suite pins the difference
rather than asserting it: every one of these passes datum equivalence and fails
token equivalence.

| Change | Layer 2 | Layer 1 |
|---|---|---|
| a comment deleted | passes | **caught** |
| a `#;` deleted, or moved to elide a different form | passes | **caught** |
| `[a b]` rewritten to `(a b)` | passes | **caught** |
| `'x` expanded to `(quote x)` | passes | **caught** |
| `#xff` rewritten as `255` | passes | **caught** |
| `"\x41;"` rewritten as `"A"`, `#\nul` as `#\null` | passes | **caught** |
| a comment moved across a code token | passes | **caught** |

Layer 1 uses the lexer and nothing else, which is what makes the two layers
genuinely independent: a layer 2 failure could come from the lexer, the parser,
or the projection, while a layer 1 failure has one author. It also reports where
it failed — the first differing index and both tokens — because its sequence is
flat.

Layer 2 is kept despite being weaker because it is a separate code path, and
because `cst->datum` is the only layer that sees defects structure cannot show:
`(#1#)` and `#vu8(300)` both parse clean and are reported there. Comparing two
projections is `equal?`, which R6RS requires to terminate on circular arguments,
so `#0=(a . #0#)` needs no comparator of pitch's own.

Pitch does not use any host implementation's `read` at runtime — that would make
the guarantee vary by platform. Host readers are used as *test* oracles only:
CI differential-tests `cst->datum` against Chez today, and against Chibi and
Gauche once the corpus harness exists. An oracle only covers what it accepts, so
datum labels — which Chez's reader rejects — rest on written expectations.

### Declared normalizations

Black documents three permitted divergences between input and output. **Pitch's
list is empty.** Bracket shape, radix notation, character names, `#t`/`#true`,
string escape spelling, and identifier spelling are all preserved exactly, so
layer 1 is plain equality with no exemptions. Anything added here must be
argued onto this list and documented.

### Preserved formatting

Layout is otherwise re-derived, but blank-line counts survive: at most one
consecutive blank line inside a form, at most two between top-level forms.
Whether pitch honors any explicit "keep this broken" signal analogous to black's
magic trailing comma is an open decision — see [`docs/DESIGN.md`](docs/DESIGN.md).

## Dialects

Pitch accepts R6RS and R7RS input. The reader is a permissive union — it never
rejects input valid in either dialect — and the dialect selects only the style
table, the bracket convention, and any dialect-specific output choices.

Selection is by explicit `--dialect`, defaulting to content sniffing (`import`
→ R6RS program, `library` → R6RS library, `define-library` → R7RS library), with
a magic comment override. Pitch never silently guesses on ambiguous input.

## Repository layout

```
src/pitch/reader.sls     derived lossless reader (see header for changes)
src/pitch/cst.sls        CST node types and cst->text
src/pitch/parse.sls      tokenizing and parsing, with diagnostics
src/pitch/diagnostic.sls one defect, anchored to a token; shared vocabulary
src/pitch/datum.sls      cst->datum, the projection to host Scheme data
src/pitch/check.sls      layers 1 and 2, and the combined runner
src/pitch/doc.sls        the document algebra the layout engine resolves
src/pitch/cost.sls       the cost factory interface and the default objective
src/pitch/layout.sls     the Pi-e layout engine
vendor/laesare/          pristine upstream copy, never edited
tests/                   regression baseline plus pitch's own tests
tests/oracle/            one corpus, rendered by pitch and by pretty-expressive
docs/DESIGN.md           design decisions and open questions
openspec/                proposals and capability specs
```

## Vendored code

`vendor/laesare/` holds an unmodified copy of `laesare` at tag `v1.0.3`, kept
alongside the derived reader at `src/pitch/reader.sls` so the changes are always
visible:

```
make test             # reader regression suite plus pitch's own tests
make oracle-layout    # layout engine vs. Racket's pretty-expressive
make vendor-diff      # exact changeset against pristine upstream
make vendor-verify    # confirm vendor/ has not been edited
```

`tests/test-reader.sps` is laesare's own suite, ported only far enough to run
against `(pitch reader)`; it is the evidence that the vendored lexical analysis
still behaves identically. `tests/test-recording.sps` covers what pitch adds to
the reader, `tests/test-cst.sps` the CST layer, `tests/test-datum.sps` the datum
projection, `tests/test-check.sps` the safety checks, `tests/test-doc.sps` the
document algebra, and `tests/test-layout.sps` the layout engine.

See [`vendor/laesare/VENDOR.md`](vendor/laesare/VENDOR.md) for the pin and the
refresh procedure.

## References

- [`laesare`](https://gitlab.com/weinholt/laesare) — R6RS/R7RS lexer and reader; the basis for pitch's lossless lexer.
- [`bwbensonjr/laesare`](https://github.com/bwbensonjr/laesare) — mirror carrying the source-text recording patch.
- [`black`](https://black.readthedocs.io/en/stable/the_black_code_style/current_style.html) — the code style pitch is modelled on.
- [Racket `fmt`](https://docs.racket-lang.org/fmt/index.html) — the closest existing analogue for a Lisp.
- [SRFI 272: Pretty Printing](https://srfi.schemers.org/srfi-272/) — source of the style grammar used as pitch's configuration format.
- [*A Pretty Expressive Printer*](https://arxiv.org/abs/2310.01530) — the layout algorithm.
- [Chez Scheme](https://github.com/cisco/chezscheme) — pitch's host implementation.

## License

Pitch is MIT licensed; see [`LICENSE`](LICENSE). It incorporates MIT-licensed
code from `laesare` by G. Weinholt — see [`NOTICE`](NOTICE).
