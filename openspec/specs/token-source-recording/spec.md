# token-source-recording Specification

## Purpose

Every token returned by the reader carries the exact source substring that
produced it, its offset span, and its parsed value, such that concatenating the
raw text of all tokens reproduces the input byte for byte. Includes the
compatibility guarantee that the existing datum-reading API is unaffected.
## Requirements
### Requirement: Tokens carry their exact source text

The reader SHALL return, for each token, a token value exposing the token kind,
the exact source substring consumed to produce it, the absolute character offsets
of the start and end of that substring, the line and column of both ends of that
substring, and the parsed value that the lexer computed.

The raw text MUST be the verbatim source substring, preserving the original
spelling in every respect: radix and exponent notation, escape sequences,
character-name spelling, boolean spelling, identifier bars and inline hex
escapes, and internal whitespace.

Where a numeric lexeme is valid R6RS or R7RS syntax but the host cannot represent
its value, the token's parsed value SHALL be an opaque Pitch numeric value rather
than a symbol, a guessed number, or a diagnostic. The opaque value SHALL retain
the numeric lexeme needed to compare a fresh read of the same source, but SHALL
NOT be exposed as a host number. A numeric value the host can represent SHALL
continue to use the corresponding host number.

#### Scenario: Token exposes both raw text and parsed value

- **WHEN** the reader reads the source `#xff`
- **THEN** the token's raw text is the string `#xff`
- **AND** the token's parsed value is the number `255`
- **AND** the token's start and end offsets delimit exactly those four characters

#### Scenario: Valid unrepresentable number remains numeric

- **WHEN** the reader on a bounded host reads a valid exact integer larger than the host's range
- **THEN** the token retains its exact source text and span
- **AND** its parsed value is an opaque Pitch numeric value
- **AND** no invalid-syntax diagnostic is produced

#### Scenario: Invalid numeric syntax is still refused

- **WHEN** the reader encounters text that begins as a number but is not valid R6RS or R7RS numeric syntax
- **THEN** it reports invalid numeric syntax rather than constructing an opaque numeric value

#### Scenario: Offsets delimit the raw text

- **WHEN** any token is read from a source string
- **THEN** the substring of the source between the token's start and end offsets
  is equal to the token's raw text

### Requirement: Concatenated token text reproduces the source

Concatenating the raw text of every token returned by the reader, in the order
returned, from the beginning of input through the end-of-file token, SHALL
reproduce the input byte for byte.

This MUST hold for tokens of every kind, including whitespace, line comments,
nested comments, datum comments, directives, and shebang lines, so that no input
character is attributable to no token.

#### Scenario: Round-trip of a whole source file

- **WHEN** the reader tokenizes a source file to end of input
- **AND** the raw text of all returned tokens is concatenated in order
- **THEN** the result is byte-for-byte identical to the file's contents

#### Scenario: Atmosphere is not dropped

- **WHEN** the reader reads source containing leading whitespace, a line comment,
  and a nested `#| ... |#` comment between two data
- **THEN** each of those is returned as its own token with its exact source text
- **AND** the concatenation of all token text reproduces the source

### Requirement: Spellings that the lexer normalizes are recoverable

For every construct whose parsed value discards the source spelling, the token's
raw text SHALL preserve the distinction, so that two inputs with equal parsed
values but different source text yield different raw text.

#### Scenario: Boolean spellings are distinguishable

- **WHEN** the reader reads `#t` and separately reads `#true`
- **THEN** both tokens have the parsed value `#t`
- **AND** their raw texts are `#t` and `#true` respectively

#### Scenario: Character-name spellings are distinguishable

- **WHEN** the reader reads `#\nul` and separately reads `#\null`
- **THEN** both tokens have the same parsed character value
- **AND** their raw texts are `#\nul` and `#\null` respectively
- **AND** the same holds for the `linefeed`/`newline` and `esc`/`escape` pairs

#### Scenario: String escapes are preserved

- **WHEN** the reader reads the source `"\x41;"`
- **THEN** the token's parsed value is the string `A`
- **AND** the token's raw text is the six characters `"\x41;"`

#### Scenario: Identifier spelling is preserved

- **WHEN** the reader reads `|foo|` and separately reads `foo`
- **THEN** both tokens have the parsed value of the symbol `foo`
- **AND** their raw texts are `|foo|` and `foo` respectively

#### Scenario: Bracket shape is preserved

- **WHEN** the reader reads a list written with square brackets
- **THEN** the opening and closing tokens report bracket kinds distinct from
  those reported for parentheses
- **AND** their raw texts are `[` and `]`

### Requirement: Datum comments retain their commented-out text

A datum comment introduced by `#;` SHALL be returned as a single token whose raw
text spans the `#;` marker, any intervening atmosphere, and the entire commented
datum as written in the source.

#### Scenario: Datum comment span covers the commented datum

- **WHEN** the reader reads the source `(a #;(b c) d)`
- **THEN** one returned token has the raw text `#;(b c)`
- **AND** the concatenation of all token text reproduces `(a #;(b c) d)`

### Requirement: The existing datum-reading API is unchanged

Adding source recording MUST NOT change the behavior of the reader's
datum-oriented entry points. `read-annotated`, `read-datum`, and
`detect-scheme-file-type` SHALL accept the same arguments, return the same
values, signal the same conditions, and enforce the same dialect gating as the
vendored reader at the pinned tag.

The two-value lexer that these entry points use SHALL remain available to callers
under a distinct name, so that recording is opt-in rather than imposed.

#### Scenario: Vendored reader test suite still passes

- **WHEN** the vendored `tests/test-reader.sps` suite is run against the derived
  reader, adapted only for the library name
- **THEN** every test passes with the same results as against the pristine
  vendored reader

#### Scenario: Recording does not alter dialect gating

- **WHEN** a construct restricted to one dialect is read in a mode that forbids
  it, such as `#vu8(` in `r7rs` mode
- **THEN** the reader signals the same error it signalled before this change

### Requirement: Tokens carry their start and end position

Each token SHALL expose the line and column at which its source text begins and
the line and column immediately after it ends, following the reader's line and
column conventions.

A token's start position MUST correspond to its start offset, and its end
position MUST correspond to its end offset, so the two descriptions of the span
never disagree.

#### Scenario: First token of a source starts at the origin

- **WHEN** the first token is read from a source string
- **THEN** its start line is 1 and its start column is 0

#### Scenario: Position tracks the offset span

- **WHEN** any token is read from a source string
- **THEN** advancing through the source from the beginning by the token's start
  offset arrives at the token's start line and column
- **AND** advancing by its end offset arrives at its end line and column

#### Scenario: A token confined to one line

- **WHEN** the reader reads the identifier `abc` beginning at line 3, column 4
- **THEN** the token's start line and end line are both 3
- **AND** its start column is 4 and its end column is 7

#### Scenario: A token spanning several lines

- **WHEN** the reader reads a token whose text contains line endings, such as a
  nested `#| ... |#` comment broken across lines
- **THEN** its end line is greater than its start line
- **AND** its end column is measured from the start of the final line, not from
  the start of the token

#### Scenario: Adjacent tokens share a boundary position

- **WHEN** two tokens are read in sequence
- **THEN** the first token's end line and end column equal the second token's
  start line and start column

#### Scenario: A token whose text ends with a line ending

- **WHEN** the reader reads a line comment beginning on line 1 whose text ends
  with the line ending that terminates it
- **THEN** the token's end line is 2 and its end column is 0

The end position denotes the character after the token, so a token terminated by
a line ending reports an end position on the following line even though it
occupies only one. A consumer asking which lines a token covers MUST account for
this rather than reading the end line directly.

### Requirement: Positions are correct on the recursive lexer paths

The recorded position of a token SHALL describe that token, on every path,
including those where the lexer consumes input recursively before deciding what
to return: datum comments, directives, and error recovery in tolerant mode.

The reader's saved line and column MUST NOT be used as a substitute, because they
describe the innermost recursive entry rather than the token returned.

#### Scenario: Datum comment reports its own start

- **WHEN** the reader reads the source `(a\n  #;(b\n     c)\n  d)`
- **THEN** the datum-comment token's start line is 2 and its start column is 2
- **AND** this is the position of the `#;` marker, not of the commented datum
  inside it

#### Scenario: Directive reports its own start

- **WHEN** the reader reads a `#!r6rs` directive that is not at the start of the
  source
- **THEN** the token's start position is that of the `#!` marker

#### Scenario: Positions survive every line ending form

- **WHEN** tokens are read from sources whose lines are separated by line feed,
  carriage return, carriage return with line feed, carriage return with next
  line, next line, line separator, or paragraph separator
- **THEN** each token's start line reflects the number of line endings preceding
  it, counting a carriage return followed by line feed or next line as one
