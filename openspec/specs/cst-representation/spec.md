# cst-representation Specification

## Purpose

The shape of the concrete syntax tree: leaf nodes holding exactly one reader
token, interior nodes holding an ordered child sequence, and the node kinds
covering every construct the lexer emits. Whitespace and comments are ordinary
children rather than attached trivia, a leaf's text is its token's text, and
bracket shape is read from tokens rather than stored on nodes. The
representation never branches on dialect, and the leaf sequence of a tree is
exactly the token sequence it was parsed from.
## Requirements

### Requirement: A CST is a tree of leaf and interior nodes

The system SHALL provide a concrete syntax tree in which a leaf node holds
exactly one reader token and an interior node holds an ordered sequence of child
nodes.

Every token produced for a source SHALL appear in exactly one leaf, and no leaf
SHALL hold a token that the reader did not produce for that source.

#### Scenario: A leaf exposes its token

- **WHEN** a leaf node is examined
- **THEN** the token it holds is available
- **AND** the token's kind, text, offsets, and line and column are reachable
  through it

#### Scenario: An interior node exposes its children in source order

- **WHEN** the source `(a b)` is parsed
- **THEN** the resulting list node's children are the leaves for `a`, the
  whitespace between them, and `b`, in that order

### Requirement: A leaf's text is the token's text

The text of a leaf node SHALL be the text recorded on its token. The token's
character offsets and line and column positions SHALL remain reachable for
diagnostic purposes but MUST NOT be the authority for a node's text.

No node SHALL store a copy of its text that could disagree with its token's text.

#### Scenario: Spelling survives into the tree

- **WHEN** the source `#xff` is parsed
- **THEN** the leaf's text is `#xff`
- **AND** the leaf's text is not the printed form of the token's parsed value

#### Scenario: Case folding does not alter leaf text

- **WHEN** a source containing a `#!fold-case` directive followed by the
  identifier `Foo` is parsed
- **THEN** the leaf's text for that identifier is `Foo`

### Requirement: Whitespace and comments are ordinary children

Whitespace, line comments, nested `#| ... |#` comments, `#;` datum comments,
directives, and a shebang line SHALL be members of the enclosing node's child
sequence, in source order, positioned exactly where they occur.

These MUST NOT be attached to a neighboring token as leading or trailing trivia,
and MUST NOT be stored anywhere that construction of a node could omit them.

The system SHALL provide a predicate distinguishing a trivia leaf from a datum
node, so that consumers can skip trivia without inspecting token kinds directly.

#### Scenario: A comment between two elements is a sibling of both

- **WHEN** the source `(a ; note\n b)` is parsed
- **THEN** the list node's children include a leaf for the comment
- **AND** that leaf is positioned after the leaf for `a` and before the leaf for
  `b`

#### Scenario: A comment before a closing delimiter is retained

- **WHEN** the source `(a ; trailing\n )` is parsed
- **THEN** the comment leaf is a child of the list node
- **AND** the list node's closing delimiter is still present

#### Scenario: Trivia are distinguishable from data

- **WHEN** a node's children contain both whitespace and data
- **THEN** the trivia predicate is true for the whitespace and comment children
  and false for the data children

### Requirement: Interior nodes name their opening and closing delimiters

A list, vector, or bytevector node SHALL hold its opening leaf and its closing
leaf in dedicated positions distinct from its interior child sequence.

The closing leaf MAY be absent, which SHALL denote a node whose delimiter was
never closed in the source.

#### Scenario: A closed list reports both delimiters

- **WHEN** the source `(a)` is parsed
- **THEN** the list node's opening leaf has the text `(`
- **AND** its closing leaf has the text `)`
- **AND** neither delimiter appears in the interior child sequence

#### Scenario: An unclosed list reports an absent closing delimiter

- **WHEN** the source `(a` is parsed
- **THEN** the list node's closing leaf is absent
- **AND** the opening leaf and the leaf for `a` are still present

### Requirement: Bracket shape is read from tokens, not stored on nodes

A list node SHALL NOT record its bracket shape as a property of the node. The
distinction between `(...)` and `[...]` SHALL be determined from the kinds of the
opening and closing leaves' tokens.

#### Scenario: Parenthesized and bracketed lists differ only in their delimiters

- **WHEN** the sources `(a)` and `[a]` are parsed
- **THEN** both produce a list node of the same kind
- **AND** the opening leaves' texts are `(` and `[` respectively
- **AND** the closing leaves' texts are `)` and `]` respectively

### Requirement: The node kinds cover every construct the lexer emits

The system SHALL provide node kinds for: a document, a list, a vector, a
bytevector, a prefix, an error region, and a leaf.

Vectors and bytevectors SHALL be list-like nodes whose children are parsed
normally, not opaque nodes holding unparsed text, so that comments inside them
are ordinary children.

#### Scenario: A vector is a list-like node

- **WHEN** the source `#(a ; note\n b)` is parsed
- **THEN** the result is a vector node whose children include leaves for `a`, the
  comment, and `b`
- **AND** the comment is not discarded

#### Scenario: A bytevector is a list-like node

- **WHEN** the source `#vu8(1 2 3)` is parsed
- **THEN** the result is a bytevector node whose opening leaf has the text
  `#vu8(`
- **AND** its children include the leaves for `1`, `2`, and `3`

### Requirement: The representation does not branch on dialect

The node kinds and their contents SHALL be identical regardless of which dialect
the source is written in. Dialect-specific spelling SHALL be carried by token
text alone.

#### Scenario: R6RS and R7RS bytevectors produce the same node kind

- **WHEN** the sources `#vu8(1)` and `#u8(1)` are parsed
- **THEN** both produce a bytevector node of the same kind
- **AND** their opening leaves' texts are `#vu8(` and `#u8(` respectively

#### Scenario: Boolean spellings do not affect node structure

- **WHEN** the sources `#t` and `#true` are parsed
- **THEN** both produce a leaf of the same kind
- **AND** their texts are `#t` and `#true` respectively

### Requirement: Abbreviations and datum labels are prefix nodes

A quote, quasiquote, unquote, unquote-splicing, syntax, quasisyntax, unsyntax,
or unsyntax-splicing abbreviation SHALL produce a prefix node holding the
abbreviation leaf and the datum it prefixes. A datum label such as `#0=` SHALL
produce a prefix node of the same kind.

An abbreviation MUST NOT be rewritten to its expanded form. Trivia occurring
between the marker and the datum SHALL be children of the prefix node.

The prefixed datum MAY be absent, which SHALL denote a marker with no following
datum in the source.

#### Scenario: A quote abbreviation is preserved

- **WHEN** the source `'x` is parsed
- **THEN** the result is a prefix node whose marker leaf has the text `'`
- **AND** whose prefixed datum is the leaf for `x`
- **AND** no node has the text `quote`

#### Scenario: Nested abbreviations nest as prefix nodes

- **WHEN** the source `,@x` is parsed
- **THEN** the marker leaf's text is `,@`
- **AND** the prefixed datum is the leaf for `x`

#### Scenario: Trivia between a marker and its datum are retained

- **WHEN** the source `' ; why\n x` is parsed
- **THEN** the prefix node's children include the whitespace and comment leaves
- **AND** the prefixed datum is the leaf for `x`

#### Scenario: A datum label is a prefix and a reference is a leaf

- **WHEN** the source `#0=(a . #0#)` is parsed
- **THEN** `#0=` is the marker leaf of a prefix node whose datum is the list node
- **AND** `#0#` is a leaf inside that list

### Requirement: Datum comments are opaque leaves

A `#;` datum comment SHALL be a single leaf whose text spans the marker, any
intervening atmosphere, and the commented datum as written. The parser MUST NOT
build nodes for the structure inside it.

#### Scenario: A datum comment is one leaf

- **WHEN** the source `(a #;(b c) d)` is parsed
- **THEN** the list node's children include exactly one leaf whose text is
  `#;(b c)`
- **AND** no list node is built for `(b c)`

#### Scenario: A datum comment is trivia

- **WHEN** a `#;` leaf is tested with the trivia predicate
- **THEN** the predicate is true

### Requirement: Improper tails keep the dot as an ordinary child

The `.` of an improper list SHALL be a leaf in the enclosing list node's child
sequence. There SHALL be no separate node kind or field for the tail.

The system SHALL provide a predicate reporting whether a list node is improper.

#### Scenario: The dot is a sibling of the elements

- **WHEN** the source `(a . b)` is parsed
- **THEN** the list node's children include leaves for `a`, the dot, and `b` in
  that order
- **AND** the improper-list predicate is true for that node

#### Scenario: Trivia around the dot are retained

- **WHEN** the source `(a . ; why\n b)` is parsed
- **THEN** the comment leaf is a child of the list node
- **AND** the improper-list predicate is true for that node

### Requirement: The leaf sequence of a tree equals its token sequence

Walking a tree's leaves in order SHALL yield exactly the tokens that were parsed,
in the same order, with none added, dropped, duplicated, or reordered.

This SHALL hold for malformed input as well as well-formed input.

#### Scenario: Leaves recover the token vector

- **WHEN** a source is tokenized and the resulting token vector is parsed
- **THEN** the tokens held by the tree's leaves, walked in order, are equal to
  that token vector element by element

#### Scenario: Leaves recover the token vector for malformed input

- **WHEN** a source with an unclosed delimiter is tokenized and parsed
- **THEN** the tokens held by the tree's leaves, walked in order, are still equal
  to that token vector element by element
