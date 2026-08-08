## MODIFIED Requirements

### Requirement: Blank-line runs survive, capped

A run of blank lines in the source SHALL be reproduced in the output, capped at
one blank line between elements of a compound node and at two blank lines between
top-level forms.

The number of blank lines a whitespace leaf represents SHALL be its count of line
endings, less one for the ending that terminated the preceding element's line,
floored at zero.

Where the preceding element's own text already carried the line ending that
terminated its line — which is true of a line comment and of a shebang, and of
nothing else — no ending SHALL be discounted, and every line ending in the
whitespace leaf SHALL count as a blank line.

#### Scenario: A blank line inside a form is kept

- **WHEN** a two-element form written with one blank line between its elements is
  laid out
- **THEN** the output has one blank line between them

#### Scenario: Two blank lines inside a form become one

- **WHEN** a form written with two blank lines between two elements is laid out
- **THEN** the output has one blank line between them

#### Scenario: Two blank lines between top-level forms are kept

- **WHEN** two top-level forms separated by two blank lines are laid out
- **THEN** the output has two blank lines between them

#### Scenario: Three blank lines between top-level forms become two

- **WHEN** two top-level forms separated by three blank lines are laid out
- **THEN** the output has two blank lines between them

#### Scenario: A single line ending is not a blank line

- **WHEN** two top-level forms on consecutive lines are laid out
- **THEN** the output has no blank line between them

#### Scenario: A blank line after a line comment is kept

- **WHEN** a source in which a line comment is followed by one blank line and
  then a form is laid out
- **THEN** the output has one blank line between the comment and the form

#### Scenario: A blank line after a comment inside a form is kept

- **WHEN** an element carrying a trailing line comment is followed by one blank
  line and another element
- **THEN** the output has one blank line between them

#### Scenario: Two adjacent line comments have no blank line between them

- **WHEN** two line comments written on consecutive lines are laid out
- **THEN** the output has no blank line between them

#### Scenario: A run after a comment is capped like any other

- **WHEN** a line comment is followed by four blank lines and then a top-level
  form
- **THEN** the output has two blank lines between them

## ADDED Requirements

### Requirement: A preserved blank line is empty

A blank line in the output SHALL contain no characters. It MUST NOT hold the
enclosing indentation, or any other whitespace, as trailing content.

The resolver indents after every line break, so the break that opens a blank line
SHALL be taken at indentation zero. This SHALL hold whichever part of the
translation emitted that break, including where it is the forced break belonging
to the preceding line comment rather than one emitted by the item sequencer.

#### Scenario: A blank line between top-level forms is empty

- **WHEN** two top-level forms separated by a blank line are laid out
- **THEN** the blank line contains no characters

#### Scenario: A blank line inside an indented form is empty

- **WHEN** a nested form containing a blank line between two elements is laid out
  at an indentation greater than zero
- **THEN** the blank line contains no characters
- **AND** it does not hold the enclosing indentation

#### Scenario: A blank line opened by a comment's own break is empty

- **WHEN** an element carrying a trailing line comment inside a nested form is
  followed by a blank line
- **THEN** the blank line contains no characters

### Requirement: A comment followed by a blank line is laid out rather than refused

The translation SHALL lay out every well-formed source. A line comment followed
by one or more blank lines SHALL NOT raise.

The assertion guarding against a separator being emitted after an element that
ends in a forced break SHALL test that condition directly. It MUST NOT test it by
comparing the document a branch produced against the separator, because distinct
branches may produce the same document value.

#### Scenario: A top-level comment followed by one blank line does not raise

- **WHEN** a source of a line comment, one blank line, and a form is laid out
- **THEN** a document is produced and nothing raises

#### Scenario: A comment inside a form followed by a blank line does not raise

- **WHEN** a source in which an element's trailing line comment is followed by a
  blank line and another element is laid out
- **THEN** a document is produced and nothing raises
