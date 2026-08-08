## ADDED Requirements

### Requirement: Data are compared by a named equivalence

The system SHALL provide a datum equivalence operation used by the layer 2
check, so that tests and future callers name one operation rather than reaching
for a host primitive directly.

The operation SHALL terminate on cyclic arguments.

#### Scenario: Structurally equal data compare equal

- **WHEN** the data projected from `(a (b c))` and from `(a (b c))` are compared
- **THEN** they compare equal

#### Scenario: Data differing in one element compare unequal

- **WHEN** the data projected from `(a b)` and from `(a c)` are compared
- **THEN** they compare unequal

#### Scenario: Equal cyclic data compare equal and terminate

- **WHEN** the data projected from `#0=(a . #0#)` and from `#0=(a . #0#)` are
  compared
- **THEN** they compare equal
- **AND** the comparison terminates

#### Scenario: Unequal cyclic data compare unequal and terminate

- **WHEN** the data projected from `#0=(a . #0#)` and from `#0=(b . #0#)` are
  compared
- **THEN** they compare unequal
- **AND** the comparison terminates

#### Scenario: Exactness is significant

- **WHEN** the data projected from `1` and from `1.0` are compared
- **THEN** they compare unequal

### Requirement: The layer 2 check compares two source texts

The check SHALL accept two source texts, parse and project each independently,
and report whether their data are equivalent.

The check MUST accept texts rather than trees or data, so that a caller cannot
compare an in-memory tree against itself. Comparing a tree to an artifact
derived from that same tree passes regardless of what a printer did, and is the
failure mode this signature exists to prevent.

#### Scenario: Texts differing only in whitespace are equivalent

- **WHEN** `(define (f x)\n  (g x))` and `(define (f x) (g x))` are checked
- **THEN** the check reports equivalence

#### Scenario: Texts differing only in comments are equivalent

- **WHEN** `(a b)` and `(a ; note\n b)` are checked
- **THEN** the check reports equivalence

#### Scenario: Texts differing in a datum are not equivalent

- **WHEN** `(a b)` and `(a c)` are checked
- **THEN** the check reports non-equivalence

#### Scenario: A dropped form is not equivalent

- **WHEN** `(a) (b)` and `(a)` are checked
- **THEN** the check reports non-equivalence

#### Scenario: A changed nesting is not equivalent

- **WHEN** `(a (b c))` and `(a b c)` are checked
- **THEN** the check reports non-equivalence

### Requirement: Diagnostics on either side fail the check

If parsing or projecting either text produces a diagnostic, the check SHALL
report failure rather than comparing, and SHALL make those diagnostics available.

#### Scenario: A malformed input fails the check

- **WHEN** `(a (b` and `(a (b` are checked
- **THEN** the check reports failure
- **AND** it does not report equivalence, even though the two texts are identical

#### Scenario: An unresolvable label fails the check

- **WHEN** `(#1#)` and `(#1#)` are checked
- **THEN** the check reports failure

### Requirement: Layer 2 states its own weakness

The check SHALL be documented as strictly weaker than token equivalence, and its
value SHALL be stated as independence from that check rather than strength.

The following MUST be understood to pass datum equivalence, so that no consumer
mistakes it for a sufficient safety check on its own: a deleted comment, a
moved `#;` datum comment, a bracket rewritten from `[` to `(`, an abbreviation
expanded to its long form, a number rewritten in another radix, and a string
escape respelled.

#### Scenario: Deleting a comment passes datum equivalence

- **WHEN** `(a ; note\n b)` and `(a b)` are checked
- **THEN** the check reports equivalence, despite the comment having been lost

#### Scenario: Flipping bracket shape passes datum equivalence

- **WHEN** `[a b]` and `(a b)` are checked
- **THEN** the check reports equivalence

#### Scenario: Expanding an abbreviation passes datum equivalence

- **WHEN** `'x` and `(quote x)` are checked
- **THEN** the check reports equivalence

#### Scenario: Respelling a number passes datum equivalence

- **WHEN** `#xff` and `255` are checked
- **THEN** the check reports equivalence

### Requirement: The check runs against text re-read from a formatter's output

When the check is used to verify a formatting run, the second text SHALL be the
text the formatter produced, re-read as text.

An implementation MUST NOT satisfy the check by reusing the tree the printer
walked, or any value derived from it. A formatter changes only layout and
trivia, so a projection of the printer's own tree is identical by construction
and would pass no matter how the printer misbehaved.

#### Scenario: The check's second input originates from the formatter's output

- **WHEN** a formatting run is verified
- **THEN** the second text passed to the check is the formatter's output text
- **AND** it is parsed afresh rather than reusing any tree from the run

### Requirement: A host reader is used as a test oracle only

The projection SHALL be differentially tested against a host implementation's
reader, asserting that projecting a source yields data equal to what that
implementation's own reader produces from the same source.

This comparison SHALL exist only in tests. No runtime code path may call a host
implementation's reader, because the guarantee would then vary by platform.

The oracle covers only what that implementation accepts; constructs it rejects
SHALL be covered by written expectations instead, and the tests SHALL say so, so
that a passing differential run is not mistaken for full coverage.

#### Scenario: The projection agrees with the host reader on the corpus

- **WHEN** each of the repository's own Scheme source files is projected
- **AND** the same file is read by the host implementation's reader
- **THEN** the two results are equal, datum for datum

#### Scenario: Constructs the oracle rejects are covered separately

- **WHEN** a construct the oracle's reader does not accept is projected
- **THEN** its expected data are asserted directly rather than against the oracle

#### Scenario: No runtime path calls a host reader

- **WHEN** the shipped libraries are examined
- **THEN** none of them calls the host implementation's `read`
