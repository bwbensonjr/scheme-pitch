## ADDED Requirements

### Requirement: A line comment is always followed by a line break

A line comment leaf SHALL be emitted as its token text with exactly one trailing
line ending removed, followed by a forced line break. The line endings recognized
for that removal SHALL be the same seven the reader's grammar counts, with the
two-character forms counting as one.

There SHALL be no path through the translation that emits a line comment without
a following forced break, including for a comment that ends the source with no
terminating line ending.

The system SHALL additionally assert, where items are sequenced, that no
separator is emitted after an element ending in a forced break. This is the
second of two independent guards on the single most dangerous defect a Lisp
formatter can have — a comment that swallows the code after it.

#### Scenario: A comment does not swallow what follows it

- **WHEN** the source `(a ; c\n b)` is laid out
- **THEN** `b` appears on a line after the comment
- **AND** the output re-tokenizes to the same tokens as the input

#### Scenario: A comment at end of input still gets a break

- **WHEN** a source ending in `; last` with no trailing line ending is laid out
- **THEN** the output ends with a line ending

#### Scenario: A form containing a line comment has no flat layout

- **WHEN** the source `(a ; c\n b)` is translated
- **THEN** the document denotes no single-line layout
- **AND** this holds however wide the page is

### Requirement: A comment written after code on its line stays on that line

A comment leaf with no line ending between it and the preceding datum in the same
node SHALL be emitted attached to that datum, separated by a single space that
offers no opportunity to break.

Attachment SHALL be determined from the text of the intervening whitespace, not
from any recorded token position.

#### Scenario: A trailing comment stays trailing

- **WHEN** the source `(a ; note\n b)` is laid out
- **THEN** the comment appears on the same line as `a`

#### Scenario: A trailing comment stays trailing when the form breaks

- **WHEN** a form wide enough to force breaking has a comment after its first
  element on the same line
- **THEN** the comment is still on the line that first element is laid out on

#### Scenario: A trailing comment may exceed the page width

- **WHEN** attaching a comment to its element would exceed the page width
- **THEN** the comment is still attached
- **AND** the overflow is priced by the cost objective rather than repaired by
  moving the comment

### Requirement: A comment written on its own line stays on its own line

A comment leaf separated from the preceding datum by whitespace containing a line
ending, or having no preceding datum in its node, SHALL be emitted as an element
of its own, preceded by a line break.

#### Scenario: An own-line comment is not pulled up

- **WHEN** the source `(a\n ; note\n b)` is laid out
- **THEN** the comment is on a line of its own
- **AND** neither `a` nor `b` shares that line

#### Scenario: A comment before the first element stays first

- **WHEN** the source `(; note\n a b)` is laid out
- **THEN** the comment precedes `a` in the output

### Requirement: A comment never crosses a code token

The order of comments relative to data SHALL be identical in the output and the
input. No comment SHALL be emitted before a datum that precedes it in the source,
or after a datum that follows it.

This is not a preference. A comment that crosses a code token documents different
code, which is a change of meaning rather than of layout, and token equivalence
rejects it.

#### Scenario: Interleaving is preserved

- **WHEN** any source is formatted
- **THEN** the interleaved sequence of code and comment tokens in the output is
  identical to the input's

#### Scenario: A comment between two elements stays between them

- **WHEN** the source `(a ; note\n b)` is laid out
- **THEN** the comment appears after `a` and before `b`

### Requirement: A comment before a closing delimiter puts the delimiter on a new line

Where the last element of a compound node ends in a forced line break, the
closing delimiter SHALL be emitted on the following line, indented to the
compound node's own indentation rather than to its elements' indentation.

#### Scenario: A trailing comment forces the closer down

- **WHEN** the source `(a ; note\n )` is laid out
- **THEN** the comment is on the same line as `a`
- **AND** the closing delimiter is on the next line

#### Scenario: The closer returns to the opening delimiter's indentation

- **WHEN** a nested form whose last element is a line comment is laid out
- **THEN** the closing delimiter is indented to the column its opening delimiter
  was laid out at

### Requirement: Block comments, datum comments, and directives are inline-capable

A `#| ... |#` comment, a `#;` datum comment, and a reader directive such as
`#!r6rs` or `#!fold-case` SHALL be emitted as ordinary elements that impose no
forced line break, and SHALL be separated from their neighbours by an ordinary
separator.

A `#;` datum comment SHALL be emitted as the single opaque token the lexer
produced, with the elided datum reproduced as written. The translation MUST NOT
build or re-layout the structure inside it.

A shebang line SHALL be emitted first in the document and SHALL be followed by a
line break.

#### Scenario: A datum comment stays on the line

- **WHEN** the source `(a #;(b c) d)` is laid out at a width that accommodates it
- **THEN** the output is `(a #;(b c) d)` on one line

#### Scenario: A datum comment's interior is not reformatted

- **WHEN** the source `(a #;(b    c) d)` is laid out
- **THEN** the output contains `#;(b    c)` with its spacing unchanged

#### Scenario: A block comment can share a line

- **WHEN** the source `(a #| note |# b)` is laid out at a width that accommodates
  it
- **THEN** the output is `(a #| note |# b)` on one line

#### Scenario: A shebang leads the file

- **WHEN** a source beginning with a shebang line is laid out
- **THEN** the output's first line is that shebang
- **AND** the first form begins on a later line
