# cst-construction Specification

## Purpose

How a CST is built: tokenizing a source into an explicit, inspectable token
vector under a tolerant, dialect-permissive reader, and parsing that vector into
a document node. Diagnostics carry a message and the position of the token they
concern, and cleanliness is the diagnostics list being empty. Parsing always
produces a tree, never raises on malformed input, and never guesses at a repair
by inserting, dropping, or substituting a token.
## Requirements

### Requirement: Tokenizing produces an explicit token vector

The system SHALL provide a tokenize operation that drives the reader to end of
input and returns the complete sequence of tokens as a vector, together with a
list of diagnostics.

The token sequence SHALL be materialized as an inspectable value rather than
consumed only as a stream, so that lexical results and parsing results can be
examined independently of each other.

The end-of-file token SHALL be the last element of the vector.

#### Scenario: Every token is present in order

- **WHEN** a source is tokenized
- **THEN** the returned vector contains every token the reader produced, in the
  order produced, ending with the end-of-file token

#### Scenario: The token vector can be parsed without re-lexing

- **WHEN** a token vector obtained from tokenizing is passed to the parser
- **THEN** a tree is produced without the source being read again

### Requirement: Tokenizing is tolerant and never rejects on dialect grounds

The tokenize operation SHALL run the reader in tolerant mode, so that a lexical
error is recorded as a diagnostic and lexing continues to end of input rather
than aborting.

The reader SHALL be used in its permissive union mode, so that constructs valid
in either R6RS or R7RS are accepted regardless of which dialect the file is
otherwise written in.

#### Scenario: A lexical error does not abort tokenizing

- **WHEN** a source containing a malformed lexeme is tokenized
- **THEN** a token vector reaching the end-of-file token is still returned
- **AND** the diagnostics list is non-empty

#### Scenario: Both bytevector spellings are accepted

- **WHEN** sources containing `#vu8(1)` and `#u8(1)` are tokenized
- **THEN** neither produces a dialect-related diagnostic

### Requirement: Diagnostics carry a message and a token position

Each diagnostic SHALL record a human-readable message and the token it concerns,
and SHALL report the line and column of that token.

The position reported MUST be derived from the token rather than from the
reader's saved line and column, which describe the innermost recursive lexer
entry rather than the token returned.

#### Scenario: A diagnostic reports the position of its token

- **WHEN** a diagnostic is produced for a token
- **THEN** its reported line and column are the token's start line and start
  column

### Requirement: Parsing builds a document node from a token vector

The parser SHALL accept a token vector and return two values: a document node
covering the whole input, and a list of diagnostics.

The document node's children SHALL be the top-level data and trivia, in source
order.

#### Scenario: Several top-level forms

- **WHEN** the source `(a)\n\n(b)` is parsed
- **THEN** the document node's children include two list nodes separated by the
  whitespace leaf

#### Scenario: Leading trivia are children of the document

- **WHEN** a source beginning with a shebang line followed by a form is parsed
- **THEN** the shebang leaf is the first child of the document node

#### Scenario: An empty source parses

- **WHEN** an empty source is parsed
- **THEN** a document node is returned with no data children
- **AND** the diagnostics list is empty

### Requirement: A tree is clean exactly when its diagnostics list is empty

Cleanliness SHALL be reported by the diagnostics list alone. The system MUST NOT
represent it as a separate mutable flag that could disagree with the list.

#### Scenario: Well-formed input yields no diagnostics

- **WHEN** a well-formed source is parsed
- **THEN** the diagnostics list is empty

#### Scenario: Malformed input yields diagnostics

- **WHEN** a source with a structural malformation is parsed
- **THEN** the diagnostics list is non-empty

### Requirement: Closing delimiters must match their opening delimiter

A list opened with `(` SHALL be closed with `)`, a list opened with `[` SHALL be
closed with `]`, and a vector or bytevector SHALL be closed with `)`.

A closing delimiter of the wrong shape SHALL close the node and produce a
diagnostic. The mismatched leaf MUST be retained as that node's closing leaf
rather than discarded or replaced.

#### Scenario: Mismatched shapes close the node and diagnose

- **WHEN** the source `(a]` is parsed
- **THEN** the list node's opening leaf has the text `(` and its closing leaf has
  the text `]`
- **AND** the diagnostics list is non-empty

#### Scenario: Matching shapes do not diagnose

- **WHEN** the sources `(a)` and `[a]` are parsed
- **THEN** neither produces a diagnostic

### Requirement: Parsing always produces a tree

The parser SHALL return a tree for every input, including input it diagnoses.
It MUST NOT raise on malformed input, because a formatter is run against
half-typed buffers.

Malformed constructs SHALL be represented as follows, and in every case all
tokens involved SHALL be retained in the tree:

- an opening delimiter with no matching close produces a node whose closing leaf
  is absent
- a closing delimiter with no matching open produces an error node containing
  that leaf
- a prefix marker with no following datum produces a prefix node whose datum is
  absent
- a misplaced dot is retained as a leaf in its enclosing list

#### Scenario: Unclosed delimiter at end of input

- **WHEN** the source `(a (b` is parsed
- **THEN** two nested list nodes are produced, each with an absent closing leaf
- **AND** the diagnostics list is non-empty

#### Scenario: Unexpected closing delimiter

- **WHEN** the source `a)` is parsed
- **THEN** the document contains the leaf for `a` and an error node containing
  the leaf for `)`
- **AND** the diagnostics list is non-empty

#### Scenario: Prefix marker with no datum

- **WHEN** the source `'` is parsed
- **THEN** a prefix node is produced whose marker leaf has the text `'` and whose
  datum is absent
- **AND** the diagnostics list is non-empty

#### Scenario: A dot in an invalid position

- **WHEN** the source `(. a)` is parsed
- **THEN** the dot leaf is retained as a child of the list node
- **AND** the diagnostics list is non-empty

#### Scenario: More than one datum after a dot

- **WHEN** the source `(a . b c)` is parsed
- **THEN** all of the leaves for `a`, the dot, `b`, and `c` are retained as
  children of the list node
- **AND** the diagnostics list is non-empty

### Requirement: Parsing does not guess at repairs

The parser SHALL NOT insert, remove, or substitute any token in order to make a
malformed input well-formed. It SHALL NOT synthesize a closing delimiter, and it
SHALL NOT drop a stray one.

#### Scenario: No delimiter is invented

- **WHEN** a source with an unclosed delimiter is parsed
- **THEN** no leaf exists that holds a token the reader did not produce

#### Scenario: No token is dropped to recover

- **WHEN** a source with an unexpected closing delimiter is parsed
- **THEN** the leaf holding that delimiter is present in the tree
