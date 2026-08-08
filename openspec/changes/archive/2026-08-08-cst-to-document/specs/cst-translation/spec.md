## ADDED Requirements

### Requirement: A CST node translates to a document

The system SHALL provide an operation taking a CST node and returning a
`(pitch doc)` document. The operation SHALL be a pure function of the tree: it
performs no input or output, consults no state outside its argument, and returns
the same document for the same tree.

The operation SHALL be total over the node kinds — document, list, vector,
bytevector, prefix, error, and leaf — including on trees parsed from malformed
input.

The operation MUST NOT depend on any token's recorded offsets, line, or column.
Every decision it makes SHALL be derived from token text and from the child
sequence.

#### Scenario: Translation is a pure function

- **WHEN** the same tree is translated twice
- **THEN** the two documents lay out to the same text under the same cost factory

#### Scenario: Every node kind translates

- **WHEN** a source containing a list, a vector, a bytevector, a quote
  abbreviation, and a datum label is translated
- **THEN** a document is produced for each, and none raises

#### Scenario: A malformed tree still translates

- **WHEN** the source `(a` is parsed and the resulting tree is translated
- **THEN** a document is produced
- **AND** it contains the text of the opening delimiter and of `a`

### Requirement: A token's text is emitted verbatim, once, in order

The document produced for a tree SHALL contain the text of every token in that
tree, exactly once, in source order, character for character. No token's text
SHALL be omitted, duplicated, reordered, or respelled.

A leaf SHALL be emitted from its token's text and MUST NOT be emitted from the
token's parsed value.

The declared-normalizations list is empty, so bracket shape, radix, character
names, boolean spelling, string escape spelling, identifier spelling, and quote
abbreviations SHALL all survive translation unchanged.

#### Scenario: A numeric lexeme is not re-printed

- **WHEN** the source `#xff` is translated and laid out
- **THEN** the output contains `#xff`
- **AND** it does not contain `255`

#### Scenario: Bracket shape survives

- **WHEN** the source `[a b]` is translated and laid out
- **THEN** the output's delimiters are `[` and `]`

#### Scenario: An abbreviation is not expanded

- **WHEN** the source `'x` is translated and laid out
- **THEN** the output is `'x`
- **AND** it does not contain `quote`

#### Scenario: A string escape spelling survives

- **WHEN** the source `"\x41;"` is translated and laid out
- **THEN** the output contains `\x41;`
- **AND** it does not contain a bare `A` in place of the escape

### Requirement: A token spanning lines keeps its interior exactly

A token whose text contains a line ending — a string literal written across
lines, a `#| ... |#` block spanning lines, or a `#;` eliding a datum written
across lines — SHALL be emitted with its interior reproduced exactly.

No indentation SHALL be added to the continuation lines of such a token.
Indentation inside a string literal would change the value the literal denotes,
and indentation inside a comment would rewrite comment contents.

#### Scenario: A multi-line string keeps its own indentation

- **WHEN** a list containing a string literal written across two lines is
  translated and laid out at an indentation greater than zero
- **THEN** the second line of the string begins with exactly the characters that
  followed the line ending in the source
- **AND** no spaces are inserted before them

#### Scenario: A multi-line block comment is not re-indented

- **WHEN** a `#| ... |#` comment spanning three lines is translated and laid out
  inside a form
- **THEN** each of its lines is reproduced with the leading characters it had in
  the source

#### Scenario: A multi-line token has no flat layout

- **WHEN** a list containing a string literal written across two lines is
  translated
- **THEN** the document denotes no single-line layout for that list

### Requirement: A compound node has a default shape of flat, aligned, and hanging

A list, vector, or bytevector node SHALL be translated to a choice among three
layouts:

- **flat** — the opening delimiter, the elements separated by single spaces, and
  the closing delimiter, all on one line;
- **aligned** — the head and the first argument on the opening line, with each
  remaining element beginning at the first argument's column;
- **hanging** — the head on the opening line, with each remaining element on its
  own line indented from the opening delimiter by a fixed amount.

The choice SHALL be made by the cost objective over the whole document, not
greedily at each node.

The hanging alternative SHALL be chosen only when it strictly improves on the
aligned alternative under the objective. The output MUST NOT depend on the
resolver's internal ordering of equally ranked layouts.

This SHALL be achieved structurally rather than by adding a cost: hanging breaks
before the first argument where aligned does not and is otherwise the same set of
breaks, so hanging is always exactly one line taller and never wider. The
translation MUST NOT construct a cost value, because a cost is expressed in the
cost factory's own representation and building one would couple the translation
to a particular factory.

#### Scenario: A form that fits is laid out flat

- **WHEN** `(f a b)` is translated and laid out at a page width that accommodates
  it
- **THEN** the output is `(f a b)` on one line

#### Scenario: A form that does not fit breaks

- **WHEN** a call whose arguments exceed the page width is laid out
- **THEN** the output occupies more than one line
- **AND** every element appears exactly once

#### Scenario: Aligned is preferred to hanging at equal cost

- **WHEN** a form is laid out for which the aligned and hanging renderings have
  the same overflow and the same line count
- **THEN** the aligned rendering is chosen

#### Scenario: Hanging is chosen when it strictly wins

- **WHEN** a form whose head is long enough that aligning under the first
  argument overflows the page width is laid out
- **AND** the hanging rendering does not overflow
- **THEN** the hanging rendering is chosen

#### Scenario: An empty compound is its delimiters

- **WHEN** `()` and `#()` are translated and laid out
- **THEN** the outputs are `()` and `#()`

### Requirement: Delimiters come from their tokens and the closer trails the last element

A compound node's opening delimiter SHALL be emitted from the opening leaf's
token text, so that `(`, `[`, `#(`, `#vu8(`, and `#u8(` are reproduced without
the translation branching on dialect.

The closing delimiter SHALL be emitted directly after the last element with no
opportunity to break between them, except where the last element ends in a
forced line break, in which case the closing delimiter SHALL begin a new line
indented to the compound's own indentation.

An absent closing delimiter SHALL emit nothing.

#### Scenario: A bytevector's opening delimiter is reproduced

- **WHEN** the sources `#vu8(1 2)` and `#u8(1 2)` are translated and laid out
- **THEN** the outputs begin with `#vu8(` and `#u8(` respectively

#### Scenario: The closing delimiter does not move to its own line

- **WHEN** a form too wide to fit is laid out
- **THEN** its closing delimiter follows the last element on the same line

#### Scenario: An unclosed list emits no closing delimiter

- **WHEN** the tree parsed from `(a` is translated and laid out
- **THEN** the output ends with `a`

### Requirement: A prefix binds to its datum and a dot binds to what follows it

A prefix node SHALL emit its marker immediately followed by its datum with no
opportunity for a line break between them. This SHALL hold for every
abbreviation — `'`, `` ` ``, `,`, `,@`, `#'`, `` #` ``, `#,`, `#,@` — and for a
datum label such as `#0=`.

A prefix node whose datum is absent SHALL emit the marker alone.

The `.` leaf of an improper list SHALL be emitted together with the element that
follows it as a single unbreakable unit, separated from it by one space. A line
break MUST NOT be placed between the dot and that element, and the dot MUST NOT
be emitted adjacent to either neighbour without an intervening space.

#### Scenario: A quote never breaks from its datum

- **WHEN** a quoted form long enough to force breaking is laid out
- **THEN** no line ends with `'`

#### Scenario: A datum label never breaks from its datum

- **WHEN** `#0=(a b)` is laid out at a width that forces the list to break
- **THEN** `#0=` and the opening delimiter remain adjacent

#### Scenario: A dotted pair keeps the dot spaced

- **WHEN** `(a . b)` is laid out
- **THEN** the output is `(a . b)`
- **AND** it contains neither `.b` nor `a.`

#### Scenario: A dotted pair breaking keeps the dot with the tail

- **WHEN** an improper list too wide to fit is laid out
- **THEN** no line consists of the dot alone
- **AND** the dot and the tail element appear on the same line

### Requirement: A per-form rule is consulted at exactly one point

The translation SHALL determine a compound node's shape through a single
operation, and no other part of the translation SHALL examine a node's head
element to decide layout.

That operation SHALL currently return the same generic shape for every compound
node, regardless of its head, so that this change introduces no per-form
knowledge.

#### Scenario: Structurally identical forms lay out identically

- **WHEN** `(if a b c)` and `(list a b c)` are laid out at the same width
- **THEN** the two outputs differ only in the head symbol

#### Scenario: The shape operation ignores the head

- **WHEN** the shape operation is applied to compound nodes with different heads
- **THEN** it returns the same shape for each
