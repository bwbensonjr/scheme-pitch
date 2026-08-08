# Pitch design decisions

Decisions and open questions that the README states without justifying. This is
the pre-specification record; OpenSpec proposals should draw from it and, where
they settle an open question, amend it.

## 1. Safety checks

### Why not datum equivalence alone

Black reparses its output and compares ASTs. The direct translation to Scheme —
compare `(read input)` with `(read output)` using `equal?` — is much weaker than
it appears, because `read` destroys exactly what a formatter must preserve. All
of the following pass a datum comparison:

- every comment deleted
- a `#;` datum comment moved so that it elides a different form
- `[` rewritten to `(` throughout
- `'x` expanded to `(quote x)`
- `#xff` rewritten as `255`, `1E10` as `10000000000.0`
- `"\x41;"` rewritten as `"A"`

Datum equivalence catches exactly one class: the printer emitted text that
re-lexes differently. That class is real and dangerous — a dropped space merging
`(- 1)` into `(-1)`, `(a . b)` printed as `(a .b)`, a line break inside a string,
a lost closing paren — but it is narrow.

### The layers

- **Layer 0 — round-trip.** With formatting disabled, concatenating the CST
  reproduces input byte for byte. Validates losslessness independently of any
  formatting, and against the original bytes rather than against another
  artifact of our own reader.
- **Layer 1 — token equivalence (primary).** Re-lex the output text; compare
  token sequences with whitespace filtered out and comments retained. Strictly
  stronger than layer 2: the token sequence includes every delimiter, so it
  determines the parse tree and hence the datum. Catches comment loss, bracket
  flips, and abbreviation expansion, none of which layer 2 sees.
- **Layer 2 — datum equivalence.** Via our own `cst->datum`. Kept despite being
  weaker because it runs through a *different code path*: if the token
  comparator itself is wrong, layer 2 is an independent witness.
- **Layer 3 — idempotence.** `pitch(pitch(x)) == pitch(x)` across the corpus.

### The vacuousness trap

The check has content only if the output is **re-read from
text**. Applying `cst->datum` to the same tree before and after
formatting compares a value to itself — a formatter only changes
layout and trivia, so the projection is identical by construction and
the check passes regardless of how badly the printer
misbehaved. Black's `--safe` does not reuse its in-memory tree either;
it reparses the string it printed.

### Host readers

Do not depend on an implementation's `read` at runtime — the guarantee
would then vary by platform, since Chez accepts constructs Chibi
rejects and vice versa. Host readers are excellent *test* oracles: CI
asserts that `cst->datum(read-cst(f))` is `equal?` to what Chez,
Chibi, and Gauche each produce from `(read f)` over the corpus. Three
independent implementations agreeing is strong evidence the reader is
right, and it validates the reader without shipping a dependency on
it.

**Status.** Chez is wired up and every in-repo source file matches its `read`
datum for datum. Chibi and Gauche are not installed; the multi-implementation
matrix belongs to the CI and corpus work in §7.

The bound worth remembering: **an oracle covers only what it accepts.** Chez's
`read` rejects datum labels and `#u8(`, so label resolution — the most intricate
part of the projection, and the only part that mutates — gets no oracle coverage
at all and rests entirely on written expectations. A green differential run is
not full coverage, and the tests say so where a reader will see it.

### Comparator details

Comment *attachment* necessarily changes — that is what formatting
is. Comment *order* must not. Compare the comment subsequence in order; do not
compare positions.

The datum comparator must terminate on cyclic structure. `#0=(a . #0#)` is legal
input.

**Settled: `cst->datum` produces host Scheme data, so the comparator is
`equal?`.** R6RS requires `equal?` to terminate on circular arguments, so
choosing host data moves the obligation from us onto the implementation. This
was measured on Chez 10.4.1 before committing to it: two structurally identical
cyclic lists compare `#t`, two cyclic lists differing in one element compare
`#f`, and two identical cyclic vectors compare `#t` — all terminating.

The earlier concern here — that a hand-written comparator over our own
representation will not terminate unless written to — is real but conditional on
inventing a representation. It was the stated reason for deferring layer 2 out
of the CST change, and it does not survive the decision to use host data. A
comparator that must be written to terminate on cycles is exactly the kind of
rarely-exercised code a *checking* layer must not contain, since a check nobody
trusts is worse than no check.

`datum=?` exists as a named wrapper over `equal?` so a future divergence has
somewhere to live. Nothing motivates one today.

Numbers compare by `eqv?`, so exactness is significant: `1` and `1.0` are not
equivalent, which is wanted. `0.0` and `-0.0` are also distinguished on Chez,
and `+nan.0` equals itself. These are recorded by test rather than reasoned
about; layer 2 needs only that both sides of a comparison are treated alike.

### Layer 2 finds what structure cannot show

Beyond being an independent code path, `cst->datum` is the only layer that can
see a class of real defect. The parser knows about brackets; it does not resolve
datum labels or check that a bytevector element is an octet. Both `(#1#)` and
`#vu8(300)` parse completely clean.

These surface as diagnostics on the same channel the parser uses — an
unresolvable reference, a duplicate label, a non-octet bytevector element, and a
reference inside a bytevector, where there is no object slot to patch. A caller
merges the two lists, so cleanliness stays one question with one answer.

The governing rule: **a datum returned with a non-empty diagnostics list must not
be trusted**. That is what licenses the projection to omit what it cannot
represent instead of inventing a placeholder that would compare unequal to
everything.

### Open questions on the checking layers

- Whether `datum=?` should ever diverge from `equal?`. The wrapper exists so the
  answer can change without a spec change; nothing motivates one now.
- Whether provenance from a datum back to the CST node that produced it is
  wanted, so a failed check can report *where* two data diverged rather than only
  that they do. Deferred until a printer exists to produce real mismatches.
- Whether the layer 2 check should return the first differing subtree rather than
  a boolean. Same dependency: worth designing against real failures.
- Layer 2 is not wired end to end, because there is no printer and so no output
  to re-read. The mechanism and its tests exist; connecting them is the
  formatter's work, and the requirement that the check take *texts* rather than
  trees is what will keep that wiring honest.

### Declared normalizations

Empty for v1. Bracket shape, radix, character names,
`#t`/`#true`, string escapes, and identifier spelling are preserved exactly.
This makes layer 1 plain equality with no modulo clause, and lets us claim
"pitch changes only whitespace" without qualification. Every future
normalization must argue its way onto a short, visible list.

## 2. Preserved formatting

Blank-line counts survive: at most one consecutive blank line
inside a form, at most two between top-level forms. (Black's rule, and the
behavior `raco fmt` exposes as `--max-blank-lines`.)

**Open.** The `; fmt: off` / `; fmt: on` escape hatch: syntax, scope (line,
form, region), and whether it exists at all in v1. SRFI 272's in-file
`;; * pp-styles: sym := style` comment is the community precedent for magic
comments and suggests a syntax.

## 3. CST design

### Where trivia live

Two models are available — Roslyn-style leading/trailing trivia
attached to tokens, or trivia as ordinary members of the child
sequence. For a Lisp, comment placement *relative to siblings* is the
entire hard problem, and floating trivia keeps "concatenate children =
source" trivially true, which is the invariant the token tests already
assert one level down.

### Text ownership

**Settled: the token owns the text.** A leaf holds a reader token and its text
is `token-text`. Offsets and line/column stay reachable through the token for
diagnostics, but are never the authority for output.

The alternative — root holds the source string, nodes hold spans — was rejected
on three grounds. The reader already allocates a text string per token, so spans
save nothing unless the reader also stops recording text, which means editing the
derived reader for a benefit we do not need. Spans force the source string to be
threaded through every printer and checker and retained after the port closes.
And spans are wrong for the tree the formatter eventually builds, whose
whitespace leaves correspond to no input span at all.

A consequence worth stating: because text is authoritative and parsed values are
not, `#!fold-case` cannot damage losslessness. It changes `token-value` for
identifiers and leaves `token-text` alone.

The same rule extends to anything derivable. Bracket shape is read from the
delimiter tokens' kinds rather than stored on the list node, and a compound
node's kind is read from its opening token. A second copy of a fact is a second
thing that can be wrong, and disagreeing with the text is the failure this whole
layer exists to prevent.

### `#;` datum comments

**Settled: opaque.** The lexer has already made this choice — `#;(b c)` is a
single token whose text spans the commented datum — so reflowing inside it would
require re-lexing. Preserving the exact text is also what SRFI 272 does (it
makes `#;` handling optional even in its `advanced` layer).

The CST therefore represents a datum comment as one leaf, and classifies it as
trivia. A consequence: an unbalanced bracket *inside* a `#;` datum is a lexical
problem, not a parse problem, and surfaces as a reader warning rather than a
structural error.

### Node kinds

**Settled.** Seven kinds: `leaf`, `document`, `list`, `vector`, `bytevector`,
`prefix`, `error`. List, vector and bytevector share one record and are told
apart by their opening token.

- **Abbreviations.** `'x` is a prefix node retaining the abbreviation token,
  never rewritten to `(quote x)`. Same for `` ` ``, `,`, `,@`, `#'`, `` #` ``,
  `#,`, `#,@`. Trivia between the marker and the datum are children of the
  prefix node.
- **Improper tails.** The `.` is an ordinary child of the list node, with no
  wrapping node and no tail field. Inventing one would create a second
  description of element order that must be kept consistent with the text, and
  would need a home for the trivia that can surround the dot (`(a . ; why\n b)`).
  Since laesare's dotted-pair path is where upstream discards comments, the point
  is to have no separate path to lose them on. A predicate over the child
  sequence answers whether a list is improper.
- **Vectors and bytevectors.** `#(`, `#vu8(`, `#u8(` are open-delimiter tokens
  of distinct kinds, and their children can contain comments. These are
  reflowable list-like nodes. Dropping them to `write` is precisely how the
  lispunion formatter loses comments inside vectors. `#vu8(` and `#u8(` give the
  same node kind — the spelling difference lives in the token, which is how the
  tree stays dialect-agnostic while preserving dialect-specific spelling.
- **Datum labels.** `#0=` is a prefix node and `#0#` is a leaf. `cst->datum`
  must reconstruct the graph, which is where the cyclic-comparator requirement
  above originates.

Interior nodes hold their opening and closing leaves in dedicated fields rather
than as the first and last members of the child sequence. The deciding argument
is error representation: with a dedicated field, an unclosed list has `close` of
`#f` explicitly, whereas "the last child happens not to be a close token" is
ambiguous with a well-formed tree.

### The leaf sequence invariant

**Settled.** Walking a tree's leaves in order yields exactly the token vector it
was parsed from — same tokens, same order, none added, dropped, duplicated or
reordered. This holds for malformed input too.

It is stronger than byte-for-byte round-trip and implies it, given that
concatenating the token vector reproduces the source. It is worth asserting
separately because when it fails it names the token that moved, whereas a
round-trip failure reports a string mismatch and leaves the diagnosis to a human.

### Malformed input

**Settled.** Parsing is tolerant and always returns a tree; a formatter is run
from editors on half-typed buffers. What it does not do is guess: no token is
inserted, dropped or substituted to make a malformed input well-formed. No
closing delimiter is synthesized and no stray one is discarded.

Cleanliness is reported by a **diagnostics list**, not a flag: `parse` returns
the document and a list of diagnostics, and a tree is clean exactly when that
list is empty. A flag would be a second copy of a fact the list already carries.
The CLI, when there is one, **refuses to format** an unclean tree: exit non-zero,
leave the file untouched, report the position. Tolerant *parsing* is required;
tolerant *output* is not.

Diagnostics take their position from the token they concern, never from the
`&source-information` on the reader's conditions. That condition position is
built from `reader-saved-line`/`reader-saved-column`, which per "Position
information" below describe the innermost recursive lexer entry rather than the
token returned — right often enough to be dangerous.

The representations, all of which retain every token involved:

| Input | Representation |
|---|---|
| unclosed `(` at eof | `list` node with `close` of `#f` |
| unexpected `)` | `error` node wrapping the stray leaf |
| `(a]` | `list` node closed by the mismatched leaf, plus a diagnostic |
| `'` at eof | `prefix` node with `datum` of `#f` |
| misplaced `.` | list keeps the dot leaf, plus a diagnostic |
| lexical warning | the token as lexed, plus a diagnostic |

This also resolves the non-minimal-span note in the derived reader's header. On
error-recovery paths a token's recorded text includes a consumed prefix; that is
harmless for round-tripping but would preserve junk if printed. Since malformed
input is never formatted, those tokens are never printed. It does mean an error
node can cover slightly more text than the offending lexeme, which affects the
span shown in a diagnostic but not the token's start position.

### Tokenizing

**Settled.** A `tokenize` step materializes the full token vector, and the parser
consumes that vector rather than streaming from `get-token`.

Layer 0 and the future layer 1 token-equivalence check both want a token
sequence, and materializing it once means they compare against the same
inspectable object. It also makes a lexer bug distinguishable from a parser bug
by looking at the vector. Source files are small enough that holding it is not a
concern.

The reader runs in `rnrs` mode, the permissive union that satisfies every
`assert-mode` check, and with `reader-tolerant?` set, so a lexical error is
recorded as a diagnostic and lexing continues to end of input. Tolerant mode is
what makes the layer honest: in strict mode a lexical error raises and there is
no tree at all, whereas tolerant mode still attributes every character to a
token, so the round-trip guarantee survives malformed input.

**Open.** An in-file `#!r6rs` or `#!r7rs` directive *mutates* `reader-mode`
mid-file, narrowing acceptance, so a file declaring `#!r6rs` and then writing
`#u8(` warns. This is upstream behavior and arguably right — the file declared
itself — but it sits in tension with the permissive-union invariant. In tolerant
mode it degrades to a diagnostic rather than a failure. Overriding it means
editing the derived reader, so it belongs to its own proposal if it is wanted.

**Open.** Whether `tokenize` should expose strict mode. A formatter always wants
tolerant, so not exposing the choice is simpler and can be relaxed later.

### Position information

**Settled.** The reader records position two ways and the CST may use either.
Every token carries a character offset span (`token-start`, `token-end`) and a
line/column span (`token-start-line`, `token-start-column`, `token-end-line`,
`token-end-column`).

Line is 1-based, column is 0-based, and both spans are half-open: the end
describes the character *after* the token. So adjacent tokens share a boundary
position, and a zero-width token's start equals its end. The consequence worth
knowing is that a token whose text ends with a line ending reports an end
position on the following line — every line comment does — so `end-line` is not
"the last line the token occupies".

Columns count characters, consistently with the offsets. They are not LSP
columns, which count UTF-16 code units; exporting to an editor protocol needs a
conversion.

Positions are captured in the `get-token` wrapper, which brackets the outermost
call. They are therefore correct on the `#;`, directive and error-recovery paths,
where the reader's own `reader-saved-line` and `reader-saved-column` describe the
innermost recursive entry rather than the token returned. Do not reach for the
saved fields: they agree with the token for everything that does not recurse,
which is exactly what makes them dangerous.

## 4. Dialects

A dialect is a bundle of three things: a **reader profile** (which
lexical extensions to accept and which to emit), a **style table**, and a
**normalization policy**. The CST and layout engine never see it.

The reader is a permissive union and never rejects input valid in
either standard. Nothing is lost by reading `#vu8` in a file declared R7RS; a
great deal is lost by refusing to.

Selection is by explicit `--dialect`, defaulting to content
sniffing, with a magic-comment override. `detect-scheme-file-type` is already
vendored and implements the sniffing: `import` → R6RS program, `library` → R6RS
library, `define-library` → R7RS library. File extensions are not reliable —
`.scm` and `.ss` are used by both camps. Pitch never silently guesses; a
formatter that guesses wrong and rewrites everyone's brackets is worse than one
that refuses.

### The lexical divergences that matter

| | R6RS | R7RS |
|---|---|---|
| bytevectors | `#vu8(...)` | `#u8(...)` |
| symbols with odd characters | inline `\x41;` escapes only | `\|foo bar\|` |
| booleans | `#t` `#f` | `#t` `#f` `#true` `#false` |
| datum labels | absent | `#0=` / `#0#` |
| case directives | absent | `#!fold-case` / `#!no-fold-case` |
| dialect directive | `#!r6rs` | (none standard) |
| brackets | standard, interchangeable with parens | reserved, but universally accepted |
| character names | `nul` `linefeed` `vtab` `page` `esc` | `null` `escape` |

Everything else — `#;`, `#|...|#`, `#(...)`, numeric syntax, string escapes,
quote abbreviations — is shared. The vendored reader already gates all of this
correctly via `assert-mode`.

`#!fold-case` is preserved as a token and otherwise ignored: pitch reproduces
source spelling rather than interning symbols. The layer 2 check is unaffected,
since the directive appears in both input and output and folds both sides
identically.

### Brackets

R6RS makes `[...]` standard
and its Appendix C gives guidance for using them in binding positions and `cond`
clauses; R6RS-descended communities write them that way. R7RS reserves the
characters and its community writes all-parens. `raco fmt` preserves bracket
shape but normalizes `cond` clauses to `[...]`; SRFI 272 punts, making it a
printer parameter.

The pitch approach for now is **dialect-selected canonical
bracketing**. It is honest that these are two style communities, and
black has precedent in `--target-version`.

## 5. Style tables

SRFI 272's style grammar is the on-disk format.** It is Scheme-native,
already community-vetted, and comes with a registry API (`pretty-style`,
`add-pp-style`, `lookup-pp-style`) and an in-file config comment syntax
(`;; * pp-styles: sym := style`, including inheritance: `my-let-macro := let`).
Adopting it means not inventing notation.

Note that SRFI 272 cannot be the *engine* — it is a datum printer, and it
explicitly leaves the layout algorithm unspecified, which destroys the one
property pitch sells. Only the grammar is borrowed.

### Why a table is needed at all

Layout cannot be derived from structure, because structurally identical forms
want different layouts:

```scheme
(if (null? xs)                    (list (null? xs)
    acc                                 acc
    (loop (cdr xs)))                    (loop (cdr xs)))
```

Both are four-element lists. Only a lookup on the head symbol distinguishes
them. The table is therefore the largest piece of hand-written, taste-dependent
data in the tool, and it *is* the encoded best practice that the "configuration
based on best practices" goal refers to.

### The shape vocabulary is small

`raco fmt`'s `conventions.rkt` has 183 distinct head names but only 14 formatter
functions, and the usage is lopsided: `format-uniform-body/helper N` (24 uses),
`format-define-like` (12), `format-for-like` (12), `format-parameterize` (10),
`format-clause-2/indirect` (5), then one-offs. **183 names collapse to about six
shapes.** scmindent's table is 38 entries of a single integer each — the Emacs
`lisp-indent-function` convention — which is expressive enough for indentation
depth but not for line-breaking, which is why scmindent is an indenter and not a
formatter.

SRFI 272's terminals cover the same six shapes declaratively:

`i` identifier · `d` datum · `e` expression · `f` formals · `l` literals ·
`h` definition head · `dc`/`ec`/`fc`/`lc` datum-, expression-, formals-,
literals-clause · `dc*`/`ec*`/`fc*`/`lc*` lists of those · `body` indented
expression list · `fill` line-filled expression list · `i?` optional identifier

### Starter table

Neither existing table is a usable corpus: scmindent's 38 names are Common Lisp,
and roughly 60% of `raco fmt`'s 183 are Racket-specific. But the R7RS-small core
is finite — about 35 syntactic keywords — so this is an afternoon, not a long
tail. The long tail is per-dialect library macros.

```scheme
;; binding
(define             (_ h . body))
(define-values      (_ f . body))
(define-syntax      (_ i . body))
(define-record-type (_ i f i . body))   ; R7RS shape; judgment call
(lambda             (_ f . body))
(case-lambda        (_ . fc*))
(let                (_ i? fc* . body))  ; i? absorbs named let
(let* letrec letrec* let-values let*-values
 let-syntax letrec-syntax parameterize
                    (_ fc* . body))
;; control
(if                 (_ . body))
(when unless        (_ e . body))
(cond               (_ . ec*))
(case               (_ e . lc*))
(and or             (_ . fill))
(begin delay delay-force (_ . body))
(do                 (_ fc* ec . body))
(guard              (_ (f . ec*) . body))
(set!               (_ i . body))
;; macro / library
(syntax-rules       (_ l . dc*))        ; judgment call
(define-library     (_ d . body))
(import export      (_ . body))         ; taste: body vs fill
(cond-expand        (_ . ec*))
;; R6RS additions
(library            (_ d . body))
(syntax-case        (_ e l . dc*))      ; judgment call
(with-syntax        (_ fc* . body))
(assert             (_ . body))
```

Entries marked as judgment calls are the taste decisions the style guide has to
settle; `import`'s one-per-line-versus-filled is another.

### `define-record-type`

**The one genuine collision**, and the reason the table must be
dialect-parameterized rather than a single union map:

```scheme
;; R7RS
(define-record-type <point> (make-point x y) point? (x point-x) (y point-y set-point-y!))
;; R6RS
(define-record-type point (fields (immutable x) (mutable y)) (protocol ...) (parent ...))
```

Same head symbol, incompatible shapes — `(_ i f i . body)` versus `(_ i . dc*)`.
It appears to be the only such collision in the core of either standard, but one
is enough to settle the architecture.

### Graceful degradation

SRFI 272 specifies that a form not matching its style pattern has
the non-matching part printed as a plain datum. Adopt this. A formatter
encounters `(let)` and `(if)` with wrong arity constantly — in macro-generating
code and in half-saved files — and must never crash or mangle.

### Numeric knobs

SRFI 272's `pp-tab` (body indent relative to the keyword) and
`pp-max-tab` (cap on the extra offset short keywords like `if` induce), plus
width. Plausibly the entire numeric configuration surface.

## 6. Layout engine

The target is a `pretty-expressive` -style engine implementing Πe from
*A Pretty Expressive Printer* (Porncharoenwase, Pombrio, Torlak,
OOPSLA 2023): strictly more expressive than prior printers in the
literature, provably minimizes a user-supplied cost objective,
correctness verified in Lean.

The cost factory is where black's aesthetic preferences get encoded — penalize
overflow, penalize height, reward dedented closing delimiters — rather than in
ad-hoc heuristics. This is the substitution point for style opinions.

**Open.** `pretty-expressive` is Racket. Porting it to R6RS is a real subproject
and should be scoped as its own OpenSpec proposal. Having Racket available (per
`CLAUDE.md`) makes it possible to differential-test the port against the
original on the same inputs.

A structural invariant checked at print time,
not inferred: **a line comment token must always be followed by a line break.**
The layer 1 check does catch violations — swallowed code shows up as missing
tokens — but this is the single most dangerous printer bug in any Lisp
formatter, and it deserves an assertion where it happens rather than a diagnosis
three layers downstream.


## 7. Corpora and CI

Standards documents will not break the formatter; other people's code will.

- **SRFI reference implementations** — the best portable-Scheme corpus. Many
  authors, wide stylistic range, deliberately written to run everywhere, and it
  exercises both dialects.
- **Chibi's `lib/`** — idiomatic R7RS-small, heavy on `define-library`.
- **Gauche's `lib/` and `libsrc/`** — larger and more varied.
- **Chez's `s/`** — large, consistent, R6RS-flavored.
- **Akku packages** (`industria`, `loko`) — real R6RS library code.

For every file: layers 0 through 3, plus the differential `read` comparison
against Chez, Chibi, and Gauche. Layer 0 will fail constantly at first; that is
it doing its job. The matrix runs per dialect, and building that harness is the
real cost of dual-dialect support — not the dialect handling itself.

