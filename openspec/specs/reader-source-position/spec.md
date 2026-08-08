# reader-source-position Specification

## Purpose

The reader tracks an absolute character offset, and reports line and column
correctly for every line ending recognized by the R6RS/R7RS grammars, not only
line feed.
## Requirements
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

### Requirement: Line and column conventions

The reader SHALL report lines counting from 1 and columns counting from 0.

A reported position SHALL denote the next character to be consumed, so that a
position taken before reading a token is the position of that token's first
character, and a position taken after reading it is the position immediately
following its last character.

These conventions MUST be the same ones the reader uses for the source
information attached to annotations, so that positions obtained from tokens and
from annotations can be compared without translation.

#### Scenario: A fresh reader is at the origin

- **WHEN** a reader is created over an input port and nothing has been read
- **THEN** the reported line is 1 and the reported column is 0

#### Scenario: Column counts characters within the current line

- **WHEN** the reader has consumed three characters, none of them a line ending
- **THEN** the reported line is 1 and the reported column is 3

#### Scenario: A line ending resets the column

- **WHEN** the reader consumes a line ending
- **THEN** the reported line is one greater than before
- **AND** the reported column is 0

