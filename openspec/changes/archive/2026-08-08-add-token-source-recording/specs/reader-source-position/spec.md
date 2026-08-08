## ADDED Requirements

### Requirement: The reader tracks an absolute character offset

The reader SHALL maintain a zero-based count of characters consumed from the
input, readable by callers, and SHALL increment it exactly once per character
consumed.

The offset MUST be expressed in characters, consistently with the token start and
end offsets, so that a caller holding the source as a string can index it
directly with the offsets a token reports.

#### Scenario: Offset advances with consumption

- **WHEN** the reader has consumed the first ten characters of its input
- **THEN** the reported offset is 10

#### Scenario: Offset starts at zero

- **WHEN** a reader is created over an input port and nothing has been read
- **THEN** the reported offset is 0

### Requirement: Line and column are correct for all recognized line endings

The reader SHALL advance its line counter and reset its column counter for every
line ending recognized by the R6RS and R7RS grammars: line feed, carriage return,
carriage return followed by line feed, U+0085 next line, U+2028 line separator,
and U+2029 paragraph separator.

A carriage return immediately followed by a line feed MUST count as a single line
ending, not two.

#### Scenario: Carriage-return-only line endings advance the line

- **WHEN** the reader consumes source whose lines are separated by `#\return`
  alone
- **THEN** the reported line number after each separator is one greater than
  before
- **AND** the reported column is reset

#### Scenario: CRLF counts once

- **WHEN** the reader consumes a carriage return immediately followed by a line
  feed
- **THEN** the line number advances by exactly 1

#### Scenario: Unicode line separators advance the line

- **WHEN** the reader consumes U+0085, U+2028, or U+2029
- **THEN** the line number advances by 1 and the column is reset

#### Scenario: Positions agree with the comment lexer

- **WHEN** source containing non-line-feed line endings inside a line comment is
  read
- **THEN** the line and column reported after the comment match the line and
  column implied by counting those separators as line endings
