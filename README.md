# Pitch

A reflowing, opinionated code formatter for the Scheme programming language.
[`black`](https://github.com/psf/black) is one influence on its safety and
workflow, not a contract to copy Black's configuration model.

Pitch formats R6RS and R7RS source. The maintained application is written in
R7RS-small and compiled by [Emit](https://github.com/bwbensonjr/emit); the
dialect of the code being formatted is independent of the implementation Pitch
runs on. Chez remains only as an independent development oracle for the
authoritative derived reader and host-reader comparisons.

## Usage

```sh
make pitch-run PITCH_ARGS='--help'  # development door through emit run
make pitch-build                    # standalone build/pitch executable
make install PREFIX=~/.local        # relocatable launcher and private executable
```

Building requires Emit revision
`41c6f43cd60d205230bc2771d2acc7a5142e0826` or newer. The prerequisite includes
the ordinary `(emit filesystem)` library used only by the real host adapter for
directory inspection, symlink classification, and atomic replacement. The
standalone executable and installed command require neither Chez nor Racket.

Pitch formats itself. Run this before committing:

```
make format         # format pitch's own sources in place
make format-check   # the same question without the rewrite
```

`PITCH_FORMAT_SOURCES` in the `Makefile` is the maintained R7RS application
source. Both `src/pitch/reader.sls`, the authoritative reader derived from
laesare, and generated `src/pitch/reader.sld` are deliberately excluded: their
byte-identical generator check and upstream diff own their formatting. Vendored
code is never edited, and tests are outside the application source set.

```
pitch f.sls                 rewrite f.sls in place
pitch src/                  rewrite every Scheme file under src/
pitch --check src/          write nothing; fail if anything would change
pitch --stdout f.sls        write the formatted text to standard output
pitch -                     format standard input to standard output
```

| Option | Meaning |
|---|---|
| `--stdout` | write formatted text to standard output, rewriting nothing |
| `--check` | write nothing; fail if any input would change |
| `--config PATH` | overlay the shipped configuration with an explicit file |
| `--width N` | override the configured page width |
| `--dialect D` | override the configured dialect with `common`, `r6rs`, or `r7rs` |
| `--help` | usage, on standard output |
| `--version` | version, on standard output |

| Exit | Meaning |
|---|---|
| 0 | every input succeeded; under `--check`, nothing would change |
| 1 | an input was refused, or under `--check` would change |
| 2 | a usage error, or a path that could not be read or written |

The three statuses are distinct so that a CI job can tell "this code is
unformatted" from "this invocation is wrong".

### Configuration

Pitch ships its defaults as `default-config.scm`, an installed data file rather
than values compiled into the formatter. A project can overlay width, dialect,
and per-form styles with one explicitly named file:

```scheme
(pitch-config 1
  (width 100)
  (dialect r7rs)
  (styles common
    ((my-let) (_ i? fc* . body)) ; add a project macro
    ((when) (_ . fill))          ; replace an existing rule
    ((cond) remove)))            ; use the generic shape instead
```

```sh
pitch --config pitch.scm src/
```

Configuration is resolved in this order: shipped defaults, the named file, then
explicit `--width` and `--dialect` flags. A common style is inherited by both
dialects; a dialect-specific entry may replace or remove an inherited one.
Pitch does not search the working directory, parent directories, a home
directory, or environment-specific locations. Every input in one invocation
uses the same resolved configuration.

The file is one inert, versioned Scheme datum. Pitch parses it with its own
reader and never passes it to host `read`, `load`, or `eval`. An unreadable or
malformed shipped or user configuration is reported before any source or
standard input is read. Configuration cannot disable safety checks, add a token
normalization, reorder code, change token spelling or comment contents, alter
terminal indentation, or execute code.

**In-place is the default, and it is made safe by the write rules rather than by
a flag.** A file is written only when its formatted text actually differs, so a
run over an already-formatted tree touches nothing — no modification times, no
rebuild storms. A file pitch refuses is left byte for byte as it was. Every write
goes to a temporary beside the target and is renamed over it, so an interrupted
run leaves a file wholly unchanged or wholly replaced.

**Standard input must be named.** `pitch -` or `pitch --stdout` reads it; a bare
`pitch` prints usage on standard error and exits 2 rather than blocking on a
pipe, because an invocation carrying no operand is usually a script whose file
list came out empty. `-` cannot be combined with other operands.

Editors want `pitch -`. A pre-commit hook wants:

```sh
pitch --check --dialect r6rs src/ || exit 1
```

## Principles

- **Reflows from scratch.** Prior line breaks and indentation are discarded and
  layout is re-derived from the line width, with a short list of declared
  exceptions (see [Preserved formatting](#preserved-formatting)).
- **Line-length driven line breaking.** Default width 88.
- **Safety checks on every run.** Output is re-read and compared against the
  input; pitch refuses to write a file whose meaning it cannot prove unchanged.
- **Idempotence.** `pitch(pitch(x)) == pitch(x)`, enforced by the test suite.
- **Bounded declarative configuration.** Width, dialect, and per-form styles are
  inert data validated before source I/O; safety and source meaning are not
  configurable.
- **Pitch never reorders code.** Not top-level definitions, not `case` clauses,
  not quoted lists. Reordering is not formatting.
- **Pitch never rewrites comment contents**, only their placement.
- **Pitch never loses a comment, a `#;` form, or a `#| |#` block.** Comment loss
  is the defining flaw of every datum-based Scheme pretty-printer.

## Architecture

```
source text
  → lossless lexer          (derived from laesare; tokens carry exact source text)
  → token vector            (materialized, so lexer and parser are separable)
  → CST                     (trivia are first-class; concatenation reproduces input)
  → document                (cst->document; where comment placement is decided)
  → cost-based optimal layout   (pretty-expressive / Πe style engine)
  → safety checks           (the output is re-read and compared to the input)
  → formatted text
```

The per-form style table — the SRFI 272 style grammar as the on-disk format —
sits alongside `cst->document`, telling it which shape each form takes. `(pitch
config)` parses and composes external entries; `(pitch style)` contains only the
closed grammar, inert descriptors, and table construction. It imports neither
the CST nor the document algebra, so a table cannot contain a document or a
procedure because the library that defines tables cannot name one.

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
`(pitch layout)`, and `(pitch print)` now drives it: `cst->document` turns a tree
into a document, and `(pitch format)` runs the whole pipeline from source text to
formatted text. The cost objective it ships with is still the reference
implementation's, not pitch's; the one encoding pitch's taste wants a corpus to
tune against.

**The style table covers the R7RS-small and R6RS cores** — about thirty
syntactic keywords, written in SRFI 272's style grammar. Only the grammar is
borrowed: SRFI 272 is a datum printer and explicitly leaves the layout algorithm
unspecified, so what each terminal renders as is pitch's decision. Eleven
terminals collapse onto two facts. Whether a subform is *code* or *data* decides
whether it is looked up at all, which is what stops `(syntax-rules (let) ...)`
laying its literals list out as a `let`; and whether a subform is filled decides
the rest. Anything the table does not describe — a head with no entry, wrong
arity, a comment forcing a break where a style needs one line — falls back to the
generic shape, which is why that shape had to exist and be correct first.

**Under a `'`, the fallback is to fill instead.** A quoted datum is data, so a
long symbol table packs to the width rather than going one element per line. This
changes the fallback only: quoting does not suppress the lookup, so `'(define (f
x) ...)` still takes `define`'s shape and quoted code goes on looking like code.
The rule is ANSI Common Lisp's, where `pprint-fill` is likewise the default for a
list with no entry.

`if`, `and` and `or` have no entry on purpose: the generic shape is already what
everyone writes for them.

The long tail of per-dialect library macros is not chased, and the cost objective
is still the reference implementation's rather than pitch's. Both want a corpus
to argue from.

The port is checked against independent implementations. `make oracle-layout`
renders a corpus through Emit Pitch and Racket's `pretty-expressive` and requires
the text, cost, and taint flag to agree. `make oracle-datum` compares serialized
Emit projections with Chez host-reader output. These are development oracles,
not runtime dependencies; the primary `make test` exercises the shipped target
through Emit and retains Chez only at those explicit oracle boundaries.

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
| 3 | **Idempotence.** `pitch(pitch(x)) == pitch(x)`. | shipped |

All four are wired end to end. `format-source` hands the checks the string the
layout engine returned, and it has no way to hand them anything else: they take
two source *texts* and do not accept a tree. Output that fails a check is not
returned at all — the status names the failing layer and the text is withheld,
because returning output pitch could not verify invites a caller to write it to a
file.

The suite pins that the checks would notice. It takes the formatter's own real
output and shows the same check failing on a mutation of it: a comment deleted, a
bracket flipped, an abbreviation expanded, a numeric lexeme respelled.

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
projections is the named `datum=?` operation backed by Emit's cycle-safe
`equal?`, so `#0=(a . #0#)` needs no second comparator of Pitch's own.

Pitch does not use any host implementation's `read` at runtime — that would make
the guarantee vary by platform. Host readers are used as *test* oracles only:
CI differential-tests serialized `cst->datum` output against Chez today. An
oracle only covers values both hosts represent and syntax it accepts, so datum
labels and Emit's private opaque numeric values rest on direct written
expectations.

### Declared normalizations

Black documents three permitted divergences between input and output. **Pitch's
list is empty.** Bracket shape, radix notation, character names, `#t`/`#true`,
string escape spelling, and identifier spelling are all preserved exactly, so
layer 1 is plain equality with no exemptions. Anything added here must be
argued onto this list and documented.

### Preserved formatting

Layout is otherwise re-derived. Two facts survive, and neither is a set of bytes
carried across — each is re-derived against the code as laid out, which is what
lets it survive a reflow at all.

**Blank-line counts.** At most one consecutive blank line inside a form, at most
two between top-level forms.

**Columns of trailing comments.** A trailing line comment is treated as aligned
when the line immediately above or below it ends in a trailing line comment at
the same column. Such a run is put back at one column in the output, one space
past the widest code in the run — a column computed from the reflowed code, not
the one the source used, since reflowing changes the width that column was
chosen against. A run is left at single spaces if aligning it would push a line
past the page width.

What this means for an adopting project: a *table* of trailing comments
survives, and a *lone* comment padded clear of its code does not. In one
codebase we measured, 388 trailing comments carried two or more spaces, and 105
of them shared a column with an adjacent line; the other 283 collapse to a
single space. If most of your trailing comments are single annotations rather
than columns, expect them to close up. Aligning anything other than trailing
comments — values in a `define` run, arrows in a table of clauses — is a
non-goal.

Whether pitch honors any explicit "keep this broken" signal analogous to black's
magic trailing comma is an open decision — see [`docs/DESIGN.md`](docs/DESIGN.md).

## Dialects

Pitch accepts R6RS and R7RS input. The reader is a permissive union — it never
rejects input valid in either dialect — and the dialect selects only the style
table, the bracket convention, and any dialect-specific output choices.

Today the dialect names a style table and nothing else. The external shipped
configuration defaults it to `common`; a user configuration may change it, and
`--dialect` is the final override. `format-source` receives the resulting
resolved configuration, selects its table at the edge, and passes only that
table to translation. Content sniffing and a magic-comment override do not
exist. File extensions are used to *discover* files during a directory walk and
for nothing else — `.scm` and `.ss` are used by both camps, so a suffix is not
evidence about which standard a file is written in.

`define-record-type` is the one form whose shape genuinely collides — same head,
incompatible arguments — and it is what forces the table to be
dialect-parameterized rather than a single union map. Under the default it has no
entry and falls back to the generic shape, which is the honest answer until pitch
can tell which standard it is looking at.

## Repository layout

```
src/pitch/reader.sls     authoritative derived reader (see header for changes)
src/pitch/reader.sld     generated Emit reader; never hand-edited
src/pitch/cst.sld        CST node types and cst->text
src/pitch/parse.sld      tokenizing and parsing, with diagnostics
src/pitch/diagnostic.sld one defect, anchored to a token; shared vocabulary
src/pitch/lines.sld      what counts as a line ending, defined once
src/pitch/datum.sld      cst->datum, including private opaque numeric values
src/pitch/check.sld      layers 1 and 2, and the combined runner
src/pitch/doc.sld        the document algebra the layout engine resolves
src/pitch/cost.sld       the cost factory interface and the default objective
src/pitch/layout.sld     the Pi-e layout engine
src/pitch/style.sld      the closed style grammar and table construction
src/pitch/config.sld     inert configuration parsing and composition
src/pitch/default-config.scm external width, dialect, and style defaults
src/pitch/print.sld      cst->document: the translation, and comment placement
src/pitch/format.sld     the end-to-end pipeline, and what it refuses
src/pitch/cli.sld        the argument grammar, write rules, and exit status
src/pitch/main.scm       thin standard-R7RS plus (emit filesystem) host adapter
emit-libs.scm            every Pitch library, test program, and program pitch
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
against authoritative `(pitch reader)` under Chez. Pitch-specific `*-r7rs.scm`
programs compile and run as standalone Emit executables; they cover recording,
CST, datum projection, safety checks, document/layout, translation,
configuration, formatting, and the CLI.

`tests/test-cli-r7rs.scm` drives the CLI against an in-memory host rather than the
filesystem, which is what lets it assert the claims that matter in that layer.
They are all negative — a refused file is *not* written, an already-formatted
file is *not* written — and against a real filesystem those mean comparing
modification times and hoping about clock resolution. Against an association
list and a write log they are exact. `tests/test-real-host.sh` then verifies the
ten real adapter operations, and `tests/test-door-parity.sh` compares complete
development/AOT output, status, diagnostics, and filesystem effects.

See [`vendor/laesare/VENDOR.md`](vendor/laesare/VENDOR.md) for the pin and the
refresh procedure.

## References

- [`laesare`](https://gitlab.com/weinholt/laesare) — R6RS/R7RS lexer and reader; the basis for pitch's lossless lexer.
- [`bwbensonjr/laesare`](https://github.com/bwbensonjr/laesare) — mirror carrying the source-text recording patch.
- [`black`](https://black.readthedocs.io/en/stable/the_black_code_style/current_style.html) — an influence on pitch's safety and workflow.
- [Racket `fmt`](https://docs.racket-lang.org/fmt/index.html) — the closest existing analogue for a Lisp.
- [SRFI 272: Pretty Printing](https://srfi.schemers.org/srfi-272/) — source of the style grammar used as pitch's configuration format.
- [*A Pretty Expressive Printer*](https://arxiv.org/abs/2310.01530) — the layout algorithm.
- [Emit](https://github.com/bwbensonjr/emit) — Pitch's supported R7RS-small compiler and runtime.
- [Chez Scheme](https://github.com/cisco/chezscheme) — development-only reader and datum oracle.

## License

Pitch is MIT licensed; see [`LICENSE`](LICENSE). It incorporates MIT-licensed
code from `laesare` by G. Weinholt — see [`NOTICE`](NOTICE).
