# preserved-formatting Specification

## Purpose

What pitch does not re-derive. Layout is reflowed from scratch, with two
declared exceptions, and neither is a set of bytes carried across -- each is a
fact re-derived against the code as laid out, which is what lets it survive a
reflow at all.

The first is blank-line runs: at most one blank line inside a form, at most two
between top-level forms, leading and trailing runs dropped, and the file ending
with exactly one newline. A preserved blank line is emitted as forced breaks, so
a form containing one has no single-line layout at all; collapsing it would
delete the blank line just preserved.

The second is a column of trailing line comments. A trailing comment counts as
aligned when an adjacent source line's trailing comment begins at the same
column, and such a run is put back at one column computed from the reflowed
code, not the column the source used. A run whose alignment would push a line
past the page width keeps single spaces instead.

Everything else a whitespace token holds -- indentation, runs of spaces, line
breaks the layout did not itself choose -- is discarded.
## Requirements

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
