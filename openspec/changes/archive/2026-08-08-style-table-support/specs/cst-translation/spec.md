## MODIFIED Requirements

### Requirement: A CST node translates to a document

The system SHALL provide an operation taking a CST node and returning a
`(pitch doc)` document. The operation SHALL accept an optional dialect naming the
style table to consult, defaulting to the shared core table. It SHALL be a pure
function of the tree and that dialect: it performs no input or output, consults
no state outside its arguments, and returns the same document for the same tree
under the same dialect.

The operation SHALL be total over the node kinds — document, list, vector,
bytevector, prefix, error, and leaf — including on trees parsed from malformed
input.

The operation MUST NOT depend on any token's recorded offsets, line, or column.
Every decision it makes SHALL be derived from token text, from token values, and
from the child sequence.

A token's value MAY be read only to select a layout, which is to say only to
decide which whitespace is emitted. Every character the operation emits SHALL
come from token text. Comment classification SHALL continue to be derived from
the text of whitespace children rather than from any recorded position.

#### Scenario: Translation is a pure function

- **WHEN** the same tree is translated twice under the same dialect
- **THEN** the two documents lay out to the same text under the same cost factory

#### Scenario: Every node kind translates

- **WHEN** a source containing a list, a vector, a bytevector, a quote
  abbreviation, and a datum label is translated
- **THEN** a document is produced for each, and none raises

#### Scenario: A malformed tree still translates

- **WHEN** the source `(a` is parsed and the resulting tree is translated
- **THEN** a document is produced
- **AND** it contains the text of the opening delimiter and of `a`

#### Scenario: The dialect defaults to the shared core

- **WHEN** a tree is translated with no dialect given
- **THEN** the result is the same as translating it under the shared core table

#### Scenario: A recorded position is never read

- **WHEN** a tree whose tokens carry deliberately wrong offsets, lines, and
  columns is translated
- **THEN** the document is identical to the one produced from correct positions

### Requirement: A compound node has a default shape of flat, aligned, and hanging

A list, vector, or bytevector node for which no style applies SHALL be translated
to a choice among three layouts:

- **flat** — the opening delimiter, the elements separated by single spaces, and
  the closing delimiter, all on one line;
- **aligned** — the head and the first argument on the opening line, with each
  remaining element beginning at the first argument's column;
- **hanging** — the head on the opening line, with each remaining element on its
  own line indented from the opening delimiter by a fixed amount.

This SHALL be the fallback for every form a style table does not match, and it
SHALL remain correct independently of any table, since it is what a form with no
entry is laid out by.

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

#### Scenario: A form with no table entry takes this shape

- **WHEN** `(list a b c)` is laid out at a width that forces breaking
- **THEN** it takes the aligned or hanging rendering described here

### Requirement: A per-form rule is consulted at exactly one point

The translation SHALL determine a compound node's shape through a single
operation, and no other part of the translation SHALL examine a node's head
element to decide layout.

That operation SHALL consult a style table selected by the dialect, keyed by the
head's parsed symbol, and SHALL return either the shape the matching style
describes or the generic shape. It SHALL be the only place in the translation
where a head symbol is read and the only place a style table is consulted.

A per-form layout rule SHALL be expressible as a table entry alone. Adding,
changing, or removing one MUST NOT require an edit to any emitter.

#### Scenario: Structurally identical forms with different styles differ

- **WHEN** `(when a b)` and `(list a b)` are laid out at a width that forces
  breaking
- **THEN** the two outputs differ in more than the head symbol

#### Scenario: Structurally identical forms with no entry stay identical

- **WHEN** `(if a b c)` and `(list a b c)` are laid out at the same width
- **THEN** the two outputs differ only in the head symbol

#### Scenario: The head is read in one place

- **WHEN** the translation is inspected
- **THEN** exactly one operation reads a head element to decide layout
