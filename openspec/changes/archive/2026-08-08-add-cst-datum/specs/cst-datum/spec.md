## ADDED Requirements

### Requirement: A CST projects to host Scheme data

The system SHALL provide an operation projecting a CST to ordinary values of the
host: pairs, vectors, bytevectors, symbols, strings, characters, numbers,
booleans, and the empty list.

The operation SHALL return two values: the top-level data in source order, and a
list of diagnostics.

It MUST NOT introduce a representation of its own for any datum that the host
already has a type for, so that comparing two projections requires no comparator
written by this project.

#### Scenario: A list projects to a pair chain

- **WHEN** the source `(a b c)` is projected
- **THEN** the result is a list of the symbols `a`, `b`, and `c`

#### Scenario: Each datum kind projects to its host type

- **WHEN** a source containing a list, a vector, a bytevector, a symbol, a
  string, a character, a number, a boolean, and `()` is projected
- **THEN** each is a value of the corresponding host type

#### Scenario: Several top-level data are returned in order

- **WHEN** the source `(a) (b)` is projected
- **THEN** two data are returned, the first for `(a)` and the second for `(b)`

### Requirement: The projection reads token values, not token text

Every leaf's contribution SHALL be the value the lexer computed for its token.
The projection MUST NOT re-parse token text, and therefore contains no number
parser, string unescaper, or character-name table of its own.

#### Scenario: Spelling is discarded as the lexer discarded it

- **WHEN** the sources `#xff` and `255` are projected
- **THEN** both yield the number 255

#### Scenario: Escapes are resolved by the lexer

- **WHEN** the sources `"\x41;"` and `"A"` are projected
- **THEN** both yield the string `A`

#### Scenario: Case folding is inherited, not implemented

- **WHEN** the source `#!fold-case\n(Foo)` is projected
- **THEN** the list contains the symbol `foo`
- **AND** the projection applies no folding of its own

### Requirement: Trivia contribute nothing to the projection

Whitespace, line comments, nested comments, directives, shebang lines, and `#;`
datum comments SHALL contribute no datum.

Because a `#;` datum comment is a single opaque leaf, the datum it elides SHALL
be absent from the projection without any rule that skips it.

#### Scenario: Comments do not appear in the data

- **WHEN** the source `(a ; note\n #| block |# b)` is projected
- **THEN** the result is a list of the symbols `a` and `b`

#### Scenario: A datum comment elides its datum

- **WHEN** the source `(a #;(b c) d)` is projected
- **THEN** the result is a list of the symbols `a` and `d`

#### Scenario: A source of only trivia projects to no data

- **WHEN** the source `; just a comment\n` is projected
- **THEN** no data are returned
- **AND** the diagnostics list is empty

### Requirement: Abbreviations expand

A prefix node for an abbreviation SHALL project to a two-element list whose
first element is the corresponding symbol and whose second is the projection of
the prefixed datum.

#### Scenario: Quote expands

- **WHEN** the source `'x` is projected
- **THEN** the result is the list `(quote x)`

#### Scenario: Every abbreviation expands to its symbol

- **WHEN** the sources `` `x ``, `,x`, `,@x`, `#'x`, `` #`x ``, `#,x`, and
  `#,@x` are projected
- **THEN** they yield lists headed by `quasiquote`, `unquote`,
  `unquote-splicing`, `syntax`, `quasisyntax`, `unsyntax`, and
  `unsyntax-splicing` respectively

#### Scenario: Abbreviations nest

- **WHEN** the source `''x` is projected
- **THEN** the result is the list `(quote (quote x))`

### Requirement: Improper lists project to improper pair chains

A list node whose dot is in a valid tail position SHALL project to a pair chain
whose final cdr is the projection of the datum after the dot.

#### Scenario: A dotted pair

- **WHEN** the source `(a . b)` is projected
- **THEN** the result is a pair whose car is `a` and whose cdr is `b`

#### Scenario: A dotted tail after several elements

- **WHEN** the source `(a b . c)` is projected
- **THEN** the result is a pair chain of `a` and `b` whose final cdr is `c`

### Requirement: Datum labels reconstruct a graph

A datum label SHALL bind its label number to the datum it prefixes, and a datum
reference SHALL project to the datum that label bound, including when that datum
contains the reference itself.

Label bindings SHALL be scoped to the top-level datum in which they appear, so a
label bound in one top-level datum is not visible in another.

#### Scenario: A reference to an earlier datum

- **WHEN** the source `(#0=(a) #0#)` is projected
- **THEN** the second element of the list is the same object as the first

#### Scenario: A cyclic structure is built

- **WHEN** the source `#0=(a . #0#)` is projected
- **THEN** the cdr of the result is the result itself
- **AND** the projection terminates

#### Scenario: A cyclic vector is built

- **WHEN** the source `#0=#(a #0#)` is projected
- **THEN** the second element of the vector is the vector itself

#### Scenario: Labels do not leak between top-level data

- **WHEN** the source `#0=1 #0#` is projected
- **THEN** the diagnostics list is non-empty, because the reference in the
  second top-level datum resolves against no binding

### Requirement: Defects invisible to the parser are reported as diagnostics

The projection SHALL report a diagnostic for each defect that structural parsing
cannot detect, carrying a message and the token concerned:

- a datum reference that resolves against no label binding
- a label number bound more than once within one top-level datum
- an element of a bytevector that is not an exact integer between 0 and 255
- a datum reference inside a bytevector, where no element can be patched

Diagnostics SHALL use the same representation the parser produces, so that a
caller merges the two lists rather than handling two mechanisms.

#### Scenario: An unresolvable reference

- **WHEN** the source `(#1#)` is projected
- **THEN** the diagnostics list is non-empty

#### Scenario: A duplicate label

- **WHEN** the source `#0=#0=1` is projected
- **THEN** the diagnostics list is non-empty

#### Scenario: A bytevector element that is not an octet

- **WHEN** the source `#vu8(300)` is projected
- **THEN** the diagnostics list is non-empty

#### Scenario: A reference inside a bytevector

- **WHEN** the source `#0=1 #vu8(#0#)` is projected
- **THEN** the diagnostics list is non-empty

#### Scenario: A diagnostic reports its token's position

- **WHEN** a projection diagnostic is produced
- **THEN** its line and column are the start line and start column of the token
  it concerns

### Requirement: A datum reported with diagnostics is not to be trusted

When the diagnostics list is non-empty, the returned data MAY be incomplete or
inaccurate, and consumers MUST NOT compare, format, or otherwise rely on them.

This licenses the projection to omit what it cannot represent rather than
inventing a placeholder.

#### Scenario: An unrepresentable bytevector element is omitted

- **WHEN** the source `#vu8(1 300 2)` is projected
- **THEN** the diagnostics list is non-empty
- **AND** no placeholder value stands in for the omitted element

### Requirement: The projection never raises

The projection SHALL return for every tree, whether or not that tree is clean.
Where a node cannot be projected it SHALL record a diagnostic and omit it.

#### Scenario: A malformed tree still projects

- **WHEN** the source `(a (b` is parsed and the resulting tree is projected
- **THEN** data are returned without an exception being raised

#### Scenario: A prefix with no datum

- **WHEN** the source `'` is parsed and the resulting tree is projected
- **THEN** data are returned without an exception being raised
- **AND** the diagnostics list is non-empty

### Requirement: The projection does not branch on dialect

The projection SHALL produce identical data for constructs that differ only in
dialect-specific spelling.

#### Scenario: Both bytevector spellings project alike

- **WHEN** the sources `#vu8(1 2)` and `#u8(1 2)` are projected
- **THEN** both yield the same bytevector

#### Scenario: Both boolean spellings project alike

- **WHEN** the sources `#t` and `#true` are projected
- **THEN** both yield true
