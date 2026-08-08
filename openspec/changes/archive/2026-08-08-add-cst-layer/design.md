## Context

`src/pitch/reader.sls` yields a flat token sequence in which every character of
the input is attributed to exactly one token. `tests/test-recording.sps` already
asserts that concatenating token text reproduces five real source files byte for
byte. Everything above the lexer — style table, layout engine, `cst->datum` — is
unwritten and needs structure to be written against.

Constraints that are not negotiable here, from `CLAUDE.md`:

- Concatenating the source text of a CST reproduces the input byte for byte, as
  a checked property rather than an aspiration.
- No stage discards a comment, a `#;` datum comment, a `#| |#` block, a bracket
  shape, a quote abbreviation, a numeric lexeme, or a string escape spelling.
- The CST never branches on dialect.
- Malformed input is refused, not guessed at.
- `src/pitch/reader.sls` is a derived work kept minimally diffed from
  `vendor/laesare/reader.sls`. Changing it has a cost this change should not pay.

Three decisions were settled before this document: scope stops short of
`cst->datum`, leaf text comes from the token, and the parser consumes an explicit
token vector. This document records their rationale and works out the rest.

## Goals / Non-Goals

**Goals:**

- A node representation that makes losslessness structural rather than
  disciplinary — the invariant should be hard to violate, not merely tested.
- A parser that always produces a tree, including for half-typed buffers, while
  reporting precisely why the tree is not clean.
- Clear seams between lexing, tokenization, parsing, and serialization, each
  independently inspectable.
- A representation the layout engine can be designed against without revisiting
  this one.

**Non-Goals:**

- `cst->datum`, graph reconstruction of `#0=`/`#0#`, and the cyclic-safe
  comparator. Deferred to its own proposal.
- Any reflowing. `cst->text` reproduces; it does not format.
- The style table, the layout engine, the CLI, and layers 1 through 3.
- Modifying `src/pitch/reader.sls`.

## Decisions

### Trivia are ordinary children

Whitespace, line comments, `#|...|#` blocks, `#;` datum comments, directives, and
the shebang line are members of a node's child sequence, in source order,
indistinguishable positionally from data.

*Alternative considered:* Roslyn-style leading/trailing trivia attached to
tokens. Rejected for the reason `docs/DESIGN.md` §3 gives: for a Lisp, comment
placement relative to siblings is the entire hard problem, and an attachment
model forces every construction site to make an attachment decision — the exact
place comments get dropped. Floating trivia keeps "concatenate the children
equals the source" true by construction, and defers attachment to the layout
engine, where it is a layout question and can be revisited without touching the
tree.

*Cost:* consumers wanting "the third element of this form" must skip trivia
rather than index. Accessors that filter trivia absorb this.

### Leaves hold tokens; the token owns the text

A leaf node holds a reader token. Its text is `token-text`. Offsets and
line/column stay reachable through the token for diagnostics but are never the
authority for output.

*Alternative considered:* the root holds the source string and every node holds a
span into it. Rejected on three grounds. The reader already allocates a text
string per token, so spans save nothing unless the reader also stops recording
text — which would mean editing the derived reader for a benefit we do not need.
Spans force the source string to be threaded through every printer and checker
and retained after the port closes. And spans are wrong for the tree the
formatter eventually builds, whose whitespace leaves do not correspond to any
input span.

*Consequence worth stating:* because text is authoritative and values are not,
`#!fold-case` cannot damage losslessness. It changes `token-value` for
identifiers and leaves `token-text` alone.

### Interior nodes name their delimiters

An interior node holds its opening leaf and closing leaf in dedicated fields,
with the interior child sequence between them. `cst->text` emits open, then
children, then close.

*Alternative considered:* delimiters as the first and last members of a single
child sequence, which makes serialization a completely uniform walk. Rejected
because it cannot represent an unclosed list distinguishably — a list whose last
child happens not to be a close token is ambiguous with a malformed one. With a
dedicated field, `close` is `#f` and the malformation is explicit rather than
inferred. Element access also stops depending on positional convention.

Bracket shape is *not* a node field. `(` versus `[` is read from the kind of the
opening and closing leaves' tokens (`openp`/`openb`, `closep`/`closeb`). Storing
it on the node would create a second source of truth that could disagree with the
text, which is the class of bug this whole layer exists to prevent.

### Node kinds

| Kind | Holds | Covers |
|---|---|---|
| `leaf` | one token | every token: atoms, delimiters, trivia, `#;`, directives, eof |
| `document` | children, eof leaf | the whole source |
| `list` | open, children, close | `(...)` and `[...]` |
| `vector` | open, children, close | `#(...)` |
| `bytevector` | open, children, close | `#vu8(...)` and `#u8(...)` |
| `prefix` | marker, children, datum | `'` `` ` `` `,` `,@` `#'` `` #` `` `#,` `#,@` and `#0=` |
| `error` | anchor token, message, children | malformed regions |

`vector` and `bytevector` are distinct kinds from `list` because their layout
differs — bytevector contents are always numbers and want filling, not
form-oriented breaking. They are *not* distinct per dialect: `#vu8(` and `#u8(`
produce the same node kind, and the spelling difference lives in the opening
token's text. This is precisely how the tree stays dialect-agnostic while
preserving dialect-specific spelling.

`#0=` is a `prefix` and `#0#` is a `leaf`, matching `docs/DESIGN.md` §3. Treating
the label as a prefix means the layout engine handles `#0=(a b)` with the same
machinery as `'(a b)`.

### `#;` datum comments stay opaque

The lexer returns `#;(b c)` as a single `inline-comment` token whose text spans
the marker, any intervening atmosphere, and the entire commented datum. The
parser does not look inside; the node is a `leaf` and the region is trivia.

This is not a fresh choice so much as an acknowledgment — the token boundary is
already drawn there, and seeing inside would require re-lexing the token's text.
It matches SRFI 272, which makes `#;` handling optional even in its advanced
layer. `docs/DESIGN.md` §3 asks that this be recorded as a decision rather than
left as an accident of the token layer; this is that record.

A consequence: an unbalanced bracket *inside* a `#;` datum is a lexical problem,
not a parse problem, and surfaces as a reader warning rather than a structural
error.

### Improper tails keep the dot as an ordinary child

In `(a . b)` the `.` is a `leaf` in the list's child sequence, with no special
node wrapping the tail.

*Alternative considered:* a dedicated tail field or a `dotted-list` node kind.
Rejected because it invents a second description of element order that must be
kept consistent with the text, and because the dot can be surrounded by trivia
(`(a . ; why\n b)`) that would then need a home. `docs/DESIGN.md` §3 warns that
laesare's dotted-pair path is where upstream discards comments; keeping the dot
flat means there is no separate path to lose them on.

The parser still *validates*: a dot must be preceded by at least one datum,
followed by exactly one datum, and be the last dot in the list. Violations
produce a diagnostic. A predicate over the child sequence answers "is this list
improper" for later layers.

### Tokenize into an explicit vector, in tolerant mode, collecting diagnostics

`tokenize` drives `get-token` to eof and returns a vector of tokens plus a list
of diagnostics. It sets `reader-tolerant?` to `#t` and installs a handler for the
continuable warnings that `reader-warning` raises in that mode, recording each
and continuing.

Tolerant mode is what makes the layer honest. In strict mode a lexical error
raises and there is no tree at all; in tolerant mode the reader recovers, still
attributes every character to a token, and the round-trip guarantee survives
malformed input — which the derived reader's header already states explicitly.

*Alternative considered:* streaming tokens straight into the parser. Rejected
because layer 0 and the future layer 1 token-equivalence check both want a token
sequence, and materializing it once means they compare against the same
inspectable object. It also makes a lexer bug distinguishable from a parser bug
by looking at the vector, which is the observability between layers `CLAUDE.md`
asks for. Source files are small enough that holding the vector is not a concern.

The reader is created in `rnrs` mode — the permissive union that satisfies every
`assert-mode` check — so dialect never causes rejection.

### Diagnostics carry token positions, not condition positions

Each diagnostic records a message and the token it concerns; line and column are
read from that token.

The lexical conditions the reader raises carry a `&source-information` built from
`reader-saved-line`/`reader-saved-column`, which by our own specification
describe the innermost recursive lexer entry rather than the token returned.
Those fields are right often enough to be dangerous. Since `tokenize` knows which
token index it is on when a warning arrives, it can attach the token's own
position, which the token-line-column change made trustworthy on exactly these
paths.

### Malformed input yields a tree plus a non-empty diagnostic list

`parse` returns two values: the document node and a list of diagnostics. A tree
is clean iff the list is empty. There is no mutable "unclean" flag.

Structural malformations and their representations:

| Input | Representation |
|---|---|
| unclosed `(` at eof | `list` node with `close` of `#f` |
| unexpected `)` | `error` node wrapping the stray leaf |
| `(a]` | `list` node closed by the mismatched leaf, plus a diagnostic |
| `'` at eof | `prefix` node with `datum` of `#f` |
| misplaced `.` | list keeps the dot leaf, plus a diagnostic |
| lexical warning | the token as lexed, plus a diagnostic |

Every one of these still holds all of its tokens, so `cst->text` reproduces the
input regardless. That is deliberate: round-trip is the property least allowed to
depend on the input being good.

Refusing to format is not implemented here because there is nothing to refuse
yet. The tree carries what a future CLI needs to refuse: a non-empty diagnostic
list with positions.

### The leaf sequence equals the token vector

An in-order walk of the tree's leaves yields exactly the token vector that was
parsed, same tokens, same order, none added or dropped.

This is a stronger and sharper invariant than byte-for-byte round-trip, which it
implies given that concatenating the token vector reproduces the source. It is
worth asserting separately because when it fails the failure names the token that
moved, whereas a round-trip failure reports a string mismatch and leaves the
diagnosis to a human. It also holds for malformed input, where round-trip alone
would not tell us whether an error node had swallowed something.

### Module layout

`(pitch cst)` — node record types, accessors, trivia predicates, the leaf walk,
and `cst->text`. Knows nothing about parsing.

`(pitch parse)` — `tokenize`, `parse-tokens`, and a `parse-source` convenience.
Depends on `(pitch reader)` and `(pitch cst)`.

Nodes are immutable records. Formatting later produces new trees rather than
mutating this one, which keeps the parsed tree available as the reference that
layer 0 compares against.

## Risks / Trade-offs

**An in-file `#!r6rs` or `#!r7rs` directive narrows the reader's mode mid-file,
so a file declaring `#!r6rs` and then writing `#u8(` warns.** → This is upstream
behavior on a path this change does not touch, and it is arguably right: the file
declared itself. But it sits in tension with `CLAUDE.md`'s "the reader never
rejects input on dialect grounds." Recorded as an open question below rather than
silently absorbed; in tolerant mode it degrades to a diagnostic, not a failure.

**Token text is not always a minimal lexeme.** On error-recovery and directive
paths `get-token*` consumes a prefix and attributes it to the token it returns.
→ Harmless for round-trip, which is why the reader does it. It means an error
node may cover slightly more text than the offending lexeme. Since malformed
input is never formatted, this only affects the span shown in a diagnostic, and
the token's *start* position remains exact.

**Keeping the dot flat pushes work onto the layout engine**, which must scan a
child sequence to lay out an improper list. → A predicate in `(pitch cst)` gives
it one call, and the alternative pushed a correctness risk into the tree, which
is the worse place for it.

**Deeply nested input recurses.** → Real source files do not approach any
plausible limit, and a formatter that fails on a pathological generated file
fails safely by not writing. Not mitigated further.

**The round-trip test can be written vacuously**, by serializing a tree and
comparing against text derived from that same tree. → For layer 0 the input is
the original file's bytes, so the comparison is against something the tree did
not produce. The test must read the file into a string, parse that string, and
compare `cst->text` to the string. Stated in the spec so the requirement, not
just the test, forbids the vacuous form.

**Corpus scope.** The five in-repo files `test-recording.sps` uses are consistent
R6RS and will not exercise R7RS shapes, `#u8(`, datum labels, or malformed input.
→ Targeted cases cover those; the real corpora in `docs/DESIGN.md` §7 arrive with
the CI harness, which is not this change.

## Open Questions

- Should `tokenize` expose strict mode, given that a formatter always wants
  tolerant? Defaulting to tolerant and not exposing the choice is simpler and can
  be relaxed later; exposing it now costs an argument nobody has a use for.
- Whether the mode-narrowing behavior of `#!r6rs`/`#!r7rs` should be overridden
  to keep the reader permissive throughout. This would mean editing the derived
  reader, so it belongs to its own proposal if it is wanted at all.
- Whether `document` should hold the eof leaf or drop it. Holding it is assumed
  here because it keeps the leaf-sequence invariant exact; its text is empty, so
  round-trip is indifferent.
