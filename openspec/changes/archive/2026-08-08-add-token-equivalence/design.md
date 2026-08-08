## Context

`(pitch check)` holds layer 2. `tokenize` in `(pitch parse)` returns a vector of
every token plus lexical diagnostics, and the CST specs already guarantee that
concatenating those tokens reproduces the input. Layer 1 is a comparison over
that vector, so the machinery it needs is finished; this change is small.

Constraints from `CLAUDE.md`:

- The declared-normalizations list is empty. Output tokens must match input
  tokens exactly, modulo whitespace. Adding an entry requires a proposal that
  argues for it.
- Every check compares against text re-read from the formatter's output.
- Pitch never reorders code and never rewrites comment contents.

Three decisions were settled before this document: one interleaved sequence, a
trailing line ending filtered as whitespace, and a failure that reports where.

## Goals / Non-Goals

**Goals:**

- The primary check: catch everything layer 2 structurally cannot.
- Depend on as little machinery as possible, so that layer 1 failing means the
  printer is wrong rather than that some other layer is.
- Fail informatively, since this is the check that will fire while a printer is
  being written.
- Specify the comparison tightly enough that "modulo whitespace" has exactly one
  reading.

**Non-Goals:**

- Running end to end. There is no printer.
- The printer-time assertion about line comments and line breaks.
- Layers 0 and 3, and any complete verification pipeline.
- Modifying the reader, CST, parser, or projection.

## Decisions

### Layer 1 uses the lexer only

The check tokenizes; it does not parse and does not project. Its diagnostics are
the lexical ones `tokenize` returns.

This is deliberate, and it is what makes layer 1 a good *primary* check. Layer 2
runs through the lexer, the parser, and the projection; a failure there has three
possible authors. Layer 1 has one. The independence that justifies keeping layer
2 at all is only real if layer 1 depends on strictly less.

It costs nothing in coverage. A structural defect in the output — an unbalanced
delimiter, a dropped close paren — changes the token sequence, so the token
comparison sees it without the parser being involved.

### One interleaved sequence

Filter whitespace tokens; compare everything that remains, in order, as a single
sequence. Code tokens and comments are not separated.

*Alternative considered:* compare non-trivia tokens in order and comments in
order, as two independent subsequences. This is the more literal reading of
`docs/DESIGN.md` §1's "compare the comment subsequence in order". Rejected
because it is strictly weaker: it permits a comment to migrate across a code
token, so `(a ; c⏎ b)` and `(a b ; c)` compare equal. That changes which code the
comment documents, which is a meaning change rather than a layout one, and
pitch's non-goals allow changing a comment's placement but not what it is
attached to.

`docs/DESIGN.md`'s "do not compare positions" is about line and column, which
necessarily change under formatting. Comparing sequence order is not comparing
positions, so the interleaved reading does not contradict it.

If the layout engine ever needs the freedom to move a comment across a code
token, this becomes a constraint that must be argued away in a proposal — which
is the right place for that argument to happen, rather than in a comparator that
quietly permitted it all along.

### Compare kind and text; never position

Two tokens are equivalent when their kinds are equal and their texts are equal
after the trailing-line-ending rule below.

Text alone would nearly suffice, since the same lexer produced both. Kind is
compared anyway because it is not redundant: the reader's mode changes mid-file
on `#!r6rs` and `#!r7rs`, and its fold-case state changes on `#!fold-case`, so
identical text can lex differently depending on what preceded it. Comparing kind
makes a directive that moved or vanished visible at the token that changed
meaning, rather than only wherever the directive itself is.

`token-value` is not compared. It is derived from the text, and comparing it
would import layer 2's weakness — `#xff` and `255` share a value.

### A trailing line ending is filtered, like all other whitespace

Before comparing, drop a single trailing line ending from a token's text.

The recognized line endings are the ones the reader's own grammar counts: line
feed, carriage return, carriage return followed by line feed, carriage return
followed by next line, next line, line separator, and paragraph separator, with
the two-character forms counting as one.

Only two token kinds can end with one:

| Kind | Ends with | Affected |
|---|---|---|
| `comment` (`; ...`) | a line ending, or end of input | yes |
| `shebang` (`#!/...`, `#! ... !#`) | a line ending | yes |
| `nested-comment` (`#\| ... \|#`) | `\|#` | no |
| `inline-comment` (`#;...`) | the elided datum | no |
| `directive` (`#!r6rs`) | the directive name | no |

The problem this solves: a line comment's token text swallows the newline that
ends it, so `; c` and `; c⏎` are different texts that differ only in whitespace.
Without the rule, a printer could not end a file with a newline when the file
ends in a comment — which is near-universal formatter behavior — and every
strictness argument for layer 1 would be fighting a tokenization boundary rather
than a real difference.

**This is not a declared normalization, and the list stays empty.** No comment
content is changed, ignored, or rewritten; two comments with different text still
compare unequal. What is filtered is whitespace, which layer 1 filters
everywhere else already. Being strict here and permissive about every other space
and newline would be incoherent. Line endings as such are layer 0's
responsibility, where they are compared byte for byte and no rule like this
exists.

### A failure reports the first differing index and both tokens

The check returns three values: whether the sequences are equivalent, a mismatch
describing the first difference, and the diagnostics found in either text.

*Asymmetry with layer 2 is intentional.* Layer 2 returns a boolean because
locating where two data diverge means walking a graph that may be cyclic — real
work, deferred until a printer produces mismatches worth diagnosing. Layer 1's
sequence is flat, so the index and the two tokens are free. Since layer 1 is the
check that will actually fire during printer development, taking the free
information is obviously right.

The mismatch can also report a side as absent, when one sequence ran out. That
branch is defensive rather than reachable: both sequences end with an eof token
and eof matches only eof, so a shorter sequence yields a mismatch of eof against
a real token before either list empties. A dropped comment therefore reports a
comment on one side and the following code token on the other — which is more
informative than an absent side would have been.

### The check takes two texts

Same signature discipline as layer 2, and for the same reason: the call site is
`check(input, formatted-output)`, and accepting token vectors or trees would let
a caller pass the artifact the printer produced rather than a re-lex of its
output. A formatter changes only layout and trivia, so comparing a printer's own
token vector against itself passes regardless of what it emitted.

### The eof token is compared and always agrees

`tokenize` always ends with an eof token whose text is empty, so it survives
whitespace filtering and compares equal on both sides. It is left in rather than
special-cased: a uniform sequence is easier to reason about than one with a
trailing exception, and if it ever failed to agree, that would be a real defect.

### The combined runner is deliberately minimal

`check-output` takes two texts and runs: diagnostics first, then layer 1, then
layer 2. It returns whether the run passed, which layer failed, and a detail
whose shape depends on the failure — diagnostics when either text is unusable,
the mismatch when layer 1 found one.

Layer 1 runs before layer 2 because it is strictly stronger and its failure is
more informative; if both would fail, the useful message is layer 1's.

This is speculative. It has no caller until a printer exists, and the real
pipeline will also want layer 0 (which compares a tree against its own input, not
two texts, so it does not share this signature) and layer 3 (which needs to run
the formatter twice). Expect the printer's change to revisit this. It is included
because a single obvious entry point is worth more than three checks a caller
must remember to sequence, and because writing it now is a few lines.

### Test file split

Layer 2's check tests currently live in `tests/test-datum.sps`, where they landed
because the projection and the check shipped together. With two checks in
`(pitch check)`, they move to a new `tests/test-check.sps` alongside layer 1's,
and `tests/test-datum.sps` keeps the projection tests.

The move is mechanical and the assertions are unchanged. Counting before and
after guards against silently dropping one in transit.

## Risks / Trade-offs

**The trailing-line-ending rule could hide a printer that rewrites a comment's
line ending style**, turning `; c␍␊` into `; c␊`. → Layer 0 compares byte for
byte and catches exactly this; layer 1 filtering all other whitespace while
policing this one newline would be incoherent. The division of labor is the
mitigation, and it is stated in the spec so it is a decision rather than a gap.

**Interleaving forbids a comment moving across a code token**, which the layout
engine might one day want. → That would be a real change in what pitch promises,
and it should surface as a proposal rather than as a comparator that always
allowed it. Recorded as an open question rather than pre-emptively permitted.

**Layer 1 cannot distinguish "the printer is wrong" from "the input was already
malformed."** → Diagnostics are reported for either text, and a defect on either
side fails before comparison, so the two cases are distinguishable by whether
diagnostics are present.

**Moving layer 2's tests between files can silently lose assertions.** → The
suite prints its own pass count; the sum across the two files must not drop.
Checked explicitly rather than assumed.

**The combined runner may be wrong in shape.** → It is small, it has no caller
yet, and the design says plainly that the printer's change will revisit it.
Better to have one entry point to revise than three call sites to discover.

## Open Questions

- Whether a comment may ever move across a code token. Forbidden here; if the
  layout engine needs it, that needs an argument.
- Whether `check-output` should grow layers 0 and 3, or whether the printer's
  change should define its own pipeline and leave this as the two-text pair.
- Whether layer 1 should report *all* differences rather than the first. The
  first is what a human fixes; a full diff may be more useful across a corpus
  run, which is the CI change's problem.
