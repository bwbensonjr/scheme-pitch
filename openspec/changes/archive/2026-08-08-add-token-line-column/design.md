## Context

`src/pitch/reader.sls` records, for each token, its kind, exact source text,
character offset span, and parsed value. It does not record line or column.

The `get-token` wrapper brackets one outermost call to `get-token*`. It resets
the text accumulator on entry and materializes the token on exit, so it already
holds both ends of the token without any further bookkeeping. `reader-line` and
`reader-column` are live throughout.

Two facts constrain the design, both confirmed against the code:

- `reader-saved-line` and `reader-saved-column` are set by `reader-mark` at
  `get-token*` entry, and `get-token*` recurses into itself on the `#;`,
  directive and error-recovery paths. After such a token is returned they hold
  the innermost mark. Reading `(a\n  #;(b\n     c)\n  d)` gives a datum-comment
  token starting at line 2, column 2, while the saved fields report 3/6. They are
  correct for non-recursive tokens, which is what makes relying on them a trap.
- `get-char` advances `column` unconditionally, including on the call that
  returns the end-of-file object. Offset tracking added by the previous change is
  guarded on `(char? c)`, so at end of input the column has advanced past a
  character that does not exist.

A probe over the existing reader confirms that capturing `reader-line` and
`reader-column` around the wrapper reproduces, for every token, the position that
walking the source to the token's offsets independently computes — with the
end-of-file token the single exception, caused by the second fact above.

## Goals / Non-Goals

**Goals:**

- Every token carries the line and column of both ends of its text.
- Positions are correct on the recursive lexer paths, where the reader's saved
  line and column are not.
- The offset span and the position span never disagree.
- The line and column conventions become stated requirements rather than
  incidental behavior.
- The change stays a single legible commit, portable to the `recording-tokens`
  branch the same way as its predecessor.

**Non-Goals:**

- Any change to `get-token*` or to how lexemes are classified.
- Any change to the datum-reading path's return values.
- Auditing whether `read-annotated`'s annotations are skewed on nested
  constructs. They read the same saved fields, so the question is real, but it is
  pre-existing upstream behavior on a path this change does not touch.
- A line index or offset-to-position conversion utility. The reader supplies
  positions directly; nothing needs to reconstruct them.

## Decisions

### Capture in the wrapper, not by conversion

The wrapper reads `reader-line` and `reader-column` before calling `get-token*`
and again after it returns. Before the call, no character of the token has been
consumed, so those values are the position of its first character. This is the
same instant at which upstream's `reader-mark` fires, so the positions match the
convention already used for annotations.

*Alternative considered:* keep the token record as it is and convert offsets to
positions in the CST, over a line index built once per file. Rejected as a second
structure that has to be built, kept consistent with the reader's own notion of
what a line ending is, and consulted on every diagnostic. The reader already
knows the answer at the moment it is free to record.

*Alternative considered:* fix `reader-mark` so the saved fields describe the
outermost call. Rejected because those fields are upstream's, are read by
`reader-source` on the datum path, and changing their meaning would alter
annotation behavior — the one thing the previous change went to some length to
leave alone.

### Record both ends now rather than start only

Only the start position has a named consumer today: the CLI refusing to format
malformed input. End positions cost two more fields and two more reads of values
that are already live at wrapper exit.

The token record is a published shape with a `nongenerative` UID. Adding fields
after the CST destructures tokens means a second breaking change and a second UID
bump. Doing both ends in one edit is strictly cheaper than doing it twice.

### Stop advancing the column at end of input

`get-char` currently advances `column` even when it returns the end-of-file
object, so the end-of-file token's end position lands one column past its own end
offset. Guard the line and column update on the value being a character, exactly
as the offset and text updates already are.

This is the principled fix: it makes "line and column describe the next character
to be consumed, and advance only when a character is consumed" true globally,
rather than true except at one boundary. It also repairs `reader-column` at end
of input for any consumer, not only for tokens.

*Alternative considered:* special-case the wrapper so a token whose start and end
offsets are equal reports its start position as its end position. Rejected as
treating the symptom; it would leave `reader-column` itself wrong at end of input
and would silently paper over any future zero-width token.

This does change an observable on the datum path, so it is not free. The previous
change promised that path stays behaviorally identical, and this narrows that
promise: the column reported *after* end of input changes. It is a position fix
of the same kind as the line-ending fix that shipped in the same file, and the
baseline suite must confirm nothing depended on the old behavior.

### End positions are half-open, and columns are character-based

The end position is the position of the character *after* the token, not of its
last character. This is not really a free choice: `token-end` is already an
exclusive character offset, so an inclusive end position would describe the same
span under the opposite convention; and the end-of-file token is zero-width, so
it has no expressible inclusive end. It also matches LSP ranges.

The consequence worth stating, because it is the common case rather than an edge
case: a token whose text ends with a line ending reports an end position on the
following line. A line comment `; hi` terminated by a newline and beginning at
line 1, column 2 ends at line 2, column 0. It occupies one line but its start and
end lines differ. Every line comment and most whitespace tokens behave this way,
so a consumer asking which lines a token covers cannot read the end line
directly. Trimming the trailing line ending from the end position would fix the
reading at the cost of breaking the correspondence with the end offset, which is
the one property the spec insists on; the wrinkle is documented instead.

Half-openness also gives a property worth testing directly: adjacent tokens share
a boundary, so each token's end position equals the next token's start position.

Columns count characters, consistently with the offsets. LSP columns are UTF-16
code units, which agree with characters only below the BMP. These positions are
therefore not LSP positions, and anything exporting them to an editor protocol
will need to convert. Noted because LSP is cited above as precedent for the
half-open convention, not for the column unit.

### Keep the character offsets

Offsets stay alongside positions. They are what `docs/DESIGN.md` §3 identifies as
the basis for the CST's text-ownership choice, they are the cheapest way to slice
the source, and they are the representation the round-trip property is stated
over. Positions are for humans; offsets are for machines.

## Risks / Trade-offs

- **The end-of-input column change is a behavior change on the datum path** →
  Confined to the position reported after the end-of-file object, which nothing
  in the reader consumes. Verified by the baseline suite, which must stay at 196.
- **Six fields is a wide token record** → Accepted. The alternative is a nested
  position record, which adds an allocation and an indirection per token for a
  formatter that reads whole files. Revisit only if the CST wants it.
- **Positions are recorded for every token, including whitespace** → Uniformity
  is worth more than the saving; a CST that treats trivia as ordinary children,
  which `docs/DESIGN.md` §3 selects, wants positions on them too.
- **Non-minimal spans carry over to positions** → On error-recovery and directive
  paths a token's text includes a consumed prefix, so its start position is the
  start of that prefix. This is the same accepted trade as for the text, and
  `docs/DESIGN.md` §3 already resolves it: malformed input is never formatted.
- **The upstream port carries a behavior change** → The end-of-input column fix
  is defensible on its own, but it should be called out separately in the ported
  commit rather than buried in a feature commit.

## Migration Plan

No deployed consumer; the CST does not exist yet. Rollback is `git revert` of the
single commit, since `vendor/laesare/` is untouched throughout.

## Open Questions

- Are `read-annotated`'s annotations skewed on nested constructs, given they read
  the same saved fields? Deliberately out of scope, but worth its own
  investigation before anything depends on annotation positions.
