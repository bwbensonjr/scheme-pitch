## ADDED Requirements

### Requirement: Tokens are compared by kind and text

The system SHALL provide a token equivalence operation. Two tokens are
equivalent when their kinds are equal and their texts are equal after the
trailing line ending rule is applied.

Line and column MUST NOT be compared, because formatting necessarily changes
them. The token's parsed value MUST NOT be compared, because it is derived from
the text and comparing it would admit the differences layer 2 already tolerates.

#### Scenario: Identical tokens are equivalent

- **WHEN** two tokens of the same kind and the same text are compared
- **THEN** they are equivalent

#### Scenario: Differing text is not equivalent

- **WHEN** a token with the text `#xff` is compared with one with the text `255`
- **THEN** they are not equivalent

#### Scenario: Differing kind is not equivalent

- **WHEN** a token of kind `openp` with the text `(` is compared with a token of
  kind `openb` with the text `[`
- **THEN** they are not equivalent

#### Scenario: Position is not compared

- **WHEN** two tokens have the same kind and text but different lines and columns
- **THEN** they are equivalent

### Requirement: Whitespace is filtered and a trailing line ending is filtered with it

The comparison SHALL ignore whitespace tokens entirely.

A single trailing line ending SHALL be dropped from a token's text before
comparison. The line endings recognized SHALL be those the reader's grammar
counts: line feed, carriage return, carriage return followed by line feed,
carriage return followed by next line, next line, line separator, and paragraph
separator, with the two-character forms counting as one ending.

This rule changes no comment content. Two comments whose content differs SHALL
remain non-equivalent, so this is not a declared normalization and the
declared-normalizations list remains empty.

#### Scenario: Layout whitespace is ignored

- **WHEN** `(a  b)` and `(a\n  b)` are compared
- **THEN** they are token-equivalent

#### Scenario: A comment terminated by a line ending matches one that is not

- **WHEN** `(a) ; c` and `(a) ; c\n` are compared
- **THEN** they are token-equivalent

#### Scenario: Comment content is still compared exactly

- **WHEN** `(a) ; c` and `(a) ; d` are compared
- **THEN** they are not token-equivalent

#### Scenario: Only a trailing line ending is dropped

- **WHEN** a nested comment `#| b |#` is compared with `#| c |#`
- **THEN** they are not token-equivalent
- **AND** no part of either text is dropped before comparison

### Requirement: Code tokens and comments are compared as one interleaved sequence

The comparison SHALL be over a single sequence containing every non-whitespace
token in source order, with comments, datum comments, directives, and shebang
lines interleaved among the code tokens exactly where they occur.

The comparison MUST NOT split the sequence into independent code and comment
subsequences, because that would permit a comment to move across a code token
and so change which code it documents.

#### Scenario: A comment moving across a code token is detected

- **WHEN** `(a ; c\n b)` and `(a b ; c\n)` are compared
- **THEN** they are not token-equivalent

#### Scenario: Two comments exchanged are detected

- **WHEN** `(a ; c\n b ; d\n)` and `(a ; d\n b ; c\n)` are compared
- **THEN** they are not token-equivalent

#### Scenario: Reindenting a comment is permitted

- **WHEN** `(a ; c\n b)` and `(a   ; c\n     b)` are compared
- **THEN** they are token-equivalent

### Requirement: The check compares two source texts

The layer 1 check SHALL accept two source texts, tokenize each independently,
and report whether their token sequences are equivalent.

It MUST accept texts rather than token vectors or trees, so that a caller cannot
compare an artifact the printer produced against itself. Re-lexing the output
text is what gives the check content.

#### Scenario: Texts differing only in layout pass

- **WHEN** `(define (f x)\n  (g x))` and `(define (f x) (g x))` are checked
- **THEN** the check reports equivalence

#### Scenario: The check re-lexes its inputs

- **WHEN** the check is given two texts
- **THEN** each is tokenized from its text
- **AND** no token sequence produced elsewhere is reused

### Requirement: Layer 1 catches what layer 2 cannot

The check SHALL report non-equivalence for each difference that datum
equivalence tolerates: a deleted comment, a deleted or relocated `#;` datum
comment, a changed bracket shape, an expanded abbreviation, a number written in
another radix, a respelled string escape, and a respelled character name.

#### Scenario: A deleted comment is caught

- **WHEN** `(a ; note\n b)` and `(a b)` are checked
- **THEN** the check reports non-equivalence

#### Scenario: A deleted datum comment is caught

- **WHEN** `(a #;(x) b)` and `(a b)` are checked
- **THEN** the check reports non-equivalence

#### Scenario: A datum comment eliding a different form is caught

- **WHEN** `(a #;(x) b)` and `(a b #;(x))` are checked
- **THEN** the check reports non-equivalence

#### Scenario: A changed bracket shape is caught

- **WHEN** `[a b]` and `(a b)` are checked
- **THEN** the check reports non-equivalence

#### Scenario: An expanded abbreviation is caught

- **WHEN** `'x` and `(quote x)` are checked
- **THEN** the check reports non-equivalence

#### Scenario: Respelled lexemes are caught

- **WHEN** `#xff` and `255` are checked, and separately `"\x41;"` and `"A"`, and
  separately `#\nul` and `#\null`
- **THEN** the check reports non-equivalence for each pair

### Requirement: Layer 1 catches lexeme merging and swallowed text

The check SHALL report non-equivalence when the output re-lexes differently from
the input because tokens merged, split, or were consumed by a comment.

#### Scenario: Two lexemes merged into one

- **WHEN** `(- 1)` and `(-1)` are checked
- **THEN** the check reports non-equivalence

#### Scenario: A dot merged into the following datum

- **WHEN** `(a . b)` and `(a .b)` are checked
- **THEN** the check reports non-equivalence

#### Scenario: A line comment swallowing the rest of the line

- **WHEN** `(a ; c\n b)` and `(a ; c b)` are checked
- **THEN** the check reports non-equivalence

#### Scenario: A lost closing delimiter

- **WHEN** `(a b)` and `(a b` are checked
- **THEN** the check does not report equivalence

### Requirement: A failed comparison reports where it failed

When the sequences are not equivalent, the check SHALL report the index of the
first differing position and the token from each side at that position.

Where one sequence has no token at that position, the missing side SHALL be
reported as absent rather than as a token.

#### Scenario: The first differing position is reported

- **WHEN** `(a b)` and `(a c)` are checked
- **THEN** the reported index is that of the differing token
- **AND** the reported tokens have the texts `b` and `c`

#### Scenario: A dropped comment is reported at the comment's position

- **WHEN** `(a ; note\n b)` and `(a b)` are checked
- **THEN** the mismatch is reported at the position of the comment
- **AND** one side reports a comment token and the other reports the code token
  that followed it

#### Scenario: A lost delimiter meets end of input

- **WHEN** `(a b)` and `(a b` are checked
- **THEN** one side reports the closing delimiter and the other reports the
  end-of-file token

#### Scenario: An equivalent pair reports no mismatch

- **WHEN** two token-equivalent texts are checked
- **THEN** no mismatch is reported

### Requirement: Diagnostics on either text fail the check

If tokenizing either text produces a diagnostic, the check SHALL report failure
rather than comparing, and SHALL make those diagnostics available.

#### Scenario: A lexical error fails the check

- **WHEN** `(a #z b)` and `(a #z b)` are checked
- **THEN** the check reports failure
- **AND** it does not report equivalence, even though the texts are identical

#### Scenario: A clean pair reports no diagnostics

- **WHEN** two well-formed texts are checked
- **THEN** no diagnostics are reported
