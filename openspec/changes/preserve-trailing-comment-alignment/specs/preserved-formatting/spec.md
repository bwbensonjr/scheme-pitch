## ADDED Requirements

### Requirement: An aligned trailing comment is recognized by a shared column

A *trailing* line comment is a line comment with at least one code token before
it on the same line of the source.

A trailing line comment SHALL be recognized as **aligned** when the source line
immediately before it or immediately after it also ends in a trailing line
comment, and that comment begins at the same column. Any other trailing comment,
and every comment that is not trailing, SHALL be recognized as unaligned.

Recognition SHALL be by shared column and MUST NOT be by the number of spaces
before the comment. The distinction is load-bearing: the widest line of an
aligned run receives a single space, so a rule keyed on padding would fail to
re-recognize that line when its own output is formatted again, and the run would
break apart on the second run.

A comment that is not a line comment SHALL never be recognized as aligned. Block
comments, datum comments and directives are inline-capable — code may follow them
on the same line — so "the comment ends the line" is not a property they have.

#### Scenario: Three comments at one column are aligned

- **WHEN** three consecutive source lines each end in a trailing line comment and
  all three comments begin at the same column
- **THEN** all three are recognized as aligned

#### Scenario: A lone trailing comment is not aligned

- **WHEN** a source line ends in a trailing line comment and neither adjacent
  line ends in one at the same column
- **THEN** it is recognized as unaligned

#### Scenario: Padding without a shared column is not alignment

- **WHEN** two consecutive source lines each end in a trailing line comment
  preceded by several spaces, at different columns
- **THEN** neither is recognized as aligned

#### Scenario: An own-line comment is never aligned

- **WHEN** a line comment is the only thing on its source line
- **THEN** it is recognized as unaligned, whatever column it begins at

#### Scenario: A block comment is never aligned

- **WHEN** two consecutive source lines each end in a block comment at the same
  column
- **THEN** neither is recognized as aligned

### Requirement: An aligned run is re-derived from the reflowed output

Alignment SHALL be applied to the output, and the column SHALL be computed from
the output. The source column SHALL NOT be reproduced: reflowing changes the
width of the code the author chose that column against, so reproducing it would
carry a number that is no longer about anything.

An **output run** SHALL be a maximal sequence of consecutive output lines, each
of which ends in a trailing line comment recognized as aligned. Two lines are
consecutive when no other output line lies between them; a line that does not end
in an aligned trailing comment terminates the run.

Within an output run, every comment SHALL be placed at one column: the smallest
column leaving at least one space between the code and the comment on every line
of the run. The space between a line's last code token and its comment SHALL be
that many spaces and nothing else.

An output run of one line SHALL therefore receive exactly one space, which is
what an unaligned trailing comment receives. No special case is needed for it and
none SHALL be added.

Alignment SHALL change only the run of spaces between a code token and a line
comment. It MUST NOT move a comment to another line, MUST NOT change any comment
text, MUST NOT change any code token, and MUST NOT change any indentation.

#### Scenario: An aligned run is re-derived at a new column

- **WHEN** three lines whose comments were aligned in the source are laid out and
  the reflowed code has different widths than the source did
- **THEN** all three comments begin at one column in the output
- **AND** that column is one greater than the end of the widest code among the
  three
- **AND** the widest line has exactly one space before its comment

#### Scenario: The source column is not reproduced

- **WHEN** an aligned run whose source column is far to the right of the reflowed
  code is laid out
- **THEN** the output column is derived from the reflowed code, not from the
  source

#### Scenario: An intervening line ends a run

- **WHEN** two aligned trailing comments in the output are separated by a line
  with no trailing comment
- **THEN** they belong to different runs and are aligned independently

#### Scenario: A run of one gets a single space

- **WHEN** an output line ending in an aligned trailing comment has no adjacent
  output line ending in one
- **THEN** it has exactly one space before its comment

#### Scenario: Nothing but the gap changes

- **WHEN** a source with aligned trailing comments is formatted
- **THEN** the output differs from the unaligned rendering only in runs of spaces
  between code tokens and line comments

### Requirement: Alignment is declined rather than bought with an overflowing line

An output run SHALL be aligned only if, after alignment, every line of the run
ends at or before the configured page width. Otherwise no line of that run SHALL
be padded, and each keeps the single space it was rendered with.

The decision SHALL be made per run. A run that cannot be aligned SHALL NOT affect
any other run.

Where the system cannot establish the correspondence between the comments it
recognized in the source and the comments present in the output — for instance
because the two differ in number — it SHALL decline to align anything and SHALL
leave the rendered text as it stands. It MUST NOT guess at a pairing, and it MUST
NOT suppress the output checks, which are what report such a discrepancy.

#### Scenario: A run that would overflow is not aligned

- **WHEN** aligning a run would put a comment's last character past the page
  width
- **THEN** every line of that run keeps a single space before its comment

#### Scenario: One run overflowing does not affect another

- **WHEN** a source contains one run that can be aligned and one that cannot
- **THEN** the first is aligned and the second is not

#### Scenario: A line already past the width is not padded further

- **WHEN** a line of a run already ends past the page width with a single space
  before its comment
- **THEN** that run is not aligned

### Requirement: Alignment holds as a fixed point

Formatting the output of a successful format SHALL produce a byte-identical
result, alignment included.

This follows from recognition being by shared column: after a run is aligned,
every comment in it begins at one column, so re-formatting recognizes the same
run and, over unchanged code, computes the same column.

A run that was declined SHALL also be stable: its comments carry single spaces at
differing columns, so they are recognized as unaligned on the next run and are
left alone.

#### Scenario: A second run changes nothing

- **WHEN** a source with aligned trailing comments is formatted and its output is
  formatted again at the same width
- **THEN** the two outputs are byte identical

#### Scenario: The widest line of a run does not break the run

- **WHEN** the output of an aligned run — in which the widest line carries a
  single space and the others carry several — is formatted again
- **THEN** the run is recognized whole
- **AND** the output is byte identical

#### Scenario: A declined run is stable

- **WHEN** the output of a run that was declined for width is formatted again
- **THEN** the output is byte identical

## MODIFIED Requirements

### Requirement: All other whitespace is discarded and re-derived

Whitespace that does not represent a blank-line run or an aligned trailing
comment's gap SHALL contribute nothing to the output beyond the separators the
layout derives. Original indentation, runs of spaces between elements, and line
breaks that the layout does not itself choose SHALL NOT be reproduced.

The gap before an aligned trailing comment is not an exception to this. The
original run of spaces is discarded like any other; what survives is the *fact*
that a column was shared, and the gap that appears in the output is computed
from the reflowed code. No number from the source reaches the output.

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

#### Scenario: The gap before an unaligned trailing comment collapses

- **WHEN** a source line ends in a trailing comment preceded by several spaces,
  and no adjacent line ends in a comment at the same column
- **THEN** the output has exactly one space before that comment
