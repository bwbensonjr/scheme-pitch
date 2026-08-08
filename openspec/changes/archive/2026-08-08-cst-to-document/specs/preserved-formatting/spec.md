## ADDED Requirements

### Requirement: Blank-line runs survive, capped

A run of blank lines in the source SHALL be reproduced in the output, capped at
one blank line between elements of a compound node and at two blank lines between
top-level forms.

The number of blank lines a whitespace leaf represents SHALL be its count of line
endings less one, floored at zero.

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

### Requirement: All other whitespace is discarded and re-derived

Whitespace that does not represent a blank-line run SHALL contribute nothing to
the output beyond the separators the layout derives. Original indentation, runs
of spaces between elements, and line breaks that the layout does not itself
choose SHALL NOT be reproduced.

#### Scenario: Original indentation is discarded

- **WHEN** a form written with idiosyncratic indentation is laid out and fits the
  page width
- **THEN** the output is that form on one line with single spaces between
  elements

#### Scenario: Runs of spaces collapse

- **WHEN** the source `(a     b)` is laid out
- **THEN** the output is `(a b)`

#### Scenario: A line break that the layout does not choose is not reproduced

- **WHEN** a short form written across three lines is laid out at a page width
  that accommodates it
- **THEN** the output is one line

### Requirement: A preserved blank line removes the flat layout

Where a blank line is preserved inside a compound node, that node SHALL have no
single-line layout, because rendering it on one line would delete the blank line
just preserved.

#### Scenario: A form with an internal blank line does not collapse

- **WHEN** a short form written with a blank line between its elements is laid
  out at a page width that would accommodate it on one line
- **THEN** the output still has the blank line
- **AND** the form occupies more than one line

### Requirement: Leading and trailing blank lines are dropped and the file ends with one newline

Blank lines before the first element of the document and after the last SHALL be
dropped. The output SHALL end with exactly one line ending.

#### Scenario: Leading blank lines are removed

- **WHEN** a source beginning with two blank lines is laid out
- **THEN** the output begins with the first form

#### Scenario: Trailing blank lines are removed

- **WHEN** a source ending with several blank lines is laid out
- **THEN** the output ends with the last form followed by exactly one line ending

#### Scenario: A source with no final newline gains one

- **WHEN** a source whose last character is not a line ending is laid out
- **THEN** the output ends with exactly one line ending
