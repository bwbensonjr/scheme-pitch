## MODIFIED Requirements

### Requirement: Tokens carry their exact source text

The reader SHALL return, for each token, a token value exposing the token kind,
the exact source substring consumed to produce it, the absolute character offsets
of the start and end of that substring, the line and column of both ends of that
substring, and the parsed value that the underlying lexer computed.

The raw text MUST be the verbatim source substring, preserving the original
spelling in every respect: radix and exponent notation, escape sequences,
character-name spelling, boolean spelling, identifier bars and inline hex
escapes, and internal whitespace.

#### Scenario: Token exposes both raw text and parsed value

- **WHEN** the reader reads the source `#xff`
- **THEN** the token's raw text is the string `#xff`
- **AND** the token's parsed value is the number `255`
- **AND** the token's start and end offsets delimit exactly those four characters

#### Scenario: Offsets delimit the raw text

- **WHEN** any token is read from a source string
- **THEN** the substring of the source between the token's start and end offsets
  is equal to the token's raw text

## ADDED Requirements

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
