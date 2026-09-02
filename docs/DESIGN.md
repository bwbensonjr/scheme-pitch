# Pitch design decisions

Decisions and open questions that the README states without justifying. This is
the pre-specification record; OpenSpec proposals should draw from it and, where
they settle an open question, amend it.

## Emit application boundary

The maintained Pitch application is R7RS-small. Its libraries are
`define-library` units listed in `emit-libs.scm`, and `src/pitch/main.scm` is the
single program entry used by both `emit run` and `emit build pitch`. Existing
R6RS library consumers must migrate to the command or to the R7RS libraries;
there is no maintained R6RS application or compatibility layer.

Emit-specific behavior is confined to the real-host edge. The program imports
the prerequisite `(emit filesystem)` library for directory listing,
directory/symlink classification, and atomic replacement, then supplies those
operations to the host-independent `(pitch cli)` interface. The CST, formatter,
layout engine, and CLI policy do not branch on the compiler.

Chez remains only at explicit independent reader and serialized-datum oracle
boundaries. Racket remains only the layout oracle. Neither is a build-time or
runtime dependency of the standalone application. Valid numeric lexemes outside
Emit's numeric tower are carried by private opaque values: they remain numeric
tokens and lossless source, but are not exposed as host numbers or accepted as
configuration integers or bytevector octets.

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

Do not depend on an implementation's `read` at runtime — the guarantee would
then vary by platform. Host readers are excellent *test* oracles. The current
oracle serializes real source text, independently projects it through Emit
Pitch and reads it through Chez, then compares the two serialized results. This
validates the projection without shipping a host-reader dependency or comparing
an in-memory tree with itself.

**Status.** `make oracle-datum` wires up Chez as that explicit external oracle.
The complete application and its primary Emit suites do not import or invoke a
host reader.

The bound worth remembering: **an oracle covers only what it accepts.** Chez's
`read` rejects datum labels and `#u8(`, so label resolution — the most intricate
part of the projection, and the only part that mutates — gets no oracle coverage
at all and rests entirely on written expectations. A green differential run is
not full coverage, and the tests say so where a reader will see it.

### What layer 1 compares

**Settled.** Filter whitespace tokens; compare every token that remains, in
order, by **kind and text**. Never by position: line and column change under
formatting by definition.

Kind is not redundant with text. The reader's mode changes mid-file on `#!r6rs`
and `#!r7rs`, and its fold-case state on `#!fold-case`, so identical text can lex
differently depending on what preceded it. Comparing kind makes a directive that
moved or vanished visible at the token whose meaning changed, not only where the
directive itself is. `token-value` is *not* compared — it is derived from the
text, and comparing it would import layer 2's weakness, since `#xff` and `255`
share a value.

**One interleaved sequence**, not separate code and comment subsequences. Comment
*attachment* necessarily changes — that is what formatting is — and comment
*positions* are never compared. But comment *order relative to code* must not
change: a comment crossing a code token alters which code it documents, which is
a meaning change rather than a layout one. Interleaving is also what catches a
`#;` relocated to elide a different form, since the `#;` token's place in the
sequence is exactly what says which datum it hides.

This is stricter than "compare the comment subsequence in order" would be, and
deliberately so. If the layout engine ever needs to move a comment across a code
token, that has to be argued for in a proposal rather than quietly permitted by a
comparator.

**A trailing line ending is filtered with the whitespace.** A line comment's
token text includes the line ending that terminates it, so `; c` and `; c⏎` are
different texts differing only in whitespace. The comparator drops one trailing
line ending — recognizing every ending the reader's grammar counts, with the
two-character forms counting as one — before comparing. Only `comment` and
`shebang` tokens can carry one; `#| |#` ends with `|#`, `#;` with the elided
datum, `#!r6rs` with the directive name.

This is **not** a declared normalization and the list stays empty: no comment
content is changed or ignored, and two comments whose content differs still
compare unequal. It stops a tokenization boundary from turning a whitespace
change into a text change, and it lets a printer end a file with a newline even
when the file ends in a comment. Line endings as such are layer 0's business,
where they are compared byte for byte.

### Layer 1 uses the lexer alone

It does not parse and does not project. This is what makes the independence of
the two layers real: layer 2 runs through the lexer, the parser and the
projection, so a failure there has three possible authors, while a layer 1
failure has one.

It costs no coverage. A structural defect in the output — an unbalanced
delimiter, a dropped close paren — changes the token sequence, so the comparison
sees it without the parser being involved.

Layer 1 also reports *where* it failed: the first differing index and both
tokens. The sequence is flat, so this is free, unlike layer 2, where locating a
difference means walking a possibly cyclic graph. Since layer 1 is the check that
will actually fire while a printer is being written, taking the free information
is obviously right.

The datum comparator must terminate on cyclic structure. `#0=(a . #0#)` is legal
input.

**Settled: `cst->datum` produces host Scheme data, so the comparator is
`equal?`.** The supported Emit revision provides cycle-safe `equal?`: two
structurally identical cyclic lists compare `#t`, two cyclic lists differing in
one element compare `#f`, and two identical cyclic vectors compare `#t` — all
terminating. Choosing host data therefore moves the cycle obligation onto a
prerequisite the build probes directly.

The earlier concern here — that a hand-written comparator over our own
representation will not terminate unless written to — is real but conditional on
inventing a representation. It was the stated reason for deferring layer 2 out
of the CST change, and it does not survive the decision to use host data. A
comparator that must be written to terminate on cycles is exactly the kind of
rarely-exercised code a *checking* layer must not contain, since a check nobody
trusts is worse than no check.

`datum=?` exists as a named wrapper over `equal?` so a future divergence has
somewhere to live. Nothing motivates one today.

For numbers Emit can represent, exactness is significant: `1` and `1.0` are not
equivalent, while `0.0` and `-0.0` compare equal and `+nan.0` does not compare
equal to itself. These behaviors are recorded by tests rather than inferred.
Valid numbers Emit cannot represent project to private opaque values. Fresh
reads of the same lexeme compare equal, while alternate opaque spellings may
compare unequal; layer 1 rejects every spelling change before layer 2 can
authorize output.

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
- Whether a comment may ever move across a code token. Layer 1 forbids it. If
  the layout engine needs the freedom, that needs an argument rather than a
  quietly weaker comparator.
- Whether layer 1 should report *all* differences rather than the first. The
  first is what a human fixes; a full diff may be more useful across a corpus
  run, which is the CI change's problem.

**Settled: the formatter's pipeline owns layers 0 and 3, and the runner stays the
two-text pair.** `format-source` in `(pitch format)` tokenizes, parses,
translates, lays out, and then runs `check-output` over the input text and the
text it just produced. Round-trip compares a tree against the input it was parsed
from rather than two texts, and idempotence needs the formatter run twice, so
neither shares the runner's signature; both belong to the thing that has a
formatter to run. Layer 3 is asserted in `tests/test-format-r7rs.scm` over
hand-written cases at four widths and over every one of pitch's own source files.

**The wiring is done, and it is not vacuous.** The check is handed the string
`layout` returned, and `(pitch format)` has no way to hand it anything else,
because `check-output` does not accept a tree. `tests/test-format-r7rs.scm` takes the
pipeline's own real output and shows that the same check fails on a mutation of
it — a deleted comment, a flipped bracket, an expanded abbreviation, a respelled
numeric lexeme. A check nobody has seen fail is one nobody should trust.

**Output that fails a check is not returned at all.** `format-source` reports the
failing layer and returns no text. Returning unverified output under any status
invites a caller to write it to a file, which is the one failure the whole
apparatus exists to prevent.

### Declared normalizations

Empty for v1. Bracket shape, radix, character names,
`#t`/`#true`, string escapes, and identifier spelling are preserved exactly.
This makes layer 1 plain equality with no modulo clause, and lets us claim
"pitch changes only whitespace" without qualification. Every future
normalization must argue its way onto a short, visible list.

**The list stayed empty, and one input is refused to keep it that way.** The
layout engine renders every break as a linefeed. Between tokens that is
harmless — those endings are whitespace, which the formatter re-derives. Inside a
token it is not: a CRLF within a multi-line string literal or a `#| |#` block is
part of a text layer 1 compares, so emitting it as a linefeed would change that
text. `format-source` screens for an interior ending other than a linefeed and
refuses the source, rather than normalizing it onto this list. A CRLF file with
no multi-line token formats normally.

The refusal can be lifted by teaching `(pitch doc)` which ending to render, which
is a change to the algebra and wants its own proposal.

## 2. Preserved formatting

Blank-line counts survive: at most one consecutive blank line
inside a form, at most two between top-level forms. (Black's rule, and the
behavior `raco fmt` exposes as `--max-blank-lines`.)

**Settled and implemented.** A whitespace leaf represents its line-ending count
less one blank lines, capped by where it sits. Leading and trailing blank lines
are dropped and a formatted file ends with exactly one newline. Everything else
in a whitespace leaf is discarded and re-derived.

Two consequences worth stating, because both are the kind of thing that looks
like a bug when first seen. A preserved blank line is emitted as forced breaks,
so a form containing one has no single-line layout at all — which is right, since
collapsing it would delete the blank line just preserved. And the break that
*opens* a blank line is taken at indentation zero, because the resolver indents
after every break and a blank line holding the enclosing indentation as trailing
whitespace is not blank.

**Open.** The `; fmt: off` / `; fmt: on` escape hatch: syntax, scope (line,
form, region), and whether it exists at all in v1. SRFI 272's in-file
`;; * pp-styles: sym := style` comment is the community precedent for magic
comments and suggests a syntax.

**A concrete case now wants it, in this repository.** `usage-lines` in
`src/pitch/cli.sld` is a quoted list of strings, one per line of `--help`
output, and the quoted fallback (§5) packs it: `"" "options:"` end up sharing a
line, and the shape of the list stops mirroring the shape of what it prints.
Grouping expressed by a blank line or a comment survives a reflow, because both
force a break; grouping expressed by a bare line break does not, anywhere in
pitch. ANSI CL's `pprint-fill` packs this identically, so it is the rule working
as specified rather than a defect in it — which is exactly why the remedy is an
escape hatch and not a special case in the layout. Until the hatch exists, this
is the cost, and it is written down here so the next person to read that file
knows it was seen rather than missed.

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
**Settled and shipped.** The CLI **refuses to format** an unclean tree: exit
non-zero, leave the file untouched, report the position. Tolerant *parsing* is
required; tolerant *output* is not.

`(pitch cli)` discharges this, and its refusal path is the same one for all three
statuses — an unclean parse, an unsupported line ending, a failed check — because
`format-source` returns no text under any of them and the driver branches on
success in exactly one place. `tests/test-cli-r7rs.scm` asserts it as a negative: after
a refusal the write log is empty and the file's contents are byte-identical.

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

Selection is resolved at the edge from the external shipped configuration, an
optional explicit user configuration, and finally `--dialect`. The shipped
default is `common`; configuration validation rejects an unknown name before
any source is read. `detect-scheme-file-type` is vendored, but content sniffing
and a magic-comment override do not exist and would require their own change and
refusal semantics. File extensions are not reliable — `.scm` and `.ss` are used
by both camps — so the directory walk uses them only as discovery filters and
never as a dialect signal.

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

**SRFI 272's style grammar is the on-disk format.** It is Scheme-native,
already community-vetted, and comes with a registry API (`pretty-style`,
`add-pp-style`, `lookup-pp-style`) and an in-file config comment syntax
(`;; * pp-styles: sym := style`, including inheritance: `my-let-macro := let`).
Adopting it means not inventing notation.

Note that SRFI 272 cannot be the *engine* — it is a datum printer, and it
explicitly leaves the layout algorithm unspecified, which destroys the one
property pitch sells. Only the grammar is borrowed.

**Settled: the grammar and an explicit configuration loader ship; neither the
registry nor the magic comment does.** `(pitch config)` parses one inert,
versioned Scheme datum with pitch's own reader, composes the shipped defaults
with an optional user overlay, and constructs three immutable tables. `(pitch
style)` owns only the closed grammar, descriptors, and construction operations;
it imports no configuration or I/O library. No configuration datum is passed to
host `read`, `load`, or `eval`.

The shipped width, dialect, and table entries live in
`src/pitch/default-config.scm` rather than in a Scheme library. `--config PATH`
names one optional overlay explicitly; pitch does no project, parent, home, or
environment discovery. The SRFI registry and `;; * pp-styles:` remain separate,
unimplemented mechanisms rather than alternate paths around this boundary.

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
data consumed by the tool, and it *is* the encoded best practice that the
"configuration based on best practices" goal refers to.

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

### What a terminal means, which SRFI 272 does not say

**Settled.** SRFI 272 describes its terminals in terms of *printing* — "print as
identifier", "print as literal" — because it uses them to colour and classify.
What each one denotes as a document is pitch's decision, and it collapses onto
two orthogonal facts.

**Whether the subform is code or data.** `e`, and every element of a `body` or
`fill` tail, is an expression: laid out by the ordinary rules, so a list among
them consults the table for its own head. Every other terminal names data, and
data is never looked up.

That is the load-bearing half. `(syntax-rules (let) ...)` has a literals list
whose head is the symbol `let`; `(let ((if 1)) ...)` has a binding whose head is
the symbol `if`. Laying either out as the form it spells is a visible defect, and
the terminal in that position is exactly what says it is not one. It is also why
`ec*` is not a synonym for `body` even though both give each element a line:
`body` looks its elements up and `ec*` refuses to.

**A quoted datum is a third thing, and it changes the fallback rather than the
lookup.** `'(car cdr cons ...)` is data, but not because a terminal said so —
because the reader did. What follows from that is narrower than it first looks.
Quoting does **not** suppress lookup: `'(define (f x) ...)` keeps `define`'s
shape and `` `(let ((,v ,e)) ...) `` keeps `let`'s, because a quoted datum
frequently *is* a form — a macro expansion under test, an example in a table —
and laying it out as the thing it spells is what makes it readable. What quoting
changes is what happens when no style applies: the fallback becomes the filled
rendering rather than the generic shape, so a data table packs instead of
staircasing off its second element. The property propagates through the whole
quoted subtree, so a sublist of a quoted list packs too.

That is ANSI Common Lisp's rule, arrived at the same way. `pprint-fill` is the
standard default for a list with no dispatch entry, and SBCL prints a quoted
`defun` as a `defun`. The alternatives were surveyed and rejected: `raco fmt`
fills nothing anywhere and produces exactly the staircase this replaces, and
zprint suppresses lookup through the quoted subtree but leaves the layout one
element per line, which fixes the staircase without fixing the file growth.
Suppressing *and* filling — the shape this looked like at first — is a
combination nothing ships, and it would pack quoted code into a paragraph.

The cost of taking CL's rule is worth naming: a data position becomes sensitive
to the style table, so adding an entry for `foo` changes how `'(foo ...)`
renders as data. CL has that property too and lives with it.

Two gaps are recorded rather than closed. The written-out `(quote datum)`
spelling is unaffected, because reaching it would need a branch on a head symbol
and that is prohibited. And of the abbreviations only `'` establishes the
property: a quasiquote holds expression positions at its unquotes, so
"everything below defers evaluation" is not true of it, and a syntax template
exists to spell code.

**What the subform's own shape is.** `i` and `d` impose nothing. `f`, `l` and `h`
name lists of names or literals and are *filled*. A clause terminal says the
element is a list read as `(first . body)` whose first element takes the style
`d`, `e`, `f` or `l`. `fc` and `lc` therefore compile to the same descriptor —
formals and literals are both filled, and nothing further distinguishes them at
the layout level. That is recorded rather than hidden: pretending they differ
would mean two code paths to keep agreeing.

Eleven terminals, three element styles. This is the "183 names collapse to about
six shapes" observation made precise enough to implement.

**A matched style denotes exactly two layouts.** The head and every slot share
the opening line; the tail goes beneath at the body indent; the whole is grouped,
so it is all-flat or fully-broken and nothing between. Worth stating because the
generic shape offers three and needs an argument that two of them can never tie
(§6). A styled form needs no such argument — its two candidates differ in height
*and* in width — so adding an entry removes work from the cost objective rather
than adding a tie for it to break. Measured: `make test` got faster, not slower.

**A clause introduces no rendering of its own.** It is the generic shape with its
first element as the head, which is what Emacs and `raco fmt` both produce. The
alternative — treating a clause as a zero-slot styled form, indenting its body
from the clause's own delimiter — was rejected on familiarity, and it would have
cost a second emitter for no gain.

**A binding list is not a clause, and this distinction was learned the hard way.**
A clause's first element is *distinguished* — it is the test, or `guard`'s
condition variable — so treating it as a head is right. A binding list
distinguishes nothing: `([a 1] [b 2] [c 3])` is a list of peers, and the generic
aligned rendering welds the second element to the first with a space no break may
be taken at, then staircases the rest off the second element's column. Pitch
shipped doing exactly that, and the whole suite was green, because
`style-layout` specified what a starred terminal does in *tail* position and
nothing about what it does in a *slot*.

So there are three headless renderings, not two, chosen by what the compiled
shape says rather than by anything about the node: a shape with a slot is a
clause and takes the generic shape; a shape with no slots and a filling tail
packs; a shape with no slots and a non-filling tail is a peer list and aligns
every element, the first included, at the column after the opening delimiter. A
peer list offers only flat and aligned — hanging exists to separate a head from
its arguments, and there is no head to separate.

A quoted position substitutes the filled rendering for the generic one wherever
no style applies — both in `compound-shape`'s no-entry case and in its non-list
case, since a vector under a quote has no head to look up either. Nothing else
about the dispatch changes, and an improper list still degrades to the generic
shape, because packing has no rendering for a dotted tail and inventing one is
the repair pitch refuses everywhere.

### Starter table

Neither existing table is a usable corpus: scmindent's 38 names are Common Lisp,
and roughly 60% of `raco fmt`'s 183 are Racket-specific. But the R7RS-small core
is finite — about 35 syntactic keywords — so this is an afternoon, not a long
tail. The long tail is per-dialect library macros.

**Shipped**, in `src/pitch/style.sld`, split into a shared core and the two
dialect tables:

```scheme
;; core -- identical in both standards
(define                 (_ h . body))
(define-syntax          (_ i . body))
(lambda                 (_ f . body))
(case-lambda            (_ . fc*))
(let                    (_ i? fc* . body))   ; i? absorbs named let
(let* letrec letrec* let-values let*-values let-syntax letrec-syntax
                        (_ fc* . body))
(when unless            (_ e . body))
(cond                   (_ . ec*))
(case                   (_ e . lc*))
(begin                  (_ . body))
(do                     (_ fc* ec . body))
(guard                  (_ (i . ec*) . body))
(set!                   (_ i . body))
(syntax-rules           (_ l . dc*))
(import                 (_ . body))
(export                 (_ . fill))
;; r7rs
(define-values          (_ f . body))
(define-record-type     (_ i h i . body))
(parameterize           (_ fc* . body))
(delay delay-force make-promise (_ . body))
(define-library         (_ d . body))
(cond-expand            (_ . ec*))
;; r6rs
(define-record-type     (_ i . body))
(library                (_ d . body))
(syntax-case            (_ e l . dc*))
(with-syntax            (_ fc* . body))
(assert                 (_ . body))
```

Four entries in the draft above this one were judgment calls, and all four are
now settled.

**`if` gets no entry, and neither do `and` and `or`.** The draft had
`(if (_ . body))`, which puts the test on its own line beneath the keyword. What
everyone writes is the test on the opening line with the branches aligned under
it — precisely the generic shape. Leaving `if` out is therefore the correct
entry rather than a gap, and it makes this section's own illustration come out as
drawn. `and` and `or` were drafted as `fill`, which packs unrelated predicates
onto shared lines; the generic aligned shape reads better, and there is no reason
to spend an entry making output worse.

**`import` is a body and `export` is a fill**, which the draft left open as
taste. Settled by looking at what this repository already contains: every library
here writes its import list one clause per line and its export list packed
several names per line, because an import clause is a structure worth scanning
vertically and an export is a name in a set. Choosing what the sources already do
also means the first run of pitch over pitch does not churn them.

**`define-record-type` is absent from the core**, so the default dialect degrades
it rather than guessing — see below.

### `define-record-type`

**The one genuine collision**, and the reason the table must be
dialect-parameterized rather than a single union map:

```scheme
;; R7RS
(define-record-type <point> (make-point x y) point? (x point-x) (y point-y set-point-y!))
;; R6RS
(define-record-type point (fields (immutable x) (mutable y)) (protocol ...) (parent ...))
```

Same head symbol, incompatible shapes — `(_ i h i . body)` versus `(_ i . body)`.
It appears to be the only such collision in the core of either standard, but one
is enough to settle the architecture.

**Settled: each resolved configuration holds three tables, and its dialect
selects one.** The core is the entries common to both standards; each dialect
table is the resolved core followed by its own additions, replacements, and
removals. A shared entry is compiled once and is literally the same descriptor
reachable from both. `format-source` takes the resolved configuration, selects
the table at the edge, and passes that table to `cst->document`; translation sees
neither dialect nor configuration. Under the shipped `common` default the
colliding head has no entry and therefore degrades rather than being guessed at.

A dialect at this layer still selects a style table and nothing else. §4 defines
it as a bundle of three, but the reader remains a permissive union by invariant
and the normalization list remains empty and non-configurable. Configuration
therefore supplies the dialect and style data without inventing reader or
normalization switches.

### Graceful degradation

SRFI 272 specifies that a form not matching its style pattern has
the non-matching part printed as a plain datum. Adopt this. A formatter
encounters `(let)` and `(if)` with wrong arity constantly — in macro-generating
code and in half-saved files — and must never crash or mangle.

**Status: shipped, and the fallback paths are enumerated rather than implied.**
The generic shape is the universal fallback, which is why it had to exist and be
correct before the table did. A form degrades when its head is not an identifier
leaf or has no entry, when it has fewer elements than the style has required
slots, when a slot requiring a list gets something else, when the list is
improper, or when a comment has forced a break inside the region a style requires
to be on one line.

That last one is the only new mechanism, and it reuses machinery rather than
reasoning afresh: the separator between two items is a plain space exactly when
nothing forced a break, so the same `gap` the printer already used answers it. A
style therefore never moves a comment and never loses one — it chooses among
layouts of an item sequence the comment-placement rules already built. Moving a
comment to make a style fit is what layer 1 refuses.

The seam is one function, `compound-shape`. It reads the head — as the token's
*value*, so `|cond|` and, under `#!fold-case`, `COND` take the shape they mean —
looks it up in the dialect's table, and returns a descriptor. No other function
in the printer may examine a head. That is `AGENTS.md`'s "style tables are data,
not code" made checkable rather than aspirational, and the check is structural at
a second level too: `(pitch style)` imports neither the CST, the document algebra
nor the reader, so a table cannot contain a document or a procedure because the
library that defines tables cannot name one.

Reading a token's value widens what the translation may look at, and the widening
is narrow: recorded offsets, lines and columns stay forbidden, comment
classification still comes from whitespace text, and every character emitted
still comes from `token-text`. A value may select whitespace, which is the one
thing pitch is allowed to change.

### Numeric knobs

SRFI 272's `pp-tab` (body indent relative to the keyword) and
`pp-max-tab` (cap on the extra offset short keywords like `if` induce), plus
width. Width is the only numeric value pitch exposes as configuration.

**Settled: `pp-tab` is 2 and is measured from the opening delimiter, and
`pp-max-tab` is not implemented.** SRFI 272 measures from the start of the form's
keyword, which with the keyword one column right of the delimiter would put a
body three columns in — what nothing in either community writes. Measuring from
the delimiter gives the two columns Emacs and `raco fmt` produce, and it is what
the hanging shape already did, so neither the constant nor the `nest` changed.

**Amended: there are two indents, and the tail terminal selects between them.**
`body` and the clause terminals indent 2; `body0` indents 0. It exists for forms
that wrap a whole compilation unit — `library` and `define-library` — where
indenting the body costs two columns on every line of a file to mark a nesting
level that ends at the last line and that nobody can forget. Both remain
constants of the implementation, measured from the opening delimiter: the
*terminal* chooses, and neither a configuration field nor a style can name an
indent of its own.

`body0` is not an SRFI 272 terminal, and adding it is the one place pitch extends
the grammar rather than adopting it. The reason is the layering rule: per-form
layout knowledge must be data in the style table and must never be a `cond`
branch on a head symbol, so a rule of the form "this form's body is not
indented" has nowhere to live except the notation. The grammar stays closed —
the terminals are a finite enumeration and anything outside it is refused where
the table is built — and the precedent extends no further than the one terminal.

`pp-max-tab` exists to cap the rightward drift a long keyword causes when a body
is offset from the keyword rather than from the delimiter. There is no such drift
here, so the knob has no referent. Both stay constants; the bounded external
configuration exposes width, dialect, and per-form style entries, not terminal
semantics.

### Open questions on style tables

- Whether a quoted list should fill. `'(1 2 3 ... 100)` one element per line is
  nobody's intent, but the fact that makes it data is the enclosing `quote`
  prefix rather than its own head, so the rule is contextual and does not fit a
  head-keyed table. Bytevectors are decided the other way and do fill, because
  their elements are octets and no judgment is involved. Vectors do not, because
  their elements can be anything.
- Whether data suppression should be deep. Today `l` suppresses lookup for the
  literals list itself and its children are laid out normally, so a
  `syntax-rules` *pattern* containing something that spells `let` is still styled
  as a `let`. Deep suppression means threading a data context through the
  translation, which is real complexity for a benefit real input has not yet
  demonstrated.
- Whether the dialect default should become `r7rs` or stay `common` once content
  sniffing exists and a file's dialect is usually known.
- Whether the long tail of per-dialect library macros is worth chasing, and by
  what evidence. `raco fmt` reached 183 entries; this table is 30 or so, and the
  corpus work is what should say which additions earn their place.
- Whether an in-file `;; * pp-styles:` comment ever ships. It is the community
  precedent for per-file overrides, but would be a second configuration channel
  with source-local precedence and needs a separate argument.

## 6. Layout engine

The target is a `pretty-expressive` -style engine implementing Πe from
*A Pretty Expressive Printer* (Porncharoenwase, Pombrio, Torlak,
OOPSLA 2023): strictly more expressive than prior printers in the
literature, provably minimizes a user-supplied cost objective,
correctness verified in Lean.

Filling is a use the engine was measured on rather than one it is being
stretched to cover. `fillSep` — "also known as fill, which performs word
wrapping" — is one of the paper's own benchmark families, and Πe handles it in
0.010 s and 0.190 s where Bernardy's printer fails outright. The paper says
nothing about quoted data or a code/data distinction; its §8.2 on the Racket
formatter notes only that each function application has three styles. So the
algebra supplies the mechanism and the policy in §5 is pitch's own.

The cost factory is where black's aesthetic preferences get encoded — penalize
overflow, penalize height, reward dedented closing delimiters — rather than in
ad-hoc heuristics. This is the substitution point for style opinions.

**Settled: the port is done.** The engine ships as three libraries: `(pitch doc)`
for the document algebra, `(pitch cost)` for the cost factory, and
`(pitch layout)` for the resolver. Nothing in them knows anything about Scheme —
no tokens, no comments, no brackets, no dialects — so the layering invariant
holds trivially: the engine cannot branch on a dialect because it cannot see one.

The surface is the paper's: `text`, `newline`, `concat`, `alternatives`, `nest`,
`align`, `reset`, `full`, `cost`, `fail`, plus `group`, `flatten`, `alt`, and
five append families. `newline` shadows the one in `(rnrs io simple)`, which
`(rnrs base)` does not export, so only a file doing console I/O ever notices —
and R6RS reports that at import time rather than shadowing silently.

Three things the reference has are deliberately absent. `special` passes a
non-string through a Racket structured output port and has nothing to do here.
Racket's parameter objects are replaced by `case-lambda` arities, so a layout
depends on its arguments and nothing else. And the infix aliases (`<>`, `<$>`,
`<+>`) are dropped as line noise in Scheme.

**Failure and taint are different outcomes, and callers must be able to tell
them apart.** A document with no layout at all — `fail`, or a `full` followed by
text — raises. It does not get a best-effort rendering, because there is no
principled one and inventing output is the repair pitch refuses everywhere else.
A document whose every layout overflows the *computation width* renders normally
but comes back with `tainted?` true: the text is complete and valid, and what
has been withdrawn is only the claim that it is minimal.

**`text` refuses a line ending, which the reference does not check.** Column
arithmetic is the whole cost model, so a newline hidden inside a text mis-costs
every measure downstream while still producing plausible output. The specific
reason is better than the general one: a line comment's token text *includes* its
terminating line ending, so a printer emitting `(text (token-text tok))` for a
comment would build exactly the bug the paragraph below is about. Refusing the
string forces the printer to split the terminator off and state what follows.
The recognized endings are the reader's seven, shared with layer 1's trailing
line-ending rule rather than defined a second time.

### The oracle, and the one place we diverge

`make oracle-layout` renders a corpus through both `(pitch layout)` and Racket's
`pretty-expressive` and requires the text, the cost and the taint flag to agree.
One file, `tests/oracle/documents.scm`, drives both sides, so a case cannot be
added to one and forgotten on the other. It is not part of `make test`, whose
application matrix runs through Emit and whose retained Chez use is limited to
reader/datum oracles; a missing Racket is reported and skipped.

The corpus reader refuses a file containing anything after its single list. That
guard is not hypothetical: a stray paren once truncated the corpus, *both*
drivers skipped the same trailing entries, and the diff passed on a corpus
smaller than the file. An oracle that agrees about nothing agrees.

**The reference's `flatten` has a bug, and pitch does not reproduce it.** It
strips `align`, `nest` and `reset` and then maps over the child's children rather
than recurring on the child, so a newline that is the *direct* child of one of
those three comes back unflattened: `(flatten (align nl))` is a line break rather
than a space, and `(flatten (align hard-nl))` is a line break rather than a
failure. The consequence is that `(group (align d))` — the shape a Lisp printer
uses constantly, "flat if it fits, else break and align under the head" — can
emit a line break from its *flat* alternative. For a formatter whose entire
promise is that it changes only whitespace, a break nobody authorized is not
cosmetic. Fixed here; the shape is excluded from the oracle corpus, with the
fixed behavior asserted directly in `tests/test-doc-r7rs.scm` instead.

Two smaller divergences are answer-preserving and recorded in the header of
`src/pitch/layout.sld`: memo tables are external and per-call rather than stored
on document nodes and cleared afterwards, and every internal node is memoized
rather than every seventh. The first is what makes a measure computed under one
cost factory unable to leak into a layout under another.

**Resolution time: both of those divergences were profiled and neither is the
cost.** This section recorded the objective and said nothing about how long
minimizing it takes, and issue #15 reported per-line formatting cost roughly
tripling from a 200-line file to a 2,500-line one, with a generated Unicode table
worse still. Change `reduce-formatting-cost` measured it. The finding, in full in
that change's `measurements.md`:

- Memoization scope and granularity are **not** the dominant term. Neither
  appears near the top of a profile of either the largest hand-written corpus
  member or the data-dense one. Memoizing every node rather than every seventh
  contributes to the live heap and so to collector time, second by a wide margin.
- A quadratic accumulation in the token vector, the CST child sequences or
  `cst->text` — §6's other guess — is **refuted**. Tokenizing and parsing are
  linear in every controlled measurement; `cst->text` does not appear in a
  profile at all.
- The cost was five superlinear terms, none of them in pitch's algorithms. Three
  were in the Emit runtime — `rt_intern` scanned its whole symbol table, and the
  code generator emits an intern per *evaluation* of a quoted symbol literal, so
  a symbol comparison in an inner loop cost O(symbols interned); `string-set!`
  reallocated and copied the entire string, making a character-at-a-time buffer
  fill quadratic. Two were pitch's own use of the host: `(pitch doc)` and
  `(pitch table)` discriminated their node and table kinds with symbol literals
  in their hottest loops, and the reader and `cst->text` left every string output
  port open, which on a libc-backed port makes each new one walk past all its
  predecessors.
- Formatting is now near-linear in both size and shape. `make bench` reports a
  largest-to-smallest per-line ratio of 1.44 and a data-dense-to-code ratio of
  1.16, against 1.58 and 2.30 before. Emit's own sources check 7–9× faster, and
  the generated Unicode table that was the worst file per line is now the best.

The general lesson, which is why it is recorded here rather than only in the
change: **the engine's asymptotics were never the problem, and two plausible
stories about them were both wrong.** A profile settled in an afternoon what a
year of reasoning about memo tables would not have.

**The shipped cost factory is the reference's, not pitch's.** Squared overflow
past the page width, then line count, compared lexicographically. It ships
because the paper specifies it and the oracle needs both sides to agree on one
objective. The dedented-closer reward and the rest of pitch's taste still want
tuning against a corpus, which is the corpus change's work; the translation that
produces real Scheme documents to tune *with* now exists.

That objective's shape is load-bearing in one place worth recording. The
translation offers each compound three layouts — flat, aligned, hanging — and
hanging is aligned plus one break and never wider, so it is always exactly one
line taller. Under an objective ranking overflow before height, hanging is
therefore chosen only when it strictly reduces overflow, and the two never tie
except where they render identically. That is what makes the choice deterministic
without the printer expressing a preference through `cost` — which it must not
do, since a cost is a value in the factory's own representation and building one
would couple the translation to a single factory.

A structural invariant checked at print time,
not inferred: **a line comment token must always be followed by a line break.**
The layer 1 check does catch violations — swallowed code shows up as missing
tokens — but this is the single most dangerous printer bug in any Lisp
formatter, and it deserves an assertion where it happens rather than a diagnosis
three layers downstream.

**Status.** Layer 1 is shipped, and `tests/test-check-r7rs.scm` pins this case: `(a ;
c⏎ b)` printed as `(a ; c b)` is caught, because the comment token swallows `b)`
and two tokens vanish from the sequence. That is a backstop, not a substitute.
The assertion still belongs in the printer, where it can name the form being
emitted; layer 1 can only report that the output no longer matches.

**Settled: the assertion is discharged, and by construction rather than by an
`assert`.** `(pitch print)` emits a line comment as its text minus one trailing
ending followed by `hard-nl`, in a single function with no branch that omits the
break — including for a comment ending the source with no terminator, which gets
one anyway, and which is also what makes a formatted file end in a newline. The
second guard is at the item join, which emits no separator after an element
ending in a forced break; it is true by construction today, and it is written as
an assertion so that a later edit making it false fails loudly rather than
quietly.

A third guard fell out of the algebra for free. `hard-nl` fails when flattened,
so a form containing a line comment denotes *no* single-line layout at any page
width. The most dangerous bug a Lisp formatter can have is not merely prohibited
here; it is unrepresentable.


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
