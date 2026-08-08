## ADDED Requirements

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
